data "aws_caller_identity" "current" {}

data "aws_vpc" "cluster" {
  id = var.vpc_id
}

data "aws_subnet" "existing_private" {
  id = var.private_subnet_id
}

# Aurora DB Subnet Group には最低 2 AZ が必要
# 既存の ROSA VPC には us-east-2a の Private Subnet しかないため
# us-east-2b に Aurora 用の追加 Private Subnet を作成する
data "aws_availability_zones" "available" {
  state = "available"
}
