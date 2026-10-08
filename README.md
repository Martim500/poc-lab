# poc-lab

各種技術検証（PoC）をまとめたリポジトリ。

## 検証一覧

| 検証 | 概要 |
|---|---|
| [eventbridge-vended-log-verify](./eventbridge-vended-log-verify) | EventBridge イベントバスから CloudWatch Logs への Vended log delivery に必要な IAM 権限設定を切り分け、aws:SourceArn に入る正しい ARN 形式を実機で確定する Terraform 一式 |
| [firehose-error-log-verify](./firehose-error-log-verify) | Amazon Data Firehose（S3 送信型）で、S3 配信失敗時に cloudwatch_logging_options で指定した本配信用ログストリームへエラーが記録されるかを検証する Terraform 一式 |
