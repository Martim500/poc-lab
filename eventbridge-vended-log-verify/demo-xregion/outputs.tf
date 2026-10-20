output "tokyo_bus_name" {
  value = aws_cloudwatch_event_bus.tokyo.name
}

output "tokyo_log_group" {
  value = aws_cloudwatch_log_group.tokyo.name
}

output "us_east_1_rule" {
  value = aws_cloudwatch_event_rule.use1_fwd.name
}

output "receiver_bus_policy_enabled" {
  value = var.enable_receiver_bus_policy
}

# us-east-1 のデフォルトバスへイベントを流すコマンド（これが東京へ転送される）
output "put_events_us_east_1" {
  value = <<-EOT
    aws events put-events --region us-east-1 --entries '[{"Source":"verify.test","DetailType":"VerifyEvent","Detail":"{\"msg\":\"xregion-test\"}","EventBusName":"default"}]'
  EOT
}

# 東京のロググループでログを確認するコマンド
output "check_tokyo_logs" {
  value = <<-EOT
    aws logs filter-log-events --region ap-northeast-1 --log-group-name ${local.log_group_name} --filter-pattern '"xregion-test"' --query "events[].message" --output text
  EOT
}
