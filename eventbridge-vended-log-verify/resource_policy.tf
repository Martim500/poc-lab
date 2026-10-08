# ---------------------------------------------------------------------------
# 宛先ロググループのリソースベースポリシー
#
# 公式 Terraform 例では、イベントバスではなく「宛先ロググループ」側に
# delivery.logs.amazonaws.com を許可するリソースポリシーを付与する。
# このファイルはそのポリシーを段階的に制御する。
#
# - enable_log_group_resource_policy = false → ポリシー自体を作らない（Step3 の素の状態）
# - enable_resource_policy_condition = false → Condition 無しのポリシー（Step4-a）
# - source_arn_pattern                      → aws:SourceArn に入れる値のパターン（Step4-b）
# ---------------------------------------------------------------------------

locals {
  # aws:SourceArn に入れる候補値
  # delivery_source: delivery-source の ARN（公式方式。正しいと想定）
  # log_group:       宛先ロググループの ARN（現行設計案が流用していた誤りの可能性を検証）
  source_arn_value = (
    var.source_arn_pattern == "delivery_source"
    ? (var.enable_log_delivery ? aws_cloudwatch_log_delivery_source.info[0].arn : "arn:aws:logs:${local.region}:${local.account_id}:delivery-source:*")
    : aws_cloudwatch_log_group.this.arn
  )
}

data "aws_iam_policy_document" "cwlogs" {
  count = var.enable_log_group_resource_policy ? 1 : 0

  statement {
    sid    = "AllowVendedLogDelivery"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }

    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]

    resources = [
      "${aws_cloudwatch_log_group.this.arn}:log-stream:*",
    ]

    # Condition を付ける場合のみ以下を追加
    dynamic "condition" {
      for_each = var.enable_resource_policy_condition ? [1] : []
      content {
        test     = "StringEquals"
        variable = "aws:SourceAccount"
        values   = [local.account_id]
      }
    }

    dynamic "condition" {
      for_each = var.enable_resource_policy_condition ? [1] : []
      content {
        test     = "ArnLike"
        variable = "aws:SourceArn"
        values   = [local.source_arn_value]
      }
    }
  }
}

resource "aws_cloudwatch_log_resource_policy" "cwlogs" {
  count = var.enable_log_group_resource_policy ? 1 : 0

  policy_name     = "AWSLogDeliveryWrite-${var.bus_name}"
  policy_document = data.aws_iam_policy_document.cwlogs[0].json
}
