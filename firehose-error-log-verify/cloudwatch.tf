resource "aws_cloudwatch_log_group" "source" {
  name              = "/fhverify/source-01"
  retention_in_days = 1
}

resource "aws_cloudwatch_log_stream" "source" {
  name           = "test-01"
  log_group_name = aws_cloudwatch_log_group.source.name
}

resource "aws_cloudwatch_log_group" "firehose_error" {
  name              = "/fhverify-log-firehose-error-01"
  retention_in_days = 1
}

resource "aws_cloudwatch_log_stream" "firehose_error" {
  name           = "fhverify-stream-s3-01"
  log_group_name = aws_cloudwatch_log_group.firehose_error.name
}
