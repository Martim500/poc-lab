# 引き継ぎメモ（次セッション用）

このファイルは次セッションへの申し送り。作業再開時にまず読むこと。
※このファイルは一時メモ。Git には上げない（.gitignore で除外済み）。

## 0. 最重要: OneDrive 問題で作業場所を移す

このフォルダは OneDrive 配下（`<OneDrive配下の作業フォルダ>\eventbridge-vended-log-verify`）。
OneDrive 同期ラグで以下の実害が出ていた:
- terraform のログ/一時ファイルを書いても read で「見つからない」が頻発
- `terraform.tfstate` が保存前に同期が絡み、state 不整合（リソースは作られたが state 空）が発生
- `.terraform/`（プロバイダ exe）が terraform-ls でロックされ削除が引っかかる

**次セッションの方針**: 検証実行は OneDrive 外（例 `C:\work\eventbridge-verify`）で行う。
コード（.tf/.md）だけ OneDrive 側の Git リポジトリに戻す。
→ 「フォルダごと移動させてセッションを変えて再開」という指示はこの意味。

## 1. 環境情報（毎回必要）

- terraform: PATH に無いことがある。`$env:Path += ';C:\terraform'` で通る（`C:\terraform\terraform.exe` v1.8.5）。
- AWS: `$env:AWS_PROFILE = "<your-profile>"`（検証用アカウント 123456789012 / IAMユーザー verify-user）。
  - 実行時は毎回 `$env:AWS_PROFILE = "<your-profile>"` を設定する。
- git: PATH に無い。`<Gitインストール先>\cmd\git.exe` を直接指定。
- AWS CLI はローカルが v2.15 で `aws events update-event-bus` 未対応。
  → デフォルトバス/カスタムバスの log_config 設定は CloudShell（最新CLI）で行う必要がある。
- リージョン: 検証は ap-northeast-1 基本。クロスリージョンは us-east-1 → ap-northeast-1。
- terraform コマンドは `-lock=false` を付けると OneDrive 上の state ロック問題を回避できる。

## 2. Git リポジトリ

- リモート: https://github.com/Martim500/poc-lab.git（public）。認証は HTTPS + GCM（保存済み）。
- ローカルリポジトリのルートは `個人ファイル\検証`（＝このフォルダの1つ上）。
  - `検証/.git` が本リポジトリ。`検証/README.md` が全体 README、`検証/.gitignore` が全体除外設定。
  - この eventbridge フォルダは `検証/eventbridge-vended-log-verify/` としてコミット対象。
- コミット作者: 個人の GitHub アカウントを使う（会社メールは使わない）。
- push 済みの最新: 「Add default-bus & non-vendedlogs-prefix verification results」まで。
  今回の追加分（RESULTS §7、default-bus-terraform-check.md 等）は未 push。

## 3. 検証の現在地（確定事項）

詳細は RESULTS.md 参照。要点:
- (a) ログ配信: イベントバス側ポリシー不要。宛先ロググループ側ポリシー＋delivery パイプラインが要件。
- aws:SourceArn は delivery-source ARN / ロググループ ARN どちらでも配信された（当初「ロググループは誤り」は撤回）。
- ロググループ側ポリシー無しでも配信された（この検証アカウントでの実測。本番相当環境で要再確認）。
- デフォルトバスでもカスタムバスと同一方法で配信成立（consolelog.md）。
- デフォルトバスは Terraform `aws_cloudwatch_event_bus` では管理不可（name=default が plan で弾かれる。
  import は通るが以後の plan で必ず失敗）。default-bus-terraform-check.md 参照。
- `aws_cloudwatch_event_bus_policy` は event_bus_name="default" を plan 通過（ポリシーだけは付けられる）。

## 4. 進行中の作業: クロスリージョン転送(b)の実機検証（demo-xregion）

### 目的
us-east-1 デフォルトバス →（ルール+xregionロール）→ 東京カスタムバス →（ログ配信）→ CloudWatch Logs。
受信側バスポリシー「あり」で成功確認 → 「なし」で同一アカウントなら不要かを検証。

### demo-xregion の構成（.tf は作成済み）
- versions.tf: 東京(デフォルト)＋us-east-1(alias use1)のマルチリージョン provider
- tokyo.tf: 東京カスタムバス `xregion-tokyo-bus` ＋ ログ配信一式（SourceArn=ロググループ ARN）
- receiver_policy.tf: 東京バスの受信用リソースポリシー（events:PutEvents）。変数 `enable_receiver_bus_policy` でトグル（既定 true）
- use1.tf: us-east-1 デフォルトバスのルール `xregion-health-global-fwd` → ターゲット=東京バス、IAMロール `xregion-forward-role`
- variables.tf / outputs.tf

### 現在の問題（state 不整合）
前回の apply で OneDrive 同期が絡み、**リソースは AWS に作られたのに state が空**になった。
再 apply すると「already exists」エラーになる。

