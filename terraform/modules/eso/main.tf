# IAM Role for ESO
resource "aws_iam_role" "eso" {
  name = "${var.project_name}-eso-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = var.oidc_provider_arn
        }
        Condition = {
          StringEquals = {
            "${replace(var.oidc_provider_url, "https://", "")}:sub" = "system:serviceaccount:external-secrets:external-secrets"
            "${replace(var.oidc_provider_url, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = var.tags
}

# ESO Policy to access Secrets Manager
resource "aws_iam_role_policy" "eso" {
  name = "${var.project_name}-eso-policy"
  role = aws_iam_role.eso.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
          "secretsmanager:ListSecrets",
          "secretsmanager:ListSecretVersionIds"
        ]
        Effect   = "Allow"
        Resource = [
          "arn:aws:secretsmanager:*:*:secret:${var.project_name}-*",
          "arn:aws:secretsmanager:*:*:secret:oauth2-proxy-*"
        ]
      }
    ]
  })
}

output "eso_role_arn" {
  value = aws_iam_role.eso.arn
}
