# EventBridge イベントバス Vended Log Delivery 権限検証（Terraform）

## 1. 検証の目的

Amazon EventBridge のカスタムイベントバスから CloudWatch Logs へログ（Vended log delivery）を
出力するために、どの IAM 権限設定が実際に必要かを、設定を段階的に足しながら切り分けて確定する。

明らかにしたいこと（優先順）:

1. そもそもポリシー設定なしでイベントバスのログが出力されるか
2. 情報源A のアイデンティティベースポリシー（`events:AllowVendedLogDeliveryForResource`）のみで出力されるか
3. リソースベースポリシーが必要な場合、Condition 無しで出力されるか
4. Condition が必要な場合、`aws:SourceArn` に入る実際の ARN 形式は何か
5. デフォルトイベントバスに対しても同じ方法でポリシーを付与できるか（カスタムバスと挙動が異なる可能性）

> 補足（事前調査で判明した事実 / 要実機確認）
> AWS 公式の Terraform プロバイダ（hashicorp/aws）の `aws_cloudwatch_event_bus` ドキュメントが示す
> CloudWatch Logs 宛先の構成例では、
> - **イベントバス自身へのリソースベースポリシーは存在しない**
> - 代わりに **宛先ロググループ側に** `aws_cloudwatch_log_resource_policy`（プリンシパル
>   `delivery.logs.amazonaws.com`）を付与する
> - その Condition の `aws:SourceArn` には **delivery-source の ARN**
>   (`aws_cloudwatch_log_delivery_source.*.arn`) が入る。ロググループの ARN ではない。
>
> つまり現行設計案（イベントバスにリソースベースポリシーを付け、`aws:SourceArn` に
> ロググループ ARN を流用）は公式方式と食い違っている可能性が高い。本検証はこれを実機で確定する。
> 出典: Terraform Registry `aws_cloudwatch_event_bus`（Logging to CloudWatch Logs の例）

## 2. 前提条件

- 検証用 AWS アカウントで実施する。検証対象外の既存環境は作らない。
- リージョン: `ap-northeast-1`
- Terraform 実行者（CLI 実行アイデンティティ）に必要な権限:
  - `events:CreateEventBus`, `events:DeleteEventBus`, `events:DescribeEventBus`, `events:PutEvents`
  - `events:AllowVendedLogDeliveryForResource`（情報源A の論点。Step2 で付与検証）
  - `logs:CreateLogGroup`, `logs:DeleteLogGroup`, `logs:PutRetentionPolicy`
  - `logs:PutDeliverySource`, `logs:DeleteDeliverySource`, `logs:GetDeliverySource`
  - `logs:PutDeliveryDestination`, `logs:DeleteDeliveryDestination`
  - `logs:CreateDelivery`, `logs:DeleteDelivery`
  - `logs:PutResourcePolicy`, `logs:DeleteResourcePolicy`, `logs:DescribeResourcePolicies`
  - `logs:DescribeLogStreams`, `logs:GetLogEvents`, `logs:FilterLogEvents`
  - `cloudtrail:LookupEvents`（権限エラー調査用）
- 作成するリソース（最小構成）:
  - カスタムイベントバス 1 本
  - CloudWatch Logs ロググループ 1 本
  - delivery-source / delivery-destination / delivery（CloudWatch Logs 向け）
  - ロググループのリソースポリシー（段階的に付与・変更）
  - ルール・ターゲット・外部連携は作らない

### リソース名の例（プレースホルダ）

| 項目 | 値（例） |
|------|----------|
| イベントバス名 | `verify-vendedlog-bus` |
| ロググループ名 | `/aws/vendedlogs/events/event-bus/verify-vendedlog-bus` |
| delivery-source 名 | `verify-vendedlog-src-INFO` |
| delivery-destination 名 | `verify-vendedlog-dst-cwl` |
| アカウントID | `{ACCOUNT_ID}` |
| リージョン | `ap-northeast-1` |

> ロググループ名の `/aws/vendedlogs/` プレフィックスは vended logs の慣例。
> このプレフィックスがログ配信の必須要件かどうかは本検証の確認対象外だが、公式例に倣っている。
## 3. 構成（Terraform で作成するリソース）

