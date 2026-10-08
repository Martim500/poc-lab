output "event_bus_name" {
  description = "作成したイベントバス名"
  value       = aws_cloudwatch_event_bus.this.name
}

output "event_bus_arn" {
  description = "イベントバスの ARN"
  value       = aws_cloudwatch_event_bus.this.arn
}

output "log_group_name" {
  description = "宛先ロググループ名（ログイベント確認時に使用）"
  value       = aws_cloudwatch_log_group.this.name
}

output "log_group_arn" {
  description = "宛先ロググループの ARN"
  value       = aws_cloudwatch_log_group.this.arn
}

output "delivery_source_arn" {
  description = "delivery-source の ARN（aws:SourceArn に入る実際の値）"
  value       = aws_cloudwatch_log_delivery_source.info.arn
}

output "effective_source_arn_in_policy" {
  description = "現在のリソースポリシーで aws:SourceArn に設定している値"
  value       = local.source_arn_value
}

# PutEvents 用のサンプルコマンド（コピペ用）
output "put_events_cli_hint" {
  description = "イベントを流すための AWS CLI コマンド例"
  value       = <<-EOT
    aws events put-events --region ${var.region} --entries '[{"Source":"verify.test","DetailType":"VerifyEvent","Detail":"{\"msg\":\"hello\"}","EventBusName":"${aws_cloudwatch_event_bus.this.name}"}]'
  EOT
}
