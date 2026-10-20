# ===========================================================================
# 受信側（東京カスタムバス）のリソースポリシー（クロスリージョン受信用）
#
# enable_receiver_bus_policy = true  → 付ける（まず転送成功を確認）
#                            = false → 付けない（同一アカウントなら不要の仮説検証）
#
# ※これは (b) イベント受信用（events:PutEvents）。(a) ログ配信用とは別物。
# ===========================================================================

data "aws_iam_policy_document" "receiver" {
  count = var.enable_receiver_bus_policy ? 1 : 0

  statement {
    sid    = "AllowCrossRegionPutEventsSameAccount"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = [local.account_id]
    }
    actions   = ["events:PutEvents"]
    resources = [aws_cloudwatch_event_bus.tokyo.arn]
  }
}

resource "aws_cloudwatch_event_bus_policy" "receiver" {
  count          = var.enable_receiver_bus_policy ? 1 : 0
  event_bus_name = aws_cloudwatch_event_bus.tokyo.name
  policy         = data.aws_iam_policy_document.receiver[0].json
}