| リソース | 名前（例） | 備考 |
|---|---|---|
| カスタムイベントバス | `verify-vendedlog-bus` | `log_config` でログレベル設定（既定 TRACE / FULL） |
| CloudWatch Logs ロググループ | `/aws/vendedlogs/events/event-bus/verify-vendedlog-bus` | 保持 1 日 |
| delivery-source | `verify-vendedlog-bus-src-INFO` | `log_type = INFO_LOGS`、resource_arn はイベントバス |
| delivery-destination | `verify-vendedlog-bus-dst-cwl` | 宛先はロググループ |
| delivery | （ID 自動） | source と destination を紐付け |
| ロググループのリソースポリシー | `AWSLogDeliveryWrite-verify-vendedlog-bus` | `delivery.logs.amazonaws.com` を許可 |

- リージョン: `ap-northeast-1`
- Terraform AWS Provider: `>= 6.44.0`
- アカウントIDは `data.aws_caller_identity` で自動取得（直書きなし）
- 全タグ対応リソースに `verify = true` を付与（provider の `default_tags`）
- ルール・ターゲット・外部連携は作らない

### 段階的切り分け用のフラグ（variables.tf）

このディレクトリは 1 つの構成で、変数を切り替えて `terraform apply` を繰り返すことで
Step1〜5 を段階的に検証できる。各フラグの意味は下表のとおり。

| 変数 | 既定 | 役割 |
|---|---|---|
| `log_level` | `TRACE` | イベントバスの `log_config.level`（OFF/ERROR/INFO/TRACE） |
| `include_detail` | `FULL` | `log_config.include_detail`（NONE/FULL） |
| `enable_log_delivery` | `true` | delivery-source/destination/delivery を作るか |
| `enable_log_group_resource_policy` | `true` | 宛先ロググループのリソースポリシーを作るか |
| `enable_resource_policy_condition` | `true` | リソースポリシーに Condition を付けるか |
| `source_arn_pattern` | `delivery_source` | `aws:SourceArn` に入れる値（`delivery_source` / `log_group`） |

> 既定値のまま apply すると「配信あり・リソースポリシーあり・Condition あり・
> SourceArn=delivery-source ARN」の状態（＝後述 Step 4-b-1 相当。正常にログが出る想定）になる。

## 4. セットアップ（apply）

```bash
# 認証プロファイルを指定（例）
export AWS_PROFILE=<your-profile>   # PowerShell: $env:AWS_PROFILE = "<your-profile>"

terraform init
terraform plan
terraform apply
```

apply 後、出力（outputs）にイベントバス名・ロググループ名・delivery-source ARN・
現在ポリシーに入っている `aws:SourceArn` の値・PutEvents コマンド例が表示される。

```bash
terraform output
```

---

## 5. apply 後の検証手順（既定値 = Step 4-b-1 の状態）

既定値のまま apply した直後は「正常にログが出るはずの構成」になっている。
まずこの状態でログ出力を確認し、その後 Step を切り替えて切り分ける。

### 5-0. 共通：イベントを流す／ログを確認する

プレースホルダ `{BUS_NAME}` `{LOG_GROUP_NAME}` は `terraform output` の値に読み替える。

**イベントを流す（PutEvents）**

ログは PutEvents でバスにイベントが入ると生成される。ルール・ターゲットが無くても
PutEvents で送られたイベントはログ対象になる（本検証がルール/ターゲットを作らない理由）。
`TRACE` では `Rule Matching Started` / `No Rules Matched` 等のステップが記録される想定。

```bash
# Linux / macOS / CloudShell
aws events put-events --region ap-northeast-1 \
  --entries 'file://event.json'
```

`event.json`:

```json
[{"Source":"verify.test","DetailType":"VerifyEvent","Detail":"{\"msg\":\"hello\"}","EventBusName":"{BUS_NAME}"}]
```

> Windows cmd で直接書く場合はダブルクォートのエスケープが必要。`file://` 方式が確実。
> `terraform output put_events_cli_hint` にワンライナー例あり。

**ログを確認する**

```bash
# ログストリームの有無（配信が始まるとストリームが自動生成される）
aws logs describe-log-streams --region ap-northeast-1 \
  --log-group-name "{LOG_GROUP_NAME}" --order-by LastEventTime --descending

# 直近のログイベント本体
aws logs filter-log-events --region ap-northeast-1 \
  --log-group-name "{LOG_GROUP_NAME}" --limit 20
```

