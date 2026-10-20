# ===========================================================================
# EventBridge Connection: ignore_changes 下での API Key 上書き検証
# ===========================================================================
#
# 【検証の目的】
#   auth_parameters.api_key.value を lifecycle.ignore_changes で無視した状態で、
#   (1) コンソールから API Key の値を変更し、
#   (2) その後 Terraform で description だけを変更して apply したときに、
#       ignore している API Key の値が TF 定義値に巻き戻る（＝一緒に上書きされる）のか、
#       それともコンソールで変更した値が維持されるのかを確認する。
#
# 【前提となる仕組み（なぜ巻き戻りが疑われるか）】
#   - EventBridge Connection の API Key 値は AWS が自動生成する Secrets Manager の
#     シークレット（events!connection/<name>/<id>）に保存される。
#   - describe-connection では value は返らない（マスクされる）。実値の確認は
#     Secrets Manager の GetSecretValue で行う。
#   - EventBridge の UpdateConnection API は AuthParameters を「丸ごと」受け取り差し替える
#     設計のため、description だけを変えたつもりでも、provider が state 上の
#     auth_parameters を一緒に送れば API Key(Secret) が TF 値へ戻る可能性がある。
#   - ignore_changes は「差分検出時にコード値を無視し state 値を維持」する機能であって、
#     「その属性を UpdateConnection のリクエストから外す」機能ではない点に注意。
#     ここが本検証の争点。
#
# 【進め方】
#   検証① … 初期作成（下のブロックが有効）。TF 定義値 api_key_value_tf を投入する。
#   → コンソールで API Key を別値（例: console-changed-key-BBBB2222）に手動変更。
#   検証② … description だけを変えて apply（変数 description を v2 に変更して apply）。
#            api_key の value 行は検証①のまま触らない（ignore_changes が効いている前提）。
#   → apply 後、Secrets Manager の実値がコンソール値のままか TF 値に戻ったかを確認。
# ===========================================================================

resource "aws_cloudwatch_event_connection" "verify" {
  name               = var.connection_name
  description        = var.description
  authorization_type = "API_KEY"

  auth_parameters {
    api_key {
      key = var.api_key_header

      # --- 検証①/②共通：TF が定義する API Key の値 ---------------------------
      # この value は「初期作成時だけ」効かせたい。コンソールでの手動変更を
      # 維持したいので ignore_changes で無視する。検証②でもこの行は変更しない。
      value = var.api_key_value_tf
    }
  }

  # -------------------------------------------------------------------------
  # 本検証の中核設定：api_key の value を変更無視にする。
  # これが効くなら、コンソールで変えた API Key は apply しても維持されるはず。
  # 効かない（UpdateConnection に乗って送られる）なら、description 変更の
  # apply で API Key が TF 定義値へ巻き戻る。
  # -------------------------------------------------------------------------
  lifecycle {
    ignore_changes = [
      auth_parameters[0].api_key[0].value,
    ]
  }

  # 過去検証の痕跡（必要になったら切り替える）:
  # 比較用に ignore_changes を外した状態で同じ手順を踏むと、
  # 「ignore 無し」での巻き戻り挙動と対比できる。
  # lifecycle {
  #   ignore_changes = []
  # }
}
