# EventBridge Connection：ignore_changes 下での API Key 上書き検証環境

EventBridge Connection の API Key 認証値（`auth_parameters.api_key.value`）を
Terraform の `lifecycle.ignore_changes` で無視した状態にして、

1. コンソールから API Key を手動で変更し、
2. その後 Terraform で **description だけ**を変更して `apply` したときに、

ignore しているはずの **API Key が TF 定義値へ巻き戻る（＝一緒に上書きされる）のか**、
それとも **コンソールで変更した値が維持されるのか**を確認するための Terraform 一式。

## この検証でわかること

- `ignore_changes = [auth_parameters[0].api_key[0].value]` を付けた状態で、
  description だけを変える apply のときに API Key(Secret) が巻き戻るか維持されるか
- EventBridge の `UpdateConnection` が `AuthParameters` を丸ごと差し替える設計であることが、
  `ignore_changes` の「差分を無視するだけ」という性質とどう噛み合うか
- API Key 値の実体がどこにあるか（AWS が自動作成する Secrets Manager シークレット）、
  実値の確認方法（`describe-connection` では値は返らない）

## 検証の背景（なぜ巻き戻りが疑われるか）

- EventBridge Connection の API Key 値は、AWS が自動生成する Secrets Manager の
  シークレット `events!connection/<name>/<id>` に保存される。
  `aws events describe-connection` では値はマスクされ返らない。
  実値の確認は Secrets Manager の `GetSecretValue` で行う。
- `UpdateConnection` API は `AuthParameters` を**丸ごと**受け取って差し替える設計。
  description だけ変えたつもりでも、provider が state 上の `auth_parameters` を
  一緒に送れば、API Key(Secret) が TF 定義値へ戻る可能性がある。
- `ignore_changes` は「plan 時に差分検出をスキップし、コード値を無視して state 値を維持」
  する機能であって、「その属性を UpdateConnection のリクエスト本文から外す」機能ではない。
  この違いが本検証の争点。

## 構成（Terraform で作成するリソース）

| リソース | 名前 | 備考 |
|---|---|---|
| EventBridge Connection | `verify-ignore-connection` | `authorization_type = API_KEY`、`api_key.value` を ignore_changes |
| Secrets Manager シークレット（自動作成） | `events!connection/verify-ignore-connection/<id>` | API Key 値の実体。AWS が自動生成 |

- リージョン: `ap-northeast-1`
- Terraform AWS Provider: `6.44.0`
- 全タグ対応リソースに `verify = true` を付与（provider の `default_tags`）
- API Key の値は変数 `api_key_value_tf`（`sensitive = true`）で管理

## 前提・必要権限

Terraform を apply できる権限を持つユーザーで実行すること。
Connection は裏で Secrets Manager にシークレットを作り、サービスリンクロール
`AWSServiceRoleForAmazonEventBridgeApiDestinations` 経由で管理する。
そのため実行ユーザーには EventBridge の Connection 操作に加えて、
`secretsmanager:*`（`events!connection/*` スコープ）と、
サービスリンクロール作成権限（初回のみ）が必要。
必要最小権限の例は `iam-policy-required.json` に用意してある（参照用）。

> `AmazonEventBridgeFullAccess` マネージドポリシーには必要な Secrets Manager 権限が
> 含まれている。権限不足で `ValidationException: Failed to create the secret...` が出る
> 場合は Secrets Manager 権限を確認する。

## セットアップ

```powershell
# 認証プロファイルを指定（例）
$env:AWS_PROFILE = "<your-profile>"

Copy-Item terraform.tfvars.example terraform.tfvars

terraform init
terraform plan
terraform apply
```

apply 後、outputs に Connection 名・ARN・secret_arn・確認用コマンドが表示される。

---

## 検証手順

### 検証①：初期作成（TF 定義値を投入）

1. `terraform apply` で Connection を作成する。
   - このとき `api_key.value = tf-defined-key-AAAA1111`（TF 定義値）が投入される。

2. 作成直後の API Key 実値を控える（これが「TF 定義値」の基準）。

```powershell
# secret_arn は outputs から取得
$sec = terraform output -raw secret_arn
aws secretsmanager get-secret-value --secret-id $sec --region ap-northeast-1 --query SecretString --output text
```

