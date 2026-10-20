output "connection_name" {
  description = "作成した EventBridge Connection 名"
  value       = aws_cloudwatch_event_connection.verify.name
}

output "connection_arn" {
  description = "Connection の ARN"
  value       = aws_cloudwatch_event_connection.verify.arn
}

output "secret_arn" {
  description = <<-EOT
    API Key 値が格納される Secrets Manager シークレットの ARN。
    実際の API Key 値はこのシークレットから GetSecretValue で確認する
    （describe-connection では値はマスクされ返らない）。
  EOT
  value       = aws_cloudwatch_event_connection.verify.secret_arn
}

output "verify_commands" {
  description = "検証に使う主要コマンド（region/account は自動埋め込み）"
  value = {
    describe   = "aws events describe-connection --name ${aws_cloudwatch_event_connection.verify.name} --region ${var.region}"
    get_secret = "aws secretsmanager get-secret-value --secret-id ${aws_cloudwatch_event_connection.verify.secret_arn} --region ${var.region} --query SecretString --output text"
  }
}
