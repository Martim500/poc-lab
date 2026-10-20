# ===========================================================================
# 検証: デフォルトイベントバス + aws:SourceArn = ロググループ ARN で配信できるか
#
# デフォルトバス本体は Terraform で作れない（name="default" は弾かれる）ため、
# バス本体は作らず、以下を Terraform で作る:
#   - 宛先ロググループ
#   - delivery-source（resource_arn = デフォルトバスの ARN）
#   - delivery-destination（ロググループ）
#   - delivery（source↔destination）
#   - ロググループのリソースポリシー（aws:SourceArn = ロググループ ARN）
#
# デフォルトバスの log_config(TRACE/FULL) は Terraform では設定できないので、
# apply 前後に CLI で設定する:
#   aws events update-event-bus --name default --log-config IncludeDetail=FULL,Level=TRACE
# ===========================================================================

# デフォルトバスの ARN（固定形式）
locals {
  default_bus_arn = "arn:aws:events:${local.region}:${local.account_id}:event-bus/default"
  log_group_name  = "/aws/vendedlogs/events/event-bus/default"
}

resource "aws_cloudwatch_log_group" "default" {
  name              = local.log_group_name
  retention_in_days = 1
}

resource "aws_cloudwatch_log_delivery_source" "default" {
  name         = "demo-default-src-INFO"
  log_type     = "INFO_LOGS"
  resource_arn = local.default_bus_arn
}

resource "aws_cloudwatch_log_delivery_destination" "default" {
  name = "demo-default-dst-cwl"
  delivery_destination_configuration {
    destination_resource_arn = aws_cloudwatch_log_group.default.arn
  }
}

resource "aws_cloudwatch_log_delivery" "default" {
  delivery_source_name     = aws_cloudwatch_log_delivery_source.default.name
  delivery_destination_arn = aws_cloudwatch_log_delivery_destination.default.arn
}

# ロググループのリソースポリシー（★ aws:SourceArn = ロググループ ARN）
data "aws_iam_policy_document" "default" {
  statement {
    sid    = "AllowVendedLogDelivery"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.default.arn}:log-stream:*"]
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      # ★ロググループ ARN を指定
      values = [aws_cloudwatch_log_group.default.arn]
    }
  }
}

resource "aws_cloudwatch_log_resource_policy" "default" {
  policy_name     = "AWSLogDeliveryWrite-demo-default"
  policy_document = data.aws_iam_policy_document.default.json
}
