# 検証結果：ignore_changes 下での EventBridge Connection API Key 上書き

## 結論

**`ignore_changes` は効かない。** `auth_parameters[0].api_key[0].value` を
`lifecycle.ignore_changes` に入れていても、description だけを変更して `apply` すると、
コンソールで手動変更した API Key は **Terraform のコード定義値へ巻き戻る（＝一緒に上書きされる）**。

さらに注意すべきは、**`terraform plan` には API Key の差分が一切出ない**こと。
plan はクリーンに見えるのに、apply 後に実値が巻き戻る。「plan で差分が出ていないから
安全」という判断は、このリソースでは通用しない。

## 検証手順と実測値

API Key の実値は Secrets Manager の `GetSecretValue` で確認した
（`describe-connection` では値はマスクされ返らないため）。

| 時点 | 操作 | API Key 実値 |
|---|---|---|
| ① 初期 apply 直後 | TF 定義値を投入 | `tf-defined-key-AAAA1111`（TF 定義値） |
| ② コンソールで手動変更後 | コンソールから Value を変更 | `qwerasdfzxcv`（コンソール変更値） |
| ③ description のみ変更して apply 後 | `description` を v1→v2 に変更（api_key は未変更） | **`tf-defined-key-AAAA1111`（TF 定義値に巻き戻り）** |

- ③ の `terraform plan` では `description` の変更のみが差分として表示され、
  `auth_parameters` 内の `api_key` は「unchanged block hidden」= 差分ゼロに見えた。
  （plan には空の `invocation_http_parameters` の削除差分だけが別途出た。）
- ③ の apply 後、`describe-connection` の `LastModifiedTime` / `LastAuthorizedTime` が
  apply 時刻に更新されており、UpdateConnection が認証情報ごと再適用したことを裏付けた。

## なぜこうなるか（考察）

- `lifecycle.ignore_changes` は「plan 時に差分検出をスキップし、コード値を無視して
  state 値を維持する」機能。**「その属性を更新 API のリクエスト本文から外す」機能ではない。**
- EventBridge の `UpdateConnection` API は `AuthParameters` を**丸ごと**受け取って
  差し替える設計。description を変える apply のとき、provider は state が保持している
  `auth_parameters`（＝TF 定義値）を UpdateConnection のリクエストに乗せて送る。
- 結果、plan に差分が出ないまま、コンソールで変えた値が TF 定義値へ巻き戻る。
- API Key の実体は AWS が自動生成する Secrets Manager シークレット
  `events!connection/<name>/<id>` に保存される。この巻き戻りは Secret の値更新として起きる。

## 実務上の対策

`ignore_changes` では EventBridge Connection の API Key のコンソール変更は守れない。
守りたい場合は次のいずれか。

- API Key を Connection リソースの外で管理する（Secrets Manager を直接管理し、
  Connection からはその値を参照しない運用にできないか検討）。
- コンソールでの手動変更を運用上禁止し、値の変更は必ず Terraform 経由にする。
- 少なくとも「`ignore_changes` を付けたから大丈夫」という前提は捨てる。
  description などの無関係な属性変更でも API Key が巻き戻るため、
  apply の影響範囲を plan だけで判断しない。

## 補足

- 比較のため `ignore_changes` を外した場合の挙動は `connection.tf` のコメントブロックで
  切り替えられる（対照実験）。本検証の主眼は「ignore を付けても巻き戻る」ことの確認。
- plan に出ていた空の `invocation_http_parameters {}` の削除も、同じ UpdateConnection で
  まとめて適用された。

## 後片付け

検証リソース（Connection と自動生成された Secrets Manager シークレット）は
`terraform destroy` で削除済み。削除後、`describe-connection` と
`describe-secret` の双方で存在しないことを確認した。