- 待ち時間の目安：Vended log はベストエフォート配信。**初回は数分（最大 5〜10 分程度）**
  かかることがある。ストリームが出来るまで `describe-log-streams` は空。
- 判定：`filter-log-events` の `events` に `verify.test` を含むレコードや
  `RULE_MATCH_STARTED` / `NO_RULES_MATCHED` 等が出れば「出力あり」。

### 5-1. Step 1：ポリシー・配信パイプライン無しで出力されるか

`terraform.tfvars`:

```hcl
log_level                        = "TRACE"
include_detail                   = "FULL"
enable_log_delivery              = false
enable_log_group_resource_policy = false
enable_resource_policy_condition = false
```

```bash
terraform apply
# PutEvents → 数分待つ → ログ確認
```

- 状態：`log_config` は TRACE だが delivery も ロググループのポリシーも無い。
  ロググループは作成されるが配信リンクが無い。
- 期待結果：ログストリームは作成されない。
- 解釈：
  - 出力されない → **配信パイプライン無しではログは出ない**ことが確定（log_config だけでは不十分）。→ Step 3 へ。
  - 出力された → 想定外。delivery 無しで出る経路の可能性。記録して要確認。

### 5-2. Step 2：情報源A のアイデンティティベースポリシーのみで出力されるか

情報源A は「ログ**設定操作を行う IAM プリンシパル**に
`events:AllowVendedLogDeliveryForResource` を付与せよ」という内容。これは
**実行時のログ出力許可ではなく、設定 API を呼ぶための権限**である可能性が高い。

Terraform 実行者（＝設定操作者）に、情報源A のポリシー（リージョンを ap-northeast-1 に変更）を付与する:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ServiceLevelAccessForLogDelivery",
      "Effect": "Allow",
      "Action": ["events:AllowVendedLogDeliveryForResource"],
      "Resource": "arn:aws:events:ap-northeast-1:{ACCOUNT_ID}:event-bus/{BUS_NAME}*"
    }
  ]
}
```

```hcl
# 配信パイプラインは作るが、ロググループのリソースポリシーは作らない
enable_log_delivery              = true
enable_log_group_resource_policy = false
enable_resource_policy_condition = false
```

```bash
terraform apply
```

- 期待結果 / 解釈：
  - `apply` が成功し delivery 系が作成できる → 情報源A は「設定時に必要な権限」。
    ただし実行時のログ出力まで通るかは Step 3 の観測で判断する。
  - 注意：情報源A のポリシーはイベントバスのリソースベースポリシーではなく
    **操作者のアイデンティティに付くもの**。現行設計案（バスにリソースベースで付与）とは別物。
    この違い自体が重要な確定事項。
- 要確認：`events:AllowVendedLogDeliveryForResource` が delivery 作成時に実際に要求されるかは、
  この権限を外した状態で `apply` し失敗するか（§6 の調査手順）で確定する。

### 5-3. Step 3：配信あり・ロググループのリソースポリシー無しで出力されるか

```hcl
enable_log_delivery              = true
enable_log_group_resource_policy = false
enable_resource_policy_condition = false
```

```bash
terraform apply
# PutEvents → 数分待つ → ログ確認
```

- 期待結果：配信リンクはあるが書き込み許可が無いためストリームは作成されない見込み。
- 解釈：
  - 出力されない → **宛先ロググループのリソースベースポリシーが必要**と確定。→ Step 4 へ。
  - 出力される → リソースポリシー不要。設計を簡素化できる（Step 4 はスキップ可）。

### 5-4. Step 4-a：リソースポリシーあり・Condition 無しで出力されるか

```hcl
enable_log_delivery              = true
enable_log_group_resource_policy = true
enable_resource_policy_condition = false
```

```bash
terraform apply
# PutEvents → 数分待つ → ログ確認
```

- 期待結果：Condition 無しの許可で書き込みを許可。ストリームが作成されログ出力される見込み。
- 解釈：
  - 出力される → **リソースポリシーは必要だが Condition は必須でない**と確定。
    セキュリティ上は Condition を付けるのが望ましいので Step 4-b で正しい値を確定する。
  - 出力されない → Condition 以前の問題。actions/resources/principal を見直す（§6 へ）。

### 5-5. Step 4-b：aws:SourceArn の正しい ARN 形式

**Step 4-b-1：SourceArn = delivery-source の ARN（公式方式。既定値）**

```hcl
enable_log_delivery              = true
enable_log_group_resource_policy = true
enable_resource_policy_condition = true
source_arn_pattern               = "delivery_source"
```

```bash
terraform apply
terraform output effective_source_arn_in_policy   # 実際に入っている値を確認
# PutEvents → 数分待つ → ログ確認
```

- 解釈：出力される → **`aws:SourceArn` には delivery-source の ARN が入る**と確定
  （`arn:aws:logs:ap-northeast-1:{ACCOUNT_ID}:delivery-source:{名前}`）。
  現行設計案（ロググループ ARN 流用）は誤りと確定。

**Step 4-b-2：SourceArn = ロググループの ARN（現行設計案の形式）**

```hcl
source_arn_pattern = "log_group"
```

```bash
terraform apply
terraform output effective_source_arn_in_policy
# PutEvents → 数分待つ → ログ確認
```

- 解釈：
  - 出力されない → **ロググループ ARN を `aws:SourceArn` に入れるのは誤り**と確定。
    Step 4-b-1 と対にすることで正しい形式が delivery-source ARN だと二重確認できる。
  - 万一出力された → 両形式とも通る。§6 で実際に渡される `aws:SourceArn` の値を確認し最終判断。

### 5-6. Step 5：デフォルトイベントバスでも同じ方法でポリシーを付与できるか

デフォルトバス（`default`）は Terraform で新規作成できない（既存リソース）。
挙動差は CLI / コンソールで確認する（Terraform 管理外）。

```bash
# 1. デフォルトバスの log_config を TRACE に設定
aws events update-event-bus --region ap-northeast-1 \
  --name default --log-config IncludeDetail=FULL,Level=TRACE

