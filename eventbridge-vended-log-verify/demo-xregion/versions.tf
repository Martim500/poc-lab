terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.44.0"
    }
  }
}

# 東京（デフォルト）: 受信側・集約先
provider "aws" {
  region = "ap-northeast-1"
}

# us-east-1（送信側）
provider "aws" {
  alias  = "use1"
  region = "us-east-1"
}

data "aws_caller_identity" "current" {}

locals {
  account_id      = data.aws_caller_identity.current.account_id
  tokyo_bus_name  = "xregion-tokyo-bus"
  tokyo_bus_arn   = "arn:aws:events:ap-northeast-1:${local.account_id}:event-bus/${local.tokyo_bus_name}"
  us_default_bus  = "arn:aws:events:us-east-1:${local.account_id}:event-bus/default"
  log_group_name  = "/aws/vendedlogs/events/event-bus/${local.tokyo_bus_name}"
}
