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
# 段階的な切り分けは「変数トグル」ではなく、各 .tf ファイル内の
# 「検証①/②/…」コメントブロックを切り替える方式で行う。
# どのブロックを有効化するかは main.tf / resource_policy.tf のコメントを参照。
# 過去の検証コードは痕跡として各ファイルにコメントで残してある。
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
