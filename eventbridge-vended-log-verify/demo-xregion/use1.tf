# ===========================================================================
# 送信側（us-east-1）: デフォルトバスのルール → ターゲット=東京カスタムバス
#   + クロスリージョン転送用 IAM ロール（xregion ロール）
# ===========================================================================

# クロスリージョン転送用 IAM ロール（events.amazonaws.com を信頼）
data "aws_iam_policy_document" "xregion_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "xregion" {
  name               = "xregion-forward-role"
  assume_role_policy = data.aws_iam_policy_document.xregion_assume.json
}

# 東京バスへ PutEvents する権限
data "aws_iam_policy_document" "xregion_put" {
  statement {
    effect    = "Allow"
    actions   = ["events:PutEvents"]
    resources = [local.tokyo_bus_arn]
  }
}

resource "aws_iam_role_policy" "xregion" {
  name   = "xregion-forward-putevents"
  role   = aws_iam_role.xregion.id
  policy = data.aws_iam_policy_document.xregion_put.json
}

# us-east-1 のデフォルトバスにルール（verify.test を拾う）
resource "aws_cloudwatch_event_rule" "use1_fwd" {
  provider       = aws.use1
  name           = "xregion-health-global-fwd"
  description    = "Forward verify.test events from us-east-1 default bus to Tokyo custom bus"
  event_bus_name = "default"
  event_pattern = jsonencode({
    source = ["verify.test"]
  })
}

# ターゲット = 東京のカスタムバス（クロスリージョン）。role_arn に xregion ロール。
resource "aws_cloudwatch_event_target" "use1_to_tokyo" {
  provider       = aws.use1
  rule           = aws_cloudwatch_event_rule.use1_fwd.name
  event_bus_name = "default"
  target_id      = "tokyo-custom-bus"
  arn            = local.tokyo_bus_arn
  role_arn       = aws_iam_role.xregion.arn
}