# 2. デフォルトバス用の delivery-source を作成
aws logs put-delivery-source --region ap-northeast-1 \
  --name default-bus-src-INFO \
  --log-type INFO_LOGS \
  --resource-arn arn:aws:events:ap-northeast-1:{ACCOUNT_ID}:event-bus/default
```

- 3. destination / delivery / ロググループのリソースポリシーはカスタムバスと同じ手順。
- 4. デフォルトバスへ PutEvents（`EventBusName` を省略 or `default`）してログ確認。
- 解釈：
  - カスタムバスと同じ手順で出力される → デフォルトバスも同一方式でよい。
  - 出力されない / 設定不可 → デフォルトバス固有の制約あり。差分を記録。
- 要確認：
  - `update-event-bus` / `--log-config` は CLI リファレンス上は実在。ただしデフォルトバスに
    log_config を適用できるか（カスタムバス固有でないか）は実機で要確認。
  - `put-delivery-source` の `resource-arn` にデフォルトバス ARN（末尾 `event-bus/default`）を
    指定できるかは要確認。
  - コンソールの EventBridge > Event buses > default > Logging からも設定できる場合がある。

> 補足（情報源B の「PutPermission では付与しづらい」挙動）：
> 情報源B は `events:PutPermission` では `AllowVendedLogDeliveryForResource` を付与しづらいと言及。
> 本検証はイベントバスのリソースベースポリシーに依存しない公式方式（ロググループ側ポリシー）で
> 通るため `PutPermission` 経路は使わない。現行設計案を再現検証したい場合は
> `aws events put-resource-policy`（要確認：コマンド実在性）での付与を試み、§6 でエラーを確認する。

---

## 6. 権限エラー時の調査手順（CloudTrail）

ログが出ない／`apply` が権限で失敗する場合、CloudTrail で該当 API 呼び出しと、
実際に渡された `aws:SourceArn` の値を確認する。

```bash
# ログ配信に関わる API（例）を直近で検索
aws cloudtrail lookup-events --region ap-northeast-1 \
  --lookup-attributes AttributeKey=EventSource,AttributeValue=logs.amazonaws.com \
  --max-results 20

# イベント名で絞る場合（例：CreateDelivery / PutDeliverySource）
aws cloudtrail lookup-events --region ap-northeast-1 \
  --lookup-attributes AttributeKey=EventName,AttributeValue=CreateDelivery \
  --max-results 20