> `SecretString` は `{"api_key_header":"<header>","api_key_value":"<value>"}` のような
> JSON で返る。`api_key_value` が `tf-defined-key-AAAA1111` であることを確認する。

### 検証②の前段：コンソールから API Key を手動変更

3. マネジメントコンソール → Amazon EventBridge → API destinations → Connections →
   `verify-ignore-connection` → **Edit** で、API Key の **Value** を別の値
   （例: `console-changed-key-BBBB2222`）に変更して保存する。

4. コンソール変更が Secret に反映されたことを確認する。

```powershell
aws secretsmanager get-secret-value --secret-id $sec --region ap-northeast-1 --query SecretString --output text
# api_key_value が console-changed-key-BBBB2222 になっていること
```

### 検証②：description だけを TF で変更して apply（本題）

5. `terraform.tfvars` の `description` を v2 に変更する（`api_key_value_tf` は**触らない**）。

```hcl
# description = "verify connection - description v1 (initial)"
description = "verify connection - description v2 (changed only description)"
```

6. plan を確認する。ここで `auth_parameters` に差分が出ないこと（ignore_changes が
   効いていること）、description のみ変更予定になっていることを見る。

```powershell
terraform plan
```

7. apply する。

```powershell
terraform apply
```

8. **判定**：apply 後に API Key 実値を再取得し、どちらになっているかを確認する。

```powershell
aws secretsmanager get-secret-value --secret-id $sec --region ap-northeast-1 --query SecretString --output text
```

- `console-changed-key-BBBB2222` のまま → **ignore_changes が効き、巻き戻らない**
- `tf-defined-key-AAAA1111` に戻った → **description 変更の UpdateConnection に
  API Key が乗って巻き戻った（＝ignore していても一緒に上書きされる）**

### 補足：plan に出ない変更の確認

`ignore_changes` を付けているため、コンソール変更は plan の差分には現れない。
「plan はクリーンに見えるのに実値は巻き戻る」なら、それがまさに本検証で確認したい
挙動（UpdateConnection が AuthParameters を丸ごと送るための副作用）になる。
`describe-connection` のタイムスタンプも参考にする。

```powershell
aws events describe-connection --name verify-ignore-connection --region ap-northeast-1 `
  --query "{State:ConnectionState,LastModified:LastModifiedTime,LastAuthorized:LastAuthorizedTime,SecretArn:SecretArn}"
```

### 対照実験（任意）：ignore_changes を外して同手順

`connection.tf` の `lifecycle` ブロックを、コメントで用意してある
`ignore_changes = []` 側に切り替えて同じ手順を踏むと、
ignore 無しのときの巻き戻り挙動と対比できる。

## 判定・報告のポイント

- 検証①直後／コンソール変更後／検証②apply 後、の 3 時点の `api_key_value` を並べる
- 検証② apply の `terraform plan` に `auth_parameters` 差分が出たか／出なかったか
- `describe-connection` の `LastModifiedTime` / `LastAuthorizedTime` の変化
- 結論：ignore_changes していても description 変更の apply で API Key が
  巻き戻るか（＝一緒に上書きされるか）／維持されるか

## 参考（AWS 公式ドキュメント・Terraform レジストリ）

- [Terraform: aws_cloudwatch_event_connection（公式レジストリ）](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_connection)
  … `auth_parameters.api_key { key, value }` の定義。value は Secrets Manager に格納される点
- [Terraform: lifecycle meta-argument（ignore_changes）](https://developer.hashicorp.com/terraform/language/meta-arguments/lifecycle#ignore_changes)
  … ignore_changes は差分検出をスキップし state 値を維持する機能、という定義
- [Authorization methods for connections in EventBridge](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-target-connection-auth.html)
  … Connection 作成・更新に Secrets Manager 権限が要る点
- [Using roles to create secrets for API destinations in EventBridge](https://docs.aws.amazon.com/eventbridge/latest/userguide/using-service-linked-roles-service-action-1.html)
  … サービスリンクロールと自動作成されるシークレット `events!connection/*`
- [API destinations as targets in Amazon EventBridge](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-api-destinations.html)
  … Connection / API destination の全体像

## 後片付け

```powershell
terraform destroy
```

> Connection を削除すると、自動作成された Secrets Manager シークレットも
> （AWS 側のライフサイクルで）削除される。残っている場合は Secrets Manager 側で確認する。
