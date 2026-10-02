# Amazon Data Firehose（S3 送信型）配信失敗時のエラーログ検証環境

CloudWatch Logs → サブスクリプションフィルター → Firehose → S3 の構成で、
**S3 への配信に失敗したとき、`cloudwatch_logging_options` で指定した本配信用ログストリームに
エラーが記録されるか**を検証するための Terraform 一式。

## この検証でわかること

- S3 配信失敗時、Firehose の CloudWatch error logging で指定したロググループ／ストリーム
  （本配信用ストリーム＝DestinationDelivery）にエラーが記録されるか
- 記録されるエラーコード・本文の内容
- 失敗時のメトリクス挙動（`IncomingRecords` は届くが `DeliveryToS3.Success` が 0 に落ちる等）
- 配信失敗（Delivery エラー）と処理失敗（Processing エラー）の出力先の違い
  （Delivery 失敗は本配信用ストリームに記録され、`error_output_prefix`＝`errors/` には出ない）
- 失敗要因（S3 書き込み権限の剥奪 または バケットポリシーの Deny）を解除したあと、
  再試行で欠損なく S3 に保存されるか

## 構成（Terraform で作成するリソース）

| リソース | 名前 | 備考 |
|---|---|---|
| S3 バケット | `fhverify-logs-<アカウントID>` | SSE-S3、パブリックアクセスブロック全有効、`force_destroy = true` |
| ソース用ロググループ | `/fhverify/source-01` | 保持 1 日 |
| ソース用ログストリーム | `test-01` | ここに手動でログ投入する |
| エラーログ用ロググループ | `/fhverify-log-firehose-error-01` | 保持 1 日 |
| エラーログ用ログストリーム | `fhverify-stream-s3-01` | Firehose の error logging 先 |
| Firehose 配信ロール | `fhverify-role-firehose` | S3 書き込み／Logs 出力 |
| CloudWatch Logs → Firehose ロール | `fhverify-role-cwlogs-firehose` | サブスクリプションフィルター用 |
| Firehose | `fhverify-stream-s3-01` | extended_s3、GZIP、`.json.gz`、Asia/Tokyo、processing 3 段 |
| サブスクリプションフィルター | `fhverify-sub-source-01` | `/fhverify/source-01` → Firehose（全件） |

- リージョン: `ap-northeast-1`
- Terraform AWS Provider: `>= 6.44.0`
- バケット名のアカウントID部分は `data.aws_caller_identity` で自動取得（直書きなし）
- 全タグ対応リソースに `verify = true` を付与（provider の `default_tags`）

### Firehose の processing_configuration

1. `Decompression`（GZIP）… CloudWatch Logs のペイロードを解凍
2. `CloudWatchLogProcessing`（`DataMessageExtraction = true`）… message だけを抽出
3. `AppendDelimiterToRecord` … レコードごとに改行を付与（NDJSON 化）

## 前提・必要権限

Terraform を apply できる権限を持つユーザーで実行すること。
**権限が不足する場合は、Terraform を apply できるユーザーを使用するか、専用ポリシーを作成してください。**
本検証に必要な最小権限の例は `iam-policy-required.json` に JSON で用意してある（参照用）。

> MFA 必須の Deny ポリシーがアタッチされたユーザーだと CLI 実行が拒否されることがある。
> その場合は MFA セッションを使うか、別の実行用ユーザー／プロファイルで実行する。

## セットアップ

```bash
# 認証プロファイルを指定（例）
export AWS_PROFILE=<your-profile>   # PowerShell: $env:AWS_PROFILE = "<your-profile>"

terraform init
terraform plan
terraform apply
```

apply 後、出力（outputs）にバケット名・Firehose ARN・各ロググループ名が表示される。

---

## 検証手順

> ログ投入・S3 確認は AWS CLI（またはコンソール／CloudShell）で行う。
> message には後で照合できる一意な文字列（`verify-ok-001` 等）を入れる。

### 事前確認（失敗させる前に必ず実施）

1. Firehose の設定確認（指定ストリームが実在し、error logging が有効なこと）

```bash
aws firehose describe-delivery-stream \
  --delivery-stream-name fhverify-stream-s3-01 \
  --query "DeliveryStreamDescription.Destinations[0].ExtendedS3DestinationDescription.CloudWatchLoggingOptions"
```

2. 正常系：ログを投入する

```bash
aws logs put-log-events \
  --log-group-name /fhverify/source-01 \
  --log-stream-name test-01 \
  --log-events timestamp=$(($(date +%s)*1000)),message="verify-ok-001" \
               timestamp=$(($(date +%s)*1000)),message="verify-ok-002" \
               timestamp=$(($(date +%s)*1000)),message="verify-ok-003"
```

3. 5〜10 分後、S3 の prefix 側にオブジェクトができることを確認（Asia/Tokyo 基準のパス）

```bash
aws s3 ls s3://fhverify-logs-<アカウントID>/applogs/sample-stream-01/ --recursive
```

4. ダウンロードして展開し、message が 1 行ずつ並ぶこと（外枠が消えていること）を確認

```bash
aws s3 cp s3://fhverify-logs-<アカウントID>/<オブジェクトキー> ./out.json.gz
gunzip -c out.json.gz
```

### 失敗系（本題：エラーログが本配信用ストリームに記録されるか）

失敗のさせ方は 2 通り。どちらかを実施する。

**(A) IAM ロールの S3 書き込み権限を外す**

`fhverify-role-firehose` のインラインポリシーから `s3:PutObject` と
`s3:AbortMultipartUpload` を一時的に削除する（コンソール or CLI）。
→ 復旧は `terraform apply` でコード定義どおりに戻せる。

