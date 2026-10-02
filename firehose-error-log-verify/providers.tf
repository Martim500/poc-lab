terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.44.0"
    }
  }
}

provider "aws" {
  region = "ap-northeast-1"

  default_tags {
    tags = {
      TISI_kensyo = "true"
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
