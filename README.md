# poc-lab

各種技術検証（PoC）をまとめたリポジトリ。

## 検証一覧

| 検証 | 概要 |
|---|---|
| [firehose-error-log-verify](./firehose-error-log-verify) | Amazon Data Firehose（S3 送信型）で、S3 配信失敗時に cloudwatch_logging_options で指定した本配信用ログストリームへエラーが記録されるかを検証する Terraform 一式 |
| [eventbridge-vended-log-verify](./eventbridge-vended-log-verify) | EventBridge のカスタム／デフォルトイベントバスから CloudWatch Logs への vended log delivery に必要な IAM 権限設定を、段階的に切り分けて確定する検証。クロスリージョン転送も含む |
| [eventbridge-connection-ignore-verify](./eventbridge-connection-ignore-verify) | EventBridge Connection の API Key を `lifecycle.ignore_changes` で無視した状態で、description だけを変更して apply したときに、コンソールで変更した API Key が TF 定義値へ巻き戻る（＝一緒に上書きされる）かを検証。結論: ignore していても UpdateConnection で巻き戻る |
