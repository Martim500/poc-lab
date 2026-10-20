# クロスリージョン転送 実演手順（CloudShell / 東京・バージニア北部）

一時ファイル。us-east-1 デフォルトバス → 東京カスタムバス転送 → 東京でログ配信、を検証する。

## 構築済みリソース（demo-xregion / Terraform 管理 = C:\work\eb-xregion）

| 項目 | 値 |
|---|---|
| 東京カスタムバス | `xregion-tokyo-bus`（ap-northeast-1） |
| 東京ロググループ | `/aws/vendedlogs/events/event-bus/xregion-tokyo-bus` |
| delivery-source | `xregion-tokyo-src-INFO`（INFO_LOGS, resource=東京バス） |
| delivery-destination | `xregion-tokyo-dst-cwl` |
| delivery | `WPH9eklge7lVCV0g`（source→destination 紐付け済み） |
| ロググループ側ポリシー | `AWSLogDeliveryWrite-xregion-tokyo`（SourceArn=ロググループ ARN） |
| 受信側バスポリシー | `AllowCrossRegionPutEventsSameAccount`（events:PutEvents。`enable_receiver_bus_policy=true` で付与中） |
| us-east-1 ルール | `xregion-health-global-fwd`（source=verify.test を東京へ転送） |
| 転送用 IAM ロール | `xregion-forward-role` |
| アカウント | `123456789012` |

> 配信パイプライン（source/destination/delivery）とロググループ側ポリシーは構築済み。
> **残るは東京バスの log_config を有効化するだけ**（import 由来で実機が null のため CLI で設定）。

一意文字列は手動で `20261009-0001` のように採番する。送った文字列でログを検索すれば一目で判別できる。

---

## 事前（1回だけ）: 東京カスタムバスの log_config を有効化

ローカル AWS CLI は v2.15 で `update-event-bus` 非対応。**CloudShell（ap-northeast-1）** で実行する。

```bash
aws events update-event-bus \
  --name xregion-tokyo-bus \
  --log-config IncludeDetail=FULL,Level=TRACE \
  --region ap-northeast-1
```

確認（LogConfig が null でなく FULL/TRACE になっていること）:
```bash
aws events describe-event-bus --name xregion-tokyo-bus --region ap-northeast-1 \
  --query "LogConfig" --output json
```
→ `{"IncludeDetail":"FULL","Level":"TRACE"}` が出れば OK。

---

## 1. ログ配信（us-east-1 にイベントを流す → 東京へ転送される）

### 一意文字列（MSG）の形式

デフォルトバスには他のイベント（スケジュール等）も流れるため、**衝突しない長い一意文字列**を使う。
形式: `XREGION-VERIFY-<YYYYMMDD>-<HHMMSS>-<ランダム8桁>`

例: `XREGION-VERIFY-20261009-153045-a7f3c9e2`

- `XREGION-VERIFY` … 検証用途が一目でわかる固定プレフィックス（絞り込み用）
- `20261009-153045` … 日付+時刻（いつ流したか一目でわかる）
- `a7f3c9e2` … ランダム8桁（同じ秒に複数流しても衝突しない）

これなら `filter-log-events` で `XREGION-VERIFY`（全件）でも、特定の1件（完全一致）でも検索でき、
他のノイズと絶対に混ざらない。

### CloudShell（bash）: 一意文字列を自動生成して送る

```bash
# 一意文字列を自動生成（日時 + ランダム8桁）
MSG="XREGION-VERIFY-$(date -u +%Y%m%d-%H%M%S)-$(openssl rand -hex 4)"
echo "送った文字列: $MSG"

aws events put-events --region us-east-1 \
  --entries "[{\"Source\":\"verify.test\",\"DetailType\":\"VerifyEvent\",\"Detail\":\"{\\\"id\\\":\\\"$MSG\\\"}\",\"EventBusName\":\"default\"}]"
```

> `openssl` が無い環境なら `$RANDOM$RANDOM` でも可:
> `MSG="XREGION-VERIFY-$(date -u +%Y%m%d-%H%M%S)-$RANDOM$RANDOM"`

### ローカル PowerShell で送る場合（file:// 方式が確実）

```powershell
$env:AWS_PROFILE = "<your-profile>"; $env:AWS_PAGER = ""
$msg = "XREGION-VERIFY-{0}-{1:x8}" -f (Get-Date -Format "yyyyMMdd-HHmmss"), (Get-Random)
Write-Host "送った文字列: $msg"
"[{`"Source`":`"verify.test`",`"DetailType`":`"VerifyEvent`",`"Detail`":`"{\`"id\`":\`"$msg\`"}`",`"EventBusName`":`"default`"}]" | Set-Content -Encoding utf8 ev.json
aws events put-events --region us-east-1 --entries file://ev.json
```

→ `FailedEntryCount: 0` なら投入成功。**送った文字列（MSG）を控えておく。**

### 確認（2〜3分後。東京のロググループを、送った文字列で検索）

```bash
# 控えた MSG をそのまま使う（例を自分の値に置換）
aws logs filter-log-events --region ap-northeast-1 \
  --log-group-name /aws/vendedlogs/events/event-bus/xregion-tokyo-bus \
  --filter-pattern '"XREGION-VERIFY-20261009-153045-a7f3c9e2"' \
  --query "events[].message" --output text
