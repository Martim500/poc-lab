# ===========================================================================
# 宛先ロググループのリソースベースポリシー
#
# 公式 Terraform 例では、イベントバスではなく「宛先ロググループ」側に
# delivery.logs.amazonaws.com を許可するリソースポリシーを付与する。
# （イベントバス側のリソースポリシーは不要と確定済み）
#
# 検証ごとにこのファイル内のコメントブロックを切り替える。
# 「ポリシー自体を作らない」検証をするときは、このファイル全体をコメントアウトする。
# ===========================================================================

locals {
  # =========================================================================
  # aws:SourceArn に入れる値（検証ごとに切り替える）
  #
  # 【検証④-b-1】delivery-source の ARN（実施済み・ログ出力 OK・公式方式）
  #   実機で aws:SourceArn = delivery-source ARN と確定。これが正しい形式。
  source_arn_value = aws_cloudwatch_log_delivery_source.info.arn
  #
  # 【検証④-b-2】宛先ロググループの ARN（現行設計案が流用していた誤りの可能性）
  #   検証④-b-2 を回すときは上をコメントアウトし、下を有効化する。
  # source_arn_value = aws_cloudwatch_log_group.this.arn
  # =========================================================================
}

data "aws_iam_policy_document" "cwlogs" {
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

    # =======================================================================
    # Condition（検証ごとに切り替える）
    #
    # 【検証④-b】Condition あり（実施済み・ログ出力 OK）
    #   SourceAccount + SourceArn で絞り込む。セキュリティ上の推奨構成。
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = [local.source_arn_value]
    }
    #
    # 【検証④-a】Condition 無し（必要なら上の 2 つの condition ブロックを
    #   まるごとコメントアウトして apply する。「Condition が必須か」を確認）
    # =======================================================================
  }
}

resource "aws_cloudwatch_log_resource_policy" "cwlogs" {
  policy_name     = "AWSLogDeliveryWrite-${var.bus_name}"
  policy_document = data.aws_iam_policy_document.cwlogs.json
}
