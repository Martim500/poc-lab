output "bucket_name" {
  value = aws_s3_bucket.logs.bucket
}

output "bucket_arn" {
  value = aws_s3_bucket.logs.arn
}

output "firehose_name" {
  value = aws_kinesis_firehose_delivery_stream.s3.name
}

output "firehose_arn" {
  value = aws_kinesis_firehose_delivery_stream.s3.arn
}

output "firehose_role_arn" {
  value = aws_iam_role.firehose.arn
}

output "source_log_group" {
  value = aws_cloudwatch_log_group.source.name
}

output "error_log_group" {
  value = aws_cloudwatch_log_group.firehose_error.name
}

output "error_log_stream" {
  value = aws_cloudwatch_log_stream.firehose_error.name
}
