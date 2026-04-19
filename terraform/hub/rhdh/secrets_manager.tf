#------------------------------------------------------------------------------
# Secrets Manager -- RHDH 用シークレット
#
# PLACEHOLDER 値で作成し、手動で実値を設定する。
# lifecycle ignore_changes で Terraform が上書きしないようにする。
#
# ExternalSecret (ESO) からこれらを参照して OpenShift Secret に同期する。
#------------------------------------------------------------------------------

resource "aws_secretsmanager_secret" "rhdh_github_oauth" {
  name       = "openshift/rhdh/github-oauth"
  kms_key_id = aws_kms_key.rhdh.arn

  tags = {
    Name = "rhdh-github-oauth-${var.environment}"
  }
}

resource "aws_secretsmanager_secret_version" "rhdh_github_oauth" {
  secret_id = aws_secretsmanager_secret.rhdh_github_oauth.id
  secret_string = jsonencode({
    clientId     = "PLACEHOLDER"
    clientSecret = "PLACEHOLDER"
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}

resource "aws_secretsmanager_secret" "rhdh_github_app" {
  name       = "openshift/rhdh/github-app"
  kms_key_id = aws_kms_key.rhdh.arn

  tags = {
    Name = "rhdh-github-app-${var.environment}"
  }
}

resource "aws_secretsmanager_secret_version" "rhdh_github_app" {
  secret_id = aws_secretsmanager_secret.rhdh_github_app.id
  secret_string = jsonencode({
    appId        = "PLACEHOLDER"
    clientId     = "PLACEHOLDER"
    clientSecret = "PLACEHOLDER"
    privateKey   = "PLACEHOLDER"
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}

resource "aws_secretsmanager_secret" "rhdh_db" {
  name       = "openshift/rhdh/database"
  kms_key_id = aws_kms_key.rhdh.arn

  tags = {
    Name = "rhdh-database-${var.environment}"
  }
}

resource "aws_secretsmanager_secret_version" "rhdh_db" {
  secret_id = aws_secretsmanager_secret.rhdh_db.id
  secret_string = jsonencode({
    host     = aws_rds_cluster.rhdh.endpoint
    port     = "5432"
    username = aws_rds_cluster.rhdh.master_username
    password = "PLACEHOLDER"
    database = aws_rds_cluster.rhdh.database_name
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}
