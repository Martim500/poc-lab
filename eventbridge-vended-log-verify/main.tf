data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.region

  # 宛先ロググループ名（vended logs の慣例プレフィックス）
  log_group_name = "/aws/vendedlogs/events/event-bus/${var.bus_name}"
}

# ---------------------------------------------------------------------------
# カスタムイベントバス（log_config でログレベルを設定）
# log_config.level = OFF の場合、EventBridge はログを生成しない。
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_event_bus" "this" {
  name = var.bus_name

  log_config {
    include_detail = var.include_detail
    level          = var.log_level
  }
}

# ---------------------------------------------------------------------------
# 宛先ロググループ
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "this" {
  name              = local.log_group_name
  retention_in_days = 1 # 検証用に短期保持
}

# ---------------------------------------------------------------------------
# delivery-source（EventBridge イベントバスをログソースとして登録）
# 最小構成として INFO_LOGS のみを対象にする。
# log_level=TRACE の場合、INFO 相当のイベントも TRACE に含まれるため INFO_LOGS で観測可能。
# （log_type ごとに source を分ける必要があるのは複数レベルを個別配信する場合）
# 要確認: log_type="INFO_LOGS" は Terraform 公式例に準拠。実機で有効値を確認すること。
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_log_delivery_source" "info" {
  count = var.enable_log_delivery ? 1 : 0

  name         = "${var.bus_name}-src-INFO"
  log_type     = "INFO_LOGS"
  resource_arn = aws_cloudwatch_event_bus.this.arn
}

# ---------------------------------------------------------------------------
# delivery-destination（CloudWatch Logs ロググループを宛先に）
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_log_delivery_destination" "cwl" {
  count = var.enable_log_delivery ? 1 : 0

  name = "${var.bus_name}-dst-cwl"

  delivery_destination_configuration {
    destination_resource_arn = aws_cloudwatch_log_group.this.arn
  }
}

# ---------------------------------------------------------------------------
# delivery（source と destination を紐付け）
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_log_delivery" "info_to_cwl" {
  count = var.enable_log_delivery ? 1 : 0

  delivery_source_name     = aws_cloudwatch_log_delivery_source.info[0].name
  delivery_destination_arn = aws_cloudwatch_log_delivery_destination.cwl[0].arn
}