**(B) バケットポリシーで Deny を付与**

```bash
aws s3api put-bucket-policy \
  --bucket fhverify-logs-<アカウントID> \
  --policy '{
    "Version": "2012-10-17",
    "Statement": [{
      "Sid": "DenyFirehosePut",
      "Effect": "Deny",
      "Principal": {"AWS": "arn:aws:iam::<アカウントID>:role/fhverify-role-firehose"},
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::fhverify-logs-<アカウントID>/*"
    }]
  }'
```

### ログ投入（失敗中。5 分おきに 3〜4 回）

```bash
aws logs put-log-events \
  --log-group-name /fhverify/source-01 \
  --log-stream-name test-01 \
  --log-events timestamp=$(($(date +%s)*1000)),message="verify-fail-001" \
               timestamp=$(($(date +%s)*1000)),message="verify-fail-002" \
               timestamp=$(($(date +%s)*1000)),message="verify-fail-003"
```

### 確認（投入開始から 30 分間）

本配信用エラーログ（本題）:

```bash
aws logs get-log-events \
  --log-group-name /fhverify-log-firehose-error-01 \
  --log-stream-name fhverify-stream-s3-01 \
  --start-from-head
```

ロググループ内の全ストリーム（記録先が違う可能性の確認）:

```bash
aws logs describe-log-streams --log-group-name /fhverify-log-firehose-error-01
```

メトリクス（データ到達と配信失敗の確認）:

```bash
# IncomingRecords / DeliveryToS3.Records / DeliveryToS3.Success を順に取得
aws cloudwatch get-metric-statistics \
  --namespace AWS/Firehose \
  --metric-name IncomingRecords \
  --dimensions Name=DeliveryStreamName,Value=fhverify-stream-s3-01 \
  --start-time <開始UTC> --end-time <終了UTC> \
  --period 300 --statistics Sum
```

S3 の errors/ 側（Processing 失敗が出ていないかの確認）:

```bash
aws s3 ls s3://fhverify-logs-<アカウントID>/errors/ --recursive
```

> 注意：Firehose のバッファは `buffering_interval = 300`（5 分）。
> 投入直後は失敗試行がまだ走っておらず、エラーログに出ない。
> 投入の約 5 分後にフラッシュ試行→失敗→エラーログ記録、という流れになる。

### 復旧確認（再試行で欠損なく届くか）

- (A) の場合：`terraform apply` でロールのポリシーを元に戻す
- (B) の場合：バケットポリシーを削除する

```bash
aws s3api delete-bucket-policy --bucket fhverify-logs-<アカウントID>
```

解除後 10〜15 分以内に、失敗中に投入した `verify-fail-xxx` が prefix 側に
欠損なく保存されるかを照合する。

```bash
aws s3 ls s3://fhverify-logs-<アカウントID>/applogs/sample-stream-01/ --recursive
```

## 判定・報告のポイント

- エラーログが記録された場合：記録時刻、`errorCode`、`message` 本文
- 記録されなかった場合：`IncomingRecords` と `DeliveryToS3.Success` の値、
  describe の `CloudWatchLoggingOptions`、ロググループ内の全ストリーム名を添える
- Delivery 失敗（例 `S3.AccessDenied`）は本配信用ストリームに記録され、
  `errors/`（`error_output_prefix`）には出ないことに注意

## 参考（AWS 公式ドキュメント）

この検証の根拠・元ネタになる公式ドキュメント。

- [CloudWatch Logs を使用して Amazon Data Firehose をモニタリングする](https://docs.aws.amazon.com/ja_jp/firehose/latest/dev/monitoring-with-cloudwatch-logs.html)
  … 主送信先への配信エラーが `DestinationDelivery` ログストリームに記録される、という本検証の核心部分
- [CloudWatch メトリクスを使用して Amazon Data Firehose をモニタリングする](https://docs.aws.amazon.com/firehose/latest/dev/monitoring-with-cloudwatch-metrics.html)
  … `IncomingRecords` / `DeliveryToS3.Success` などのメトリクス定義
- [CloudWatch Logs を解凍する（Decompression）](https://docs.aws.amazon.com/ja_jp/firehose/latest/dev/writing-with-cloudwatch-logs-decompression.html)
  … `processing_configuration` の Decompression の説明
- [解凍後のメッセージ抽出（Message extraction）](https://docs.aws.amazon.com/firehose/latest/dev/Message_extraction.html)
  … `DataMessageExtraction` で message だけを抽出し、外枠メタデータを除去する挙動
- [CloudWatch Logs サブスクリプションフィルター](https://docs.aws.amazon.com/ja_jp/AmazonCloudWatch/latest/logs/SubscriptionFilters.html)
  … ロググループ → Firehose へログを流す仕組み
- [Firehose と Amazon S3 間のデータ配信失敗のトラブルシューティング（AWS ナレッジセンター）](https://repost.aws/knowledge-center/kinesis-delivery-failure-s3)
  … S3 配信失敗時にエラーログを有効化して切り分ける手順
- [Terraform: aws_kinesis_firehose_delivery_stream（公式レジストリ）](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kinesis_firehose_delivery_stream)
  … `extended_s3_configuration` / `processing_configuration` / `cloudwatch_logging_options` の定義

## 後片付け

```bash
terraform destroy
```

> バケットにオブジェクトが残っていると `force_destroy` が削除を試みる。
> 実行ユーザーに `s3:DeleteObject` 権限が必要（バージョニング有効時は `s3:DeleteObjectVersion` も）。
> 権限不足で失敗する場合は、先に `aws s3 rm s3://<bucket>/ --recursive` でオブジェクトを削除してから
> 再度 `terraform destroy` を実行する。
