#------------------------------------------------------------------------------
# IRSA -- External Secrets Operator が Secrets Manager にアクセスするためのロール
#
# Trusted SA: rhdh namespace の external-secrets SA
# Policy: SecretsManager read + KMS decrypt (openshift/rhdh/* スコープ)
#------------------------------------------------------------------------------

resource "aws_iam_role" "rhdh_eso" {
  name = "rhdh-external-secrets-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = var.oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${var.oidc_provider_url}:sub" = "system:serviceaccount:rhdh:external-secrets"
          }
        }
      },
    ]
  })

  tags = {
    Name = "rhdh-external-secrets-${var.environment}"
  }
}

resource "aws_iam_role_policy" "rhdh_eso" {
  name = "rhdh-secrets-access"
  role = aws_iam_role.rhdh_eso.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SecretsManagerRead"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
        ]
        Resource = "arn:aws:secretsmanager:${var.region}:${data.aws_caller_identity.current.account_id}:secret:openshift/rhdh/*"
      },
      {
        Sid    = "KMSDecrypt"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey",
        ]
        Resource = aws_kms_key.rhdh.arn
      },
    ]
  })
}

output "rhdh_eso_role_arn" {
  description = "IAM Role ARN for RHDH ExternalSecrets ServiceAccount"
  value       = aws_iam_role.rhdh_eso.arn
}
