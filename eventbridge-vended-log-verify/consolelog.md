# デフォルトイベントバス 検証ログ（CloudShell 実行記録）

残件1「デフォルトバスでもカスタムバスと同じ方法で vended log delivery が通るか」を
AWS CloudShell（ap-northeast-1）で検証した際の実行記録。

- アカウントID は `{ACCOUNT_ID}` に置換してある。
- 検証と無関係な、このアカウントの実運用リソース（`aws.events` 由来の Scheduled Event や
  各 Lambda への配信ログ）はノイズのため除去し、`[検証と無関係な既存ルールのログは省略]` と記載。
- 残しているのは検証で投入した `source: verify.test` のイベントログ。

---

## 手順1: 共通変数の設定

**入力**
```bash
export AWS_DEFAULT_REGION=ap-northeast-1
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
LG=/aws/vendedlogs/events/event-bus/default
echo "ACCOUNT_ID=$ACCOUNT_ID"
echo "LOG_GROUP=$LG"
```

**出力**
```
ACCOUNT_ID={ACCOUNT_ID}
LOG_GROUP=/aws/vendedlogs/events/event-bus/default
```

---

## 手順2: デフォルトバスの log_config を設定

**入力**
```bash
aws events update-event-bus --name default --log-config IncludeDetail=FULL,Level=TRACE
```

**出力**
```json
{
    "Arn": "arn:aws:events:ap-northeast-1:{ACCOUNT_ID}:event-bus/default",
    "Name": "default",
    "LogConfig": {
        "IncludeDetail": "FULL",
        "Level": "TRACE"
    }
}
```

→ デフォルトバスにも log_config を適用できる（カスタムバス固有ではない）。

---

## 手順3: delivery-source の確認（デフォルトバス ARN 指定）

**入力**
```bash
aws logs get-delivery-source --name default-bus-src-INFO
```

**出力**
```json
{
    "deliverySource": {
        "name": "default-bus-src-INFO",
        "arn": "arn:aws:logs:ap-northeast-1:{ACCOUNT_ID}:delivery-source:default-bus-src-INFO",
        "resourceArns": [
            "arn:aws:events:ap-northeast-1:{ACCOUNT_ID}:event-bus/default"
        ],
        "service": "events",
        "logType": "INFO_LOGS"
    }
}
```

→ `put-delivery-source` の resource-arn にデフォルトバス ARN（`event-bus/default`）を指定できる。

---

## 手順4: 宛先ロググループの作成

**入力**
```bash
aws logs create-log-group --log-group-name "$LG"
aws logs put-retention-policy --log-group-name "$LG" --retention-in-days 1
```

**出力**
```
（出力なし＝成功）
```

---

## 手順5: ロググループのリソースポリシー付与

**入力**
```bash
cat > default-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowVendedLogDelivery",
      "Effect": "Allow",
      "Principal": { "Service": "delivery.logs.amazonaws.com" },
      "Action": ["logs:CreateLogStream", "logs:PutLogEvents"],
      "Resource": "arn:aws:logs:ap-northeast-1:${ACCOUNT_ID}:log-group:${LG}:log-stream:*",
      "Condition": {
        "StringEquals": { "aws:SourceAccount": "${ACCOUNT_ID}" },
        "ArnLike": { "aws:SourceArn": "arn:aws:logs:ap-northeast-1:${ACCOUNT_ID}:delivery-source:default-bus-src-INFO" }
      }
    }
  ]
}
EOF

aws logs put-resource-policy --policy-name AWSLogDeliveryWrite-default-bus \
  --policy-document file://default-policy.json
```

**出力（要点）**
```json
{
    "resourcePolicy": {
        "policyName": "AWSLogDeliveryWrite-default-bus",
        "policyScope": "ACCOUNT"
    }
}
```

→ ポリシーの `aws:SourceArn` には delivery-source の ARN を設定（カスタムバスと同じ形式）。

---

## 手順6: delivery-destination と delivery の作成

