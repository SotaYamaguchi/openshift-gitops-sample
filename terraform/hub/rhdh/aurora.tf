#------------------------------------------------------------------------------
# Aurora PostgreSQL -- RHDH (Red Hat Developer Hub) データベース
#
# ROSA HCP の VPC 内に直接 Aurora を配置する。
# DB Subnet Group には最低 2 AZ 必要なため、別 AZ に追加サブネットを作成。
# manage_master_user_password = true で AWS Secrets Manager がパスワード自動管理。
#
# Non-functional Requirements:
#   - ROSA VPC Private Subnet 配置、インターネット非公開
#   - KMS CMK で保存時暗号化
#   - Single Instance (Sandbox 向け、本番では count=2 に変更)
#   - バックアップ: 日次取得、7日保持
#   - メンテナンス窓: 日曜 02:00-06:00 JST (= sat:17:00-sat:21:00 UTC)
#
# ref: https://access.redhat.com/documentation/en-us/red_hat_developer_hub/1.9/html-single/configuring/index
#------------------------------------------------------------------------------

############################
# Aurora 用追加サブネット
############################

# 既存 VPC に別 AZ の Private Subnet を追加 (DB Subnet Group の 2 AZ 要件)
resource "aws_subnet" "aurora_secondary" {
  vpc_id            = var.vpc_id
  cidr_block        = "10.0.1.0/24"
  availability_zone = data.aws_availability_zones.available.names[1] # us-east-2b

  tags = {
    Name = "rhdh-aurora-private-${data.aws_availability_zones.available.names[1]}"
  }
}

############################
# KMS Key
############################

resource "aws_kms_key" "rhdh" {
  description             = "KMS key for RHDH Aurora PostgreSQL"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  tags = {
    Name = "rhdh-${var.environment}"
  }
}

resource "aws_kms_alias" "rhdh" {
  name          = "alias/rhdh-${var.environment}"
  target_key_id = aws_kms_key.rhdh.key_id
}

############################
# DB Subnet Group
############################

resource "aws_db_subnet_group" "rhdh" {
  name        = "rhdh-${var.environment}"
  description = "Subnet group for RHDH Aurora PostgreSQL (${var.environment})"
  subnet_ids = [
    var.private_subnet_id,
    aws_subnet.aurora_secondary.id,
  ]

  tags = {
    Name = "rhdh-${var.environment}"
  }
}

############################
# Security Group
############################

resource "aws_security_group" "rhdh_aurora" {
  name        = "rhdh-${var.environment}-aurora"
  description = "Security group for RHDH Aurora PostgreSQL (${var.environment})"
  vpc_id      = var.vpc_id

  tags = {
    Name = "rhdh-${var.environment}-aurora"
  }
}

resource "aws_vpc_security_group_ingress_rule" "rhdh_aurora_from_vpc" {
  security_group_id = aws_security_group.rhdh_aurora.id
  description       = "Allow PostgreSQL from VPC CIDR"
  cidr_ipv4         = data.aws_vpc.cluster.cidr_block
  from_port         = 5432
  to_port           = 5432
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "rhdh_aurora_to_all" {
  security_group_id = aws_security_group.rhdh_aurora.id
  description       = "Allow all outbound traffic"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

############################
# Aurora Cluster
############################

resource "aws_rds_cluster" "rhdh" {
  cluster_identifier = "rhdh-${var.environment}"

  engine         = "aurora-postgresql"
  engine_version = "15.10"

  database_name   = "backstage"
  master_username = "backstage_admin"

  # AWS が Secrets Manager でマスターパスワードを自動管理
  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.rhdh.name
  vpc_security_group_ids = [aws_security_group.rhdh_aurora.id]

  # 暗号化
  storage_encrypted = true
  kms_key_id        = aws_kms_key.rhdh.arn

  # バックアップ (Sandbox 向け: 7日)
  backup_retention_period      = 7
  preferred_backup_window      = "16:00-17:00"
  preferred_maintenance_window = "sat:17:00-sat:21:00"
  copy_tags_to_snapshot        = true

  # 保護 (Sandbox では false、本番では true に変更)
  deletion_protection = false
  skip_final_snapshot = true

  # ログ出力
  enabled_cloudwatch_logs_exports = ["postgresql"]

  tags = {
    Name = "rhdh-${var.environment}"
  }
}

############################
# Aurora Instance (Single)
############################

resource "aws_rds_cluster_instance" "rhdh" {
  identifier         = "rhdh-${var.environment}-0"
  cluster_identifier = aws_rds_cluster.rhdh.id

  engine         = aws_rds_cluster.rhdh.engine
  engine_version = aws_rds_cluster.rhdh.engine_version
  instance_class = "db.t4g.medium"

  db_subnet_group_name = aws_db_subnet_group.rhdh.name

  # 監視
  performance_insights_enabled    = true
  performance_insights_kms_key_id = aws_kms_key.rhdh.arn

  preferred_maintenance_window = "sat:17:00-sat:21:00"
  copy_tags_to_snapshot        = true
  auto_minor_version_upgrade   = true

  tags = {
    Name = "rhdh-${var.environment}-0"
  }
}

############################
# Outputs
############################

output "rhdh_aurora_endpoint" {
  description = "Aurora cluster endpoint for RHDH"
  value       = aws_rds_cluster.rhdh.endpoint
}

output "rhdh_aurora_master_secret_arn" {
  description = "ARN of the Secrets Manager secret for Aurora master password"
  value       = aws_rds_cluster.rhdh.master_user_secret[0].secret_arn
}
