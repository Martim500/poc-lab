# ---------------------------------------------------------------------------
# Firehose 配信ロール
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "firehose_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["firehose.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "firehose" {
  name               = "fhverify-role-firehose"
  assume_role_policy = data.aws_iam_policy_document.firehose_assume.json
}

data "aws_iam_policy_document" "firehose_policy" {
  statement {
    sid = "S3Access"
    actions = [
      "s3:AbortMultipartUpload",
      "s3:GetBucketLocation",
      "s3:ListBucket",
      "s3:ListBucketMultipartUploads",
      "s3:PutObject",
    ]
    resources = [
      aws_s3_bucket.logs.arn,
      "${aws_s3_bucket.logs.arn}/*",
    ]
  }

  statement {
    sid = "LogsAccess"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "firehose" {
  name   = "fhverify-role-firehose-policy"
  role   = aws_iam_role.firehose.id
  policy = data.aws_iam_policy_document.firehose_policy.json
}

# ---------------------------------------------------------------------------
# CloudWatch Logs -> Firehose ロール
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "cwlogs_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["logs.${local.region}.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cwlogs_firehose" {
  name               = "fhverify-role-cwlogs-firehose"
  assume_role_policy = data.aws_iam_policy_document.cwlogs_assume.json
}

data "aws_iam_policy_document" "cwlogs_policy" {
  statement {
    sid = "FirehosePut"
    actions = [
      "firehose:PutRecord",
      "firehose:PutRecordBatch",
    ]
    resources = [aws_kinesis_firehose_delivery_stream.s3.arn]
  }
}

resource "aws_iam_role_policy" "cwlogs_firehose" {
  name   = "fhverify-role-cwlogs-firehose-policy"
  role   = aws_iam_role.cwlogs_firehose.id
  policy = data.aws_iam_policy_document.cwlogs_policy.json
}