**入力**
```bash
aws logs put-delivery-destination --name default-bus-dst-cwl \
  --delivery-destination-configuration "destinationResourceArn=arn:aws:logs:ap-northeast-1:${ACCOUNT_ID}:log-group:${LG}"

aws logs create-delivery --delivery-source-name default-bus-src-INFO \
  --delivery-destination-arn arn:aws:logs:ap-northeast-1:${ACCOUNT_ID}:delivery-destination:default-bus-dst-cwl
```

**出力（要点）**
```json
{
    "deliveryDestination": {
        "name": "default-bus-dst-cwl",
        "arn": "arn:aws:logs:ap-northeast-1:{ACCOUNT_ID}:delivery-destination:default-bus-dst-cwl",
        "deliveryDestinationType": "CWL"
    }
}
```
```json
{
    "delivery": {
        "id": "{DELIVERY_ID}",
        "deliverySourceName": "default-bus-src-INFO",
        "deliveryDestinationArn": "arn:aws:logs:ap-northeast-1:{ACCOUNT_ID}:delivery-destination:default-bus-dst-cwl",
        "deliveryDestinationType": "CWL"
    }
}
```

---

## 手順7: デフォルトバスへイベント投入（5 回）

**入力**
```bash
cat > event-default.json <<'EOF'
[{"Source":"verify.test","DetailType":"VerifyEvent","Detail":"{\"msg\":\"default-bus\"}","EventBusName":"default"}]
EOF

for i in 1 2 3 4 5; do
  aws events put-events --entries file://event-default.json
  sleep 2
done
```

**出力**
```
各回とも FailedEntryCount: 0（EventId 発行）
```

---

## 手順8: ログ確認

**入力**
```bash
sleep 150
aws logs describe-log-streams --log-group-name "$LG" --order-by LastEventTime --descending \
  --query "logStreams[].logStreamName" --output text

aws logs get-log-events --log-group-name "$LG" \
  --log-stream-name EventBridgeEventBusLogs --start-from-head \
  --query "events[].message" --output text
```

**出力（ストリーム一覧）**
```
EventBridgeEventBusLogs	log_stream_created_by_aws_to_validate_log_delivery_subscriptions
```

**出力（ログイベント／検証投入分のみ抜粋・匿名化）**

`[検証と無関係な既存ルール（aws.events の Scheduled Event と各 Lambda への配信ログ）は省略]`

投入した `verify.test` のイベントは、5 件すべて `EVENT_INGEST_SUCCESS` で記録された（1 件分を代表例として掲載）:

```json
{
  "resource_arn": "arn:aws:events:ap-northeast-1:{ACCOUNT_ID}:event-bus/default",
  "event_bus_name": "default",
  "event_id": "{EVENT_ID}",
  "message_type": "EVENT_INGEST_SUCCESS",
  "log_level": "INFO",
  "details": {
    "caller_account_id": "{ACCOUNT_ID}",
    "source": "verify.test",
    "detail_type": "VerifyEvent",
    "resources": [],
    "event_detail": "{\"msg\":\"default-bus\"}"
  }
}
```

各 `verify.test` イベントの直後には `NO_STANDARD_RULES_MATCHED`（ルール未設定のため）も記録された。

---

## 結論（残件1）

- デフォルトバスでも `log_config` 設定・delivery パイプライン・ロググループ側リソースポリシー
  （`aws:SourceArn`=delivery-source ARN）という**カスタムバスと同一の方法でログ出力が成立**した。
- 投入した `verify.test` 5 件すべてが `EVENT_INGEST_SUCCESS` として記録された。
- デフォルトバスには実運用のスケジュールイベント等も流れるため、ログには検証対象外のレコードも
  混在する点に注意（本記録では省略）。

## 後片付け（デフォルトバスは削除しない）

```bash
DID=$(aws logs describe-deliveries --query "deliveries[?deliverySourceName=='default-bus-src-INFO'].id" --output text)
[ -n "$DID" ] && aws logs delete-delivery --id "$DID"
aws logs delete-delivery-destination --name default-bus-dst-cwl
aws logs delete-delivery-source --name default-bus-src-INFO
aws logs delete-resource-policy --policy-name AWSLogDeliveryWrite-default-bus
aws logs delete-log-group --log-group-name "$LG"
# デフォルトバスの log_config を OFF に戻す（バス自体は削除しない）
aws events update-event-bus --name default --log-config Level=OFF
```
