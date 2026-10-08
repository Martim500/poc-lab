data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.region

  # =========================================================================
  # 宛先ロググループ名（検証ごとに切り替える）
  #
  # 【検証①】/aws/vendedlogs/ 配下の慣例プレフィックス名（実施済み・ログ出力 OK）
  #   vended logs の標準的な名前。カスタムバスでログ出力が成立することを確認済み。
  # log_group_name = "/aws/vendedlogs/events/event-bus/${var.bus_name}"
  #
  # 【検証②】/aws/vendedlogs/ 配下でない名前でも配信が通るか ★実施中
  #   実運用の設計では /aws/vendedlogs/ 配下でないロググループ名を使うことがあるため、
  #   このプレフィックスが配信の必須要件かを確認する。
  log_group_name = "/verify-non-vendedlogs-prefix-01"
  # =========================================================================
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

# ===========================================================================
# 配信パイプライン（delivery-source → destination → delivery）
#
# 【検証（配信あり）】下記 3 リソースを有効化（既定）。ログ出力の標準構成。
# 【検証（配信なし）】「そもそも配信パイプライン無しで出るか」を見るときは、
#   下記 3 リソースと resource_policy.tf のポリシーをまとめてコメントアウトする。
#   → ロググループは作られるが配信リンクが無い状態になる。
# ===========================================================================

# delivery-source（EventBridge イベントバスをログソースとして登録）
# 最小構成として INFO_LOGS のみを対象にする。
# 要確認: log_type="INFO_LOGS" は Terraform 公式例に準拠。
resource "aws_cloudwatch_log_delivery_source" "info" {
  name         = "${var.bus_name}-src-INFO"
  log_type     = "INFO_LOGS"
  resource_arn = aws_cloudwatch_event_bus.this.arn
}

# delivery-destination（CloudWatch Logs ロググループを宛先に）
resource "aws_cloudwatch_log_delivery_destination" "cwl" {
  name = "${var.bus_name}-dst-cwl"

  delivery_destination_configuration {
    destination_resource_arn = aws_cloudwatch_log_group.this.arn
  }
}

# delivery（source と destination を紐付け）
resource "aws_cloudwatch_log_delivery" "info_to_cwl" {
  delivery_source_name     = aws_cloudwatch_log_delivery_source.info.name
  delivery_destination_arn = aws_cloudwatch_log_delivery_destination.cwl.arn
}