```

プレフィックスで全件まとめて見たい場合:
```bash
aws logs filter-log-events --region ap-northeast-1 \
  --log-group-name /aws/vendedlogs/events/event-bus/xregion-tokyo-bus \
  --filter-pattern '"XREGION-VERIFY"' \
  --query "events[].message" --output text
```

→ 送った文字列を含むレコードが出れば「**us-east-1 → 東京転送 ＋ 東京でログ配信**」が成功（＝受信側ポリシーありで成功）。

> 初回はログストリーム生成に数分（最大 5〜10 分）かかることがある。
> ストリームが出来るまでは空。待って再検索する。

---

## 2. ロググループ側で指定している aws:SourceArn の表示（任意）

```bash
aws logs describe-resource-policies --region ap-northeast-1 \
  --query "resourcePolicies[?policyName=='AWSLogDeliveryWrite-xregion-tokyo'].policyDocument" \
  --output text
```
→ `aws:SourceArn` にロググループ ARN が入っていることを確認できる。

---

## 3. 受信側バスポリシーを削除（同一アカウントなら不要か検証）

**方法A（推奨）: Terraform トグルで削除**（担当者 = AI 側で実施可能）
`enable_receiver_bus_policy = false` で apply すると
`aws_cloudwatch_event_bus_policy.receiver` が destroy される。

**方法B: CloudShell で直接削除**
```bash
aws events remove-permission \
  --event-bus-name xregion-tokyo-bus \
  --statement-id AllowCrossRegionPutEventsSameAccount \
  --region ap-northeast-1
```
削除後の確認（Policy が消えていること）:
```bash
aws events describe-event-bus --name xregion-tokyo-bus --region ap-northeast-1 \
  --query "Policy" --output text
```
→ `None` / 空になれば削除成功。

> 方法B で消すと Terraform state と実機がズレる。あとで `enable_receiver_bus_policy=false` で
> apply して state を合わせるか、再度 true で apply して戻すこと。

---

## 4. 再度ログ配信（ポリシー無しでも転送されるか）

手順1と同じ要領で、**新しい一意文字列**を自動生成して送る（手順1と区別するため、
別の時刻・別のランダム値になるので自然に別物になる）。
```bash
MSG="XREGION-VERIFY-$(date -u +%Y%m%d-%H%M%S)-$(openssl rand -hex 4)"
echo "送った文字列: $MSG"

aws events put-events --region us-east-1 \
  --entries "[{\"Source\":\"verify.test\",\"DetailType\":\"VerifyEvent\",\"Detail\":\"{\\\"id\\\":\\\"$MSG\\\"}\",\"EventBusName\":\"default\"}]"
```
> 控えた MSG を手順1の分と区別してメモしておく（ポリシー削除「後」に送った方）。

確認（2〜3分後。控えた「後」の MSG で検索。例を自分の値に置換）:
```bash
aws logs filter-log-events --region ap-northeast-1 \
  --log-group-name /aws/vendedlogs/events/event-bus/xregion-tokyo-bus \
  --filter-pattern '"XREGION-VERIFY-20261009-154210-b2d8f1a0"' \
  --query "events[].message" --output text
```

判定:
- **「後」の MSG が出る** → 受信側バスポリシー無しでも転送成功。同一アカウント内のクロスリージョン転送は
  送信側 IAM ロール（events:PutEvents）だけで成立し、受信側バスポリシーは不要（制限用途の任意手段）。
- **「後」の MSG が出ない** → 受信側バスポリシーが必要だった。

> 注意: 手順1（削除「前」）の MSG はポリシーありで配信済みなので、検索すると当然出る。
> 判定に使うのは必ず「削除後に送った新しい MSG」。前後の MSG を取り違えないこと。

---

## ノイズ対策（重要）

- デフォルトバス／カスタムバスには `aws.events` のスケジュールイベント等が混ざる。
- 必ず「送った一意文字列（例: `XREGION-VERIFY-20261009-153045-a7f3c9e2`）」で `filter-log-events` すること。
- `source=verify.test` かつ `event_detail` に自分の id が入っているレコードだけが検証対象。

## 期待されるログの形（抜粋）

```json
{
  "resource_arn": "arn:aws:events:ap-northeast-1:123456789012:event-bus/xregion-tokyo-bus",
  "event_bus_name": "xregion-tokyo-bus",
  "message_type": "EVENT_INGEST_SUCCESS",
  "log_level": "INFO",
  "details": {
    "source": "verify.test",
    "detail_type": "VerifyEvent",
    "event_detail": "{\"id\":\"20261009-0001\"}"
  }
}
```