```

- 確認ポイント：
  - `errorCode` / `errorMessage`（`AccessDenied` 等）
  - `requestParameters` / `additionalEventData` に現れる `resourceArn` や条件評価の対象
  - 実際に評価された `aws:SourceArn` の値（ロググループ ARN か delivery-source ARN か）
- `events:AllowVendedLogDeliveryForResource` の要否を切り分けるときは、この権限を外して
  `apply` → CloudTrail で拒否された API と Principal を確認する。

> 注意：CloudTrail に記録されるまで数分のラグがある。管理イベントは既定で記録されるが、
> データイベントは証跡設定に依存する。

---

## 7. 後片付け（クリーンアップ）

```bash
terraform destroy
```

- Step 5 で CLI から手動作成したデフォルトバス向けリソース（delivery-source / destination /
  delivery / ロググループのリソースポリシー）は Terraform 管理外なので、手動で削除する:

```bash
aws logs delete-delivery --region ap-northeast-1 --id <delivery-id>
aws logs delete-delivery-destination --region ap-northeast-1 --name <destination-name>
aws logs delete-delivery-source --region ap-northeast-1 --name default-bus-src-INFO
# デフォルトバスの log_config を OFF に戻す
aws events update-event-bus --region ap-northeast-1 --name default --log-config Level=OFF
```

> デフォルトバスは削除せず、log_config を `OFF` に戻すだけにする（既存の共有リソースのため）。

---

## 8. 結果記入表

検証後に下表を埋めれば、検証したかったこと 1〜5 の結論がそのまま記録として残る。

| # | 検証したいこと | 対応 Step | ログ出力 | 判明した結論（記入） |
|---|---|---|---|---|
| 1 | ポリシー・配信無しで出力されるか | Step 1 | ☐出た / ☐出ない | |
| 2 | 情報源A のアイデンティティベースのみで出力されるか | Step 2→3 | ☐出た / ☐出ない | |
| 3 | リソースベースポリシーは Condition 無しで出力されるか | Step 4-a | ☐出た / ☐出ない | |
| 4 | `aws:SourceArn` に入る実際の ARN 形式は何か | Step 4-b | ☐delivery-source / ☐log_group / ☐両方 | |
| 5 | デフォルトバスでも同じ方法で付与できるか | Step 5 | ☐出た / ☐出ない / ☐設定不可 | |

### 事前調査からの想定（実機で上書き確認する）

| # | 想定（事前調査） |
|---|---|
| 1 | 出ない（配信パイプラインが無いと出力されない見込み） |
| 2 | 情報源A は「設定操作用」の権限。実行時出力はロググループ側ポリシーに依存する見込み |
| 3 | リソースポリシーは必要。Condition 無しでも出力される見込み |
| 4 | delivery-source の ARN（`arn:aws:logs:...:delivery-source:...`）。ロググループ ARN は誤りの見込み |
| 5 | 要実機確認（update-event-bus の default 適用可否、put-delivery-source の default ARN 指定可否） |

### 補足メモ欄

- 待ち時間の実測：
- 出力されたログステップ名（例：RULE_MATCH_STARTED / NO_RULES_MATCHED）：
- CloudTrail で確認した実際の `aws:SourceArn`：
- その他気づき：

---

## 9. 参考（AWS 公式ドキュメント / Terraform）

- [Configuring logs for Amazon EventBridge event buses](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-event-bus-logs.html)
  … 情報源A。ログ設定とアイデンティティベースポリシーの説明
- [Enabling logging from AWS services（CloudWatch Logs / vended logs 権限）](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/AWS-logs-and-resource-policy.html)
  … delivery-source/destination/delivery と V2 権限の説明
- [Terraform: aws_cloudwatch_event_bus（公式レジストリ）](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_bus)
  … `log_config` と CloudWatch Logs 宛先の完全な構成例（本検証の構成の根拠）
- [How do I configure an event bus to allow vended log delivery?（AWS re:Post）](https://repost.aws/questions/QU0c8gTGVwSlW_q8i9pYCS0A/how-do-i-configure-an-event-bus-to-allow-vended-log-delivery)
  … 情報源B。リソースベースポリシーと条件キーに関する言及
