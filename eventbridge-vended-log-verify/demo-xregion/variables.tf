# 受信側（東京）バスに、クロスリージョン受信用のリソースポリシー（events:PutEvents 許可）を
# 付けるかどうか。
#   true  → ポリシーあり（まずこれで転送成功を確認）
#   false → ポリシー無し（同一アカウントなら不要という仮説の検証）
variable "enable_receiver_bus_policy" {
  description = "東京カスタムバスにクロスリージョン受信用リソースポリシーを付けるか"
  type        = bool
  default     = true
}
