resource "aws_kinesis_firehose_delivery_stream" "s3" {
  name        = "fhverify-stream-s3-01"
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn   = aws_iam_role.firehose.arn
    bucket_arn = aws_s3_bucket.logs.arn

    prefix              = "applogs/sample-stream-01/!{timestamp:yyyy/MM/dd/HH}/"
    error_output_prefix = "errors/applogs/sample-stream-01/!{timestamp:yyyy/MM/dd}/!{firehose:error-output-type}/"
    buffering_size      = 5
    buffering_interval  = 300
    compression_format  = "GZIP"
    file_extension      = ".json.gz"
    custom_time_zone    = "Asia/Tokyo"

    processing_configuration {
      enabled = true

      processors {
        type = "Decompression"
        parameters {
          parameter_name  = "CompressionFormat"
          parameter_value = "GZIP"
        }
      }

      processors {
        type = "CloudWatchLogProcessing"
        parameters {
          parameter_name  = "DataMessageExtraction"
          parameter_value = "true"
        }
      }

      processors {
        type = "AppendDelimiterToRecord"
      }
    }

    cloudwatch_logging_options {
      enabled         = true
      log_group_name  = aws_cloudwatch_log_group.firehose_error.name
      log_stream_name = aws_cloudwatch_log_stream.firehose_error.name
    }
  }
}