### AWS 上に残っている残骸（Terraform 管理外）※次セッションで要クリーンアップ
- 東京バス: `xregion-tokyo-bus`
- 東京ロググループ: `/aws/vendedlogs/events/event-bus/xregion-tokyo-bus`
- delivery-destination: `xregion-tokyo-dst-cwl`
- リソースポリシー: `AWSLogDeliveryWrite-xregion-tokyo`
- IAMロール: `xregion-forward-role`
- us-east-1 ルール: `xregion-health-global-fwd`（ターゲットも付いている可能性）
- 旧 demo（demo-default-loggrouparn）の残骸: delivery-source `demo-default-src-INFO`、
  リソースポリシー `AWSLogDeliveryWrite-demo-default`、ロググループ `/aws/vendedlogs/events/event-bus/default`、
  delivery-destination `demo-default-dst-cwl`

## 5. 次セッションでやること（手順）

1. このフォルダを OneDrive 外（例 `C:\work\eventbridge-verify`）にコピー。
   state/.terraform は壊れているのでコピーせず、.tf/.md/.json だけ移す。
2. AWS 残骸をクリーンアップ（下記コマンド）。
3. `C:\work\eventbridge-verify\demo-xregion` で init → apply（enable_receiver_bus_policy=true）し直す。
4. CloudShell で東京バスの log_config を有効化:
   `aws events update-event-bus --name xregion-tokyo-bus --log-config IncludeDetail=FULL,Level=TRACE --region ap-northeast-1`
5. _demo-console-steps.md の手順で検証（一意文字列 20261010-0001 形式を手動採番）。
6. 受信側ポリシーあり→成功を確認後、enable_receiver_bus_policy=false で apply し再検証。
7. 結果を RESULTS.md §7-3 に記入。
8. 機微情報スキャン後、Git に push。

### AWS 残骸クリーンアップ用コマンド（CloudShell 推奨。{ACCOUNT_ID} は 123456789012）
```bash
# 東京側ログ配信
aws logs delete-delivery-destination --name xregion-tokyo-dst-cwl --region ap-northeast-1
aws logs delete-delivery-source --name xregion-tokyo-src-INFO --region ap-northeast-1 2>/dev/null
aws logs delete-resource-policy --policy-name AWSLogDeliveryWrite-xregion-tokyo --region ap-northeast-1
aws logs delete-log-group --log-group-name /aws/vendedlogs/events/event-bus/xregion-tokyo-bus --region ap-northeast-1
# 東京カスタムバス（log_config を OFF にしてから削除）
aws events delete-event-bus --name xregion-tokyo-bus --region ap-northeast-1
# us-east-1 ルール（先にターゲット削除）
aws events remove-targets --rule xregion-health-global-fwd --event-bus-name default --ids tokyo-custom-bus --region us-east-1
aws events delete-rule --name xregion-health-global-fwd --event-bus-name default --region us-east-1
# IAMロール（先にインラインポリシー削除）
aws iam delete-role-policy --role-name xregion-forward-role --policy-name xregion-forward-putevents 2>/dev/null
aws iam delete-role --role-name xregion-forward-role
# 旧 demo-default の残骸
aws logs delete-delivery-source --name demo-default-src-INFO --region ap-northeast-1
aws logs delete-resource-policy --policy-name AWSLogDeliveryWrite-demo-default --region ap-northeast-1
aws logs delete-delivery-destination --name demo-default-dst-cwl --region ap-northeast-1 2>/dev/null
aws logs delete-log-group --log-group-name /aws/vendedlogs/events/event-bus/default --region ap-northeast-1 2>/dev/null
# デフォルトバスの log_config を OFF に戻す
aws events update-event-bus --name default --log-config Level=OFF --region ap-northeast-1
```

## 6. ファイル仕分け（このフォルダ内）

### Git に上げる（公開対象。機微情報なし確認済み）
- .gitignore, README.md, RESULTS.md, consolelog.md, default-bus-terraform-check.md,
  iam-policy-required.json, main.tf, variables.tf, outputs.tf, versions.tf,
  terraform.tfvars.example, resource_policy.tf.disabled

### Git に上げない（一時/作業物。.gitignore 除外 or _始まり）
- HANDOFF.md（このファイル）, _demo-console-steps.md
- terraform.tfstate, terraform.tfstate.backup, .terraform.lock.hcl, .terraform/
- demo-xregion/, demo-default-loggrouparn/, _default-bus-policy-check/ の各 state/.terraform
  （.tf は引き継ぎ用に残す。state は壊れているので次セッションで作り直し）

### 本体ルートの .tf について（重要）
main.tf / resource_policy.tf.disabled / variables.tf 等は「コメント切り替え方式」。
- main.tf: 検証②（非vendedlogs名）が有効化された状態（log_group_name = "/verify-non-vendedlogs-prefix-01"）。
- resource_policy.tf は `.disabled` にリネーム済み（検証④-c でポリシー無しにしたため）。
  通常構成に戻すなら `.disabled` を外し、outputs.tf の effective_source_arn_in_policy のコメントを戻す。
