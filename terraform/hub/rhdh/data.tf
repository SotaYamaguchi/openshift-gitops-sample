data "aws_caller_identity" "current" {}

data "aws_vpc" "cluster" {
  id = var.vpc_id
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }

  tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }
}
