variable "region" {
  description = "検証リージョン"
  type        = string
  default     = "ap-northeast-1"
}

variable "connection_name" {
  description = "EventBridge Connection 名"
  type        = string
  default     = "verify-ignore-connection"
}

# ---------------------------------------------------------------------------
# 検証の切り分けは「変数トグル」ではなく、connection.tf 内の
# 「検証①/②/…」コメントブロックを切り替える方式で行う。
# 過去の検証コードは痕跡として各ファイルにコメントで残す。
#
# この検証で動かす値は connection.tf の locals / コメントブロックで管理する。
# ---------------------------------------------------------------------------

variable "description" {
  description = "Connection の description。検証②で TF 側だけ変更するために変数化してある"
  type        = string
  default     = "verify connection - description v1 (initial)"
}

variable "api_key_header" {
  description = "API Key のヘッダー名（auth_parameters.api_key.key）"
  type        = string
  default     = "x-verify-api-key"
}

variable "api_key_value_tf" {
  description = <<-EOT
    TF コードが定義する API Key の値（auth_parameters.api_key.value）。
    検証ではこの値を初期投入し、その後コンソールで別の値に変更する。
    ignore_changes によって、この TF 定義値が apply 時に適用されない（コンソール値が維持される）
    のか、それとも Description 変更時の UpdateConnection で巻き戻るのかを確認する。
  EOT
  type        = string
  default     = "tf-defined-key-AAAA1111"
  sensitive   = true
}
