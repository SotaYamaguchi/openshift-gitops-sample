#------------------------------------------------------------------------------
# Aurora PostgreSQL -- RHDH (Red Hat Developer Hub) データベース
#
# RHDH の enableLocalDb を外部 Aurora PostgreSQL に置き換える。
# manage_master_user_password = true により、AWS が Secrets Manager で
# マスターパスワードを自動管理する。
#
# Non-functional Requirements:
#   - Private Subnet 配置、インターネット非公開
#   - KMS CMK で保存時暗号化
#   - Multi-AZ (2 インスタンス)
#   - バックアップ: 日次取得、30日保持
#   - メンテナンス窓: 日曜 02:00-06:00 JST (= sat:17:00-sat:21:00 UTC)
#
# ref: https://access.redhat.com/documentation/en-us/red_hat_developer_hub/1.9/html-single/configuring/index
#------------------------------------------------------------------------------

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
  subnet_ids  = data.aws_subnets.private.ids

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
  vpc_id      = data.aws_vpc.cluster.id

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

  # バックアップ
  backup_retention_period      = 30
  preferred_backup_window      = "16:00-17:00"
  preferred_maintenance_window = "sat:17:00-sat:21:00"
  copy_tags_to_snapshot        = true

  # 保護
  deletion_protection = true

  # ログ出力
  enabled_cloudwatch_logs_exports = ["postgresql"]

  tags = {
    Name = "rhdh-${var.environment}"
  }
}

############################
# Aurora Instance
############################

resource "aws_rds_cluster_instance" "rhdh" {
  count = 2

  identifier         = "rhdh-${var.environment}-${count.index}"
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
    Name = "rhdh-${var.environment}-${count.index}"
  }
}

############################
# Outputs
############################

output "rhdh_aurora_endpoint" {
  description = "Aurora cluster endpoint for RHDH"
  value       = aws_rds_cluster.rhdh.endpoint
}

output "rhdh_aurora_reader_endpoint" {
  description = "Aurora reader endpoint for RHDH"
  value       = aws_rds_cluster.rhdh.reader_endpoint
}
