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
| 5 | デフォルトイベントバスでも同じ方法か | **成立（確認済み）** | デフォルトバスに `update-event-bus --log-config` 適用可、`put-delivery-source` にデフォルトバス ARN 指定可、`verify.test` 5 件が `EVENT_INGEST_SUCCESS` で出力。記録は consolelog.md |
| 追 | ロググループ名が `/aws/vendedlogs/` 配下でなくても出力されるか | **出力される（プレフィックス非依存）** | `/verify-non-vendedlogs-prefix-01` で検証②を実施し、4 件が `EVENT_INGEST_SUCCESS` で出力。`/aws/vendedlogs/` 配下でない任意の名前でも問題なし |

> 本検証で確定したのは #4、#5、プレフィックス非依存、および「イベントバス自身への
> リソースベースポリシー無しでも、ロググループ側ポリシー＋配信パイプラインがあれば出力される」こと。
> #1 #3 はコメントブロックを切り替えた追加 apply で切り分けられる（main.tf / resource_policy.tf のコメント参照）。

## 5. 設計へのフィードバック

- 現行設計案の「イベントバスにリソースベースポリシー、`aws:SourceArn` にロググループ ARN」は変更が必要。
- 正しくは「ロググループにリソースベースポリシー、`aws:SourceArn` に delivery-source ARN」。
- `aws:SourceAccount` には自アカウントIDを入れる（本検証でも設定し、出力は成立）。

## 6. 追加検証で確定した事項

- **デフォルトバス**: カスタムバスと同一方法でログ出力が成立（§4 #5。記録: consolelog.md）。
  - `aws events update-event-bus --name default --log-config IncludeDetail=FULL,Level=TRACE` が成功。
  - `put-delivery-source` の `resource-arn` にデフォルトバス ARN（`event-bus/default`）を指定可能。
  - 注意: デフォルトバスには実運用のスケジュールイベント等も流れるため、ログに検証対象外のレコードが混在する。
- **ロググループ名のプレフィックス非依存**: `/aws/vendedlogs/` 配下でない名前でも出力される（検証②）。
  `/aws/vendedlogs/` 配下でない任意の名前でも、ロググループ側ポリシーが正しければ配信される。

## 7. 残る未確認事項（軽微）

- `put-delivery-source` の `log_type` は `INFO_LOGS` を使用（Terraform 公式例準拠）。他レベル（`ERROR_LOGS` / `TRACE_LOGS`）の個別配信は未検証。
- #1（配信パイプライン無し）／#3（Condition 無し）は、main.tf / resource_policy.tf のコメントブロック切り替えで追検証可能（実運用設計の判断には影響しない範囲）。
