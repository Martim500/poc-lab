resource "aws_cloudwatch_log_subscription_filter" "source" {
  name            = "fhverify-sub-source-01"
  log_group_name  = aws_cloudwatch_log_group.source.name
  filter_pattern  = ""
  destination_arn = aws_kinesis_firehose_delivery_stream.s3.arn
  role_arn        = aws_iam_role.cwlogs_firehose.arn
}
