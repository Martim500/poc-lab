# 追加検証: デフォルトイベントバスを Terraform で管理できるか

関連 issue: hashicorp/terraform-provider-aws #41585
「Allow terraform to manage the default event bus」（2025 年起票）が、
AWS Provider v6.44.0 で改善されているかを確認した。

- 検証リージョン: ap-northeast-1
- AWS Provider: v6.44.0
- アカウントID は `{ACCOUNT_ID}` に置換して記載。

## 検証に使った構成

```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.44.0"
    }
  }
}

resource "aws_cloudwatch_event_bus" "default" {
  name = "default"
}
```

## 結果サマリ

| 操作 | 結果 |
|---|---|
| 新規作成（plan / apply） | ✗ plan 段階でバリデーションエラー（`name` に `default` は不可） |
| import | ✓ 成功（state に取り込める。既存の log_config も反映される） |
| import 後の plan | ✗ 同じバリデーションエラーで失敗 |

→ **import は一度通るが、その後の plan/apply が必ず同じエラーで失敗する**ため、
継続管理（plan→apply のサイクル）ができない。実質的にデフォルトバスは
`aws_cloudwatch_event_bus` リソースでは管理不可。issue #41585 は v6.44.0 時点でも未解決。

## 各ステップの実ログ

### 1. 新規作成（plan）→ バリデーションエラー

```
Error: invalid value for name (cannot be 'default')

  with aws_cloudwatch_event_bus.default,
  on main.tf line 19, in resource "aws_cloudwatch_event_bus" "default":
  19:   name = "default"
```

### 2. import → 成功

```
aws_cloudwatch_event_bus.default: Importing from ID "default"...
aws_cloudwatch_event_bus.default: Import prepared!
  Prepared aws_cloudwatch_event_bus for import
```

import 後の state（`terraform state show`）:

```hcl
# aws_cloudwatch_event_bus.default:
resource "aws_cloudwatch_event_bus" "default" {
    arn                = "arn:aws:events:ap-northeast-1:{ACCOUNT_ID}:event-bus/default"
    id                 = "default"
    name               = "default"
    region             = "ap-northeast-1"

    log_config {
        include_detail = "FULL"
        level          = "TRACE"
    }
}
```

（log_config は、先行して CLI で設定した値がそのまま反映されている）

### 3. import 後の plan → バリデーションエラー

```
Error: invalid value for name (cannot be 'default')

  with aws_cloudwatch_event_bus.default,
  on main.tf line 16, in resource "aws_cloudwatch_event_bus" "default":
  16:   name = "default"
```

## 実務上の結論

- 本番でデフォルトバスのログ設定（log_config）や delivery を Terraform
  （`aws_cloudwatch_event_bus`）で管理することはできない。
- デフォルトバス関連は CloudShell / AWS CLI で手動設定する（consolelog.md の手順で動作確認済み）。
- カスタムイベントバスは Terraform で問題なく管理できる。
