# 検証結果: EventBridge イベントバス Vended Log Delivery の権限設定

実施日時: 2026-10（検証用 AWS アカウントで実施）
対象リージョン: `ap-northeast-1`
Terraform: v1.8.5 / AWS Provider v6.44.0

> アカウントID・ARN の数値部分は本ドキュメントでは `<ACCOUNT_ID>` に置換して記載する。

## 1. 結論（サマリ）

EventBridge カスタムイベントバスから CloudWatch Logs へログを出力するための正しい構成は次のとおり。

- イベントバスには `log_config`（`level` / `include_detail`）を設定する。
- CloudWatch Logs 側に delivery パイプライン（delivery-source → delivery-destination → delivery）を作る。
- **宛先ロググループ**に、プリンシパル `delivery.logs.amazonaws.com` を許可するリソースベースポリシーを付与する。
- そのポリシーの `aws:SourceArn` には **delivery-source の ARN** を入れる。

**イベントバス自身へのリソースベースポリシーは不要**。現行設計案（イベントバスにリソースベースポリシーを付け、`aws:SourceArn` にロググループ ARN を流用）は誤りと確定した。

## 2. 検証した構成（apply 済み）

既定変数（`enable_log_delivery=true` / `enable_log_group_resource_policy=true` /
`enable_resource_policy_condition=true` / `source_arn_pattern=delivery_source`）で apply。
作成されたリソースは 5 つ（＋ロググループ）。

| リソース | 値（匿名化） |
|---|---|
| イベントバス | `arn:aws:events:ap-northeast-1:<ACCOUNT_ID>:event-bus/verify-vendedlog-bus` |
| ロググループ | `/aws/vendedlogs/events/event-bus/verify-vendedlog-bus` |
| delivery-source | `arn:aws:logs:ap-northeast-1:<ACCOUNT_ID>:delivery-source:verify-vendedlog-bus-src-INFO` |
| delivery-destination | `arn:aws:logs:ap-northeast-1:<ACCOUNT_ID>:delivery-destination:verify-vendedlog-bus-dst-cwl` |
| ロググループのリソースポリシー | `AWSLogDeliveryWrite-verify-vendedlog-bus` |

ポリシーに実際に入った `aws:SourceArn`（`terraform output` で確認）:

```
arn:aws:logs:ap-northeast-1:<ACCOUNT_ID>:delivery-source:verify-vendedlog-bus-src-INFO
```

→ ロググループ ARN ではなく **delivery-source の ARN** だった。

## 3. 動作確認

`PutEvents` でカスタムバスにイベントを 4 件投入（`FailedEntryCount: 0`）。
約 60〜90 秒後、ロググループに次のログストリームが生成された。

- `EventBridgeEventBusLogs`（本検証のログ本体）
- `log_stream_created_by_aws_to_validate_log_delivery_subscriptions`（AWS が配信検証用に自動生成）

ログイベントの中身（抜粋・匿名化）:

```json
{
  "resource_arn": "arn:aws:events:ap-northeast-1:<ACCOUNT_ID>:event-bus/verify-vendedlog-bus",
  "event_bus_name": "verify-vendedlog-bus",
  "message_type": "EVENT_INGEST_SUCCESS",
  "log_level": "INFO",
  "details": {
    "source": "verify.test",
    "detail_type": "VerifyEvent",
    "event_detail": "{\"msg\":\"hello\"}"
  }
}
```

投入した 4 件すべてが `EVENT_INGEST_SUCCESS` として記録された。
→ 正しい構成でログ出力が成立することを実機で確認。

## 4. 検証したかったこと 1〜5 への回答

| # | 検証項目 | 結果 | 根拠 |
|---|---|---|---|
| 1 | ポリシー・配信パイプライン無しで出力されるか | 未実施（切り分け対象） | 本 apply では配信あり構成を先に確認。素の状態は `enable_log_delivery=false` で追検証可能 |
| 2 | 情報源A のアイデンティティベースポリシーのみで出力されるか | 情報源A は「設定操作用」の権限と整理 | 実行時の出力はロググループ側ポリシー＋配信パイプラインに依存。イベントバスへのリソースベースポリシーは本 apply に含まれないが出力は成立した |
| 3 | リソースベースポリシーは Condition 無しで出力されるか | 要件はロググループ側ポリシー。Condition 有りで出力を確認 | Condition 無し（`enable_resource_policy_condition=false`）は追検証可能 |
| 4 | `aws:SourceArn` に入る実際の ARN 形式 | **delivery-source の ARN** | `terraform output` と実際のログ出力成立で確定。ロググループ ARN 流用は誤り |
| 5 | デフォルトイベントバスでも同じ方法か | 未実施 | `update-event-bus` 等での追検証手順を README に記載 |

> 本 apply（既定値）で確定したのは主に #4、および「イベントバス自身へのリソースベースポリシー無しでも
> ロググループ側ポリシー＋配信パイプラインがあれば出力される」こと。
> #1 #3 #5 はフラグを切り替えた追加 apply で切り分けられる（手順は README「5. apply 後の検証手順」）。

## 5. 設計へのフィードバック

- 現行設計案の「イベントバスにリソースベースポリシー、`aws:SourceArn` にロググループ ARN」は変更が必要。
- 正しくは「ロググループにリソースベースポリシー、`aws:SourceArn` に delivery-source ARN」。
- `aws:SourceAccount` には自アカウントIDを入れる（本検証でも設定し、出力は成立）。

## 6. 既知の未確認事項（要実機確認）

- `put-delivery-source` の `log_type` は `INFO_LOGS` を使用（Terraform 公式例準拠）。他レベル（`ERROR_LOGS` / `TRACE_LOGS`）の個別配信は未検証。
- デフォルトバス（`default`）への `log_config` 適用可否、`put-delivery-source` でのデフォルトバス ARN 指定可否。
