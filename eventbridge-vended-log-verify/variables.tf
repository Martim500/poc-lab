variable "region" {
  description = "検証リージョン"
  type        = string
  default     = "ap-northeast-1"
}

variable "bus_name" {
  description = "カスタムイベントバス名"
  type        = string
  default     = "verify-vendedlog-bus"
}

# ---------------------------------------------------------------------------
# 段階的切り分け用のフィーチャーフラグ
# 各ステップで値を変えて terraform apply を繰り返し、ログ出力有無を観察する。
# 詳細な手順と期待結果は README.md「5. apply 後の検証手順」を参照。
# ---------------------------------------------------------------------------

variable "log_level" {
  description = "イベントバスの log_config.level。OFF/ERROR/INFO/TRACE"
  type        = string
  default     = "TRACE"

  validation {
    condition     = contains(["OFF", "ERROR", "INFO", "TRACE"], var.log_level)
    error_message = "log_level は OFF/ERROR/INFO/TRACE のいずれか。"
  }
}

variable "include_detail" {
  description = "イベントバスの log_config.include_detail。NONE/FULL"
  type        = string
  default     = "FULL"

  validation {
    condition     = contains(["NONE", "FULL"], var.include_detail)
    error_message = "include_detail は NONE/FULL のいずれか。"
  }
}

# delivery-source / delivery-destination / delivery を作成するか。
# false の場合、イベントバスの log_config だけを設定した状態（＝配信先未設定）になる。
# Step1 の「配信パイプライン無し」観察に使用。
variable "enable_log_delivery" {
  description = "CloudWatch Logs への delivery パイプライン(source/destination/delivery)を作成するか"
  type        = bool
  default     = true
}

# ロググループのリソースポリシー(aws_cloudwatch_log_resource_policy)を作成するか。
# false にすると配信先ロググループに書き込み許可が無い状態になる。
# Step3 の「リソースポリシー無しで出力されるか」観察に使用。
variable "enable_log_group_resource_policy" {
  description = "宛先ロググループのリソースベースポリシーを作成するか"
  type        = bool
  default     = true
}

# リソースポリシーに Condition(aws:SourceAccount / aws:SourceArn)を付けるか。
# false にすると Condition 無しのポリシーになる。
# Step4-a の「Condition 無しで出力されるか」観察に使用。
variable "enable_resource_policy_condition" {
  description = "ロググループのリソースポリシーに Condition を付与するか"
  type        = bool
  default     = true
}

# aws:SourceArn 条件に入れる値のパターンを選ぶ。
# "delivery_source" = delivery-source の ARN（公式例の方式。これが正しいと想定）
# "log_group"       = 宛先ロググループの ARN（現行設計案が流用していた形式。誤りの可能性を検証）
# Step4-b の「aws:SourceArn の正しい ARN 形式」切り分けに使用。
variable "source_arn_pattern" {
  description = "aws:SourceArn に入れる ARN パターン: delivery_source | log_group"
  type        = string
  default     = "delivery_source"

  validation {
    condition     = contains(["delivery_source", "log_group"], var.source_arn_pattern)
    error_message = "source_arn_pattern は delivery_source | log_group のいずれか。"
  }
}
