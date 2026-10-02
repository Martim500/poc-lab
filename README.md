# poc-lab

各種技術検証（PoC）をまとめたリポジトリ。

## 検証一覧

| 検証 | 概要 |
|---|---|
| [firehose-error-log-verify](./firehose-error-log-verify) | Amazon Data Firehose（S3 送信型）で、S3 配信失敗時に cloudwatch_logging_options で指定した本配信用ログストリームへエラーが記録されるかを検証する Terraform 一式 |
