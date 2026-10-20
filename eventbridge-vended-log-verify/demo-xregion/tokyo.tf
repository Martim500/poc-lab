# ===========================================================================
# 東京（ap-northeast-1）: 集約先カスタムバス + ログ配信一式
# ===========================================================================

resource "aws_cloudwatch_event_bus" "tokyo" {
  name = local.tokyo_bus_name
  log_config {
    include_detail = "FULL"
    level          = "TRACE"
  }
}

resource "aws_cloudwatch_log_group" "tokyo" {
  name              = local.log_group_name
  retention_in_days = 1
}

resource "aws_cloudwatch_log_delivery_source" "tokyo" {
  name         = "xregion-tokyo-src-INFO"
  log_type     = "INFO_LOGS"
  resource_arn = aws_cloudwatch_event_bus.tokyo.arn
}

resource "aws_cloudwatch_log_delivery_destination" "tokyo" {
  name = "xregion-tokyo-dst-cwl"
  delivery_destination_configuration {
    destination_resource_arn = aws_cloudwatch_log_group.tokyo.arn
  }
}

resource "aws_cloudwatch_log_delivery" "tokyo" {
  delivery_source_name     = aws_cloudwatch_log_delivery_source.tokyo.name
  delivery_destination_arn = aws_cloudwatch_log_delivery_destination.tokyo.arn
}

# ログ配信のためのロググループ側リソースポリシー（SourceArn = ロググループ ARN）
data "aws_iam_policy_document" "tokyo_logs" {
  statement {
    sid    = "AllowVendedLogDelivery"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.tokyo.arn}:log-stream:*"]
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = [aws_cloudwatch_log_group.tokyo.arn]
    }
  }
}

resource "aws_cloudwatch_log_resource_policy" "tokyo_logs" {
  policy_name     = "AWSLogDeliveryWrite-xregion-tokyo"
  policy_document = data.aws_iam_policy_document.tokyo_logs.json
}
