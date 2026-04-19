terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # backend は環境に合わせて設定すること
  # backend "s3" {
  #   bucket = "<your-terraform-state-bucket>"
  #   key    = "hub/rhdh/terraform.tfstate"
  #   region = "<your-region>"
  # }
}

provider "aws" {
  # region は変数で制御
  region = var.region
}
