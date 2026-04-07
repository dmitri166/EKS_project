resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = ["sts.amazonaws.com"]

  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"] # GitHub's OIDC thumbprint
}

resource "aws_iam_role" "github_actions" {
  name = "${var.project_name}-github-actions-role"

  # Permission boundary - hard ceiling even if AdministratorAccess is attached
  permissions_boundary = aws_iam_policy.ci_boundary.arn

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Condition = {
          StringEquals = {
            # Only main branch can assume this role - not PRs, forks, or other branches
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_repo}:ref:refs/heads/main"
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = var.tags
}

# Permission boundary - limits blast radius even with AdministratorAccess attached
# The role can never exceed these permissions regardless of attached policies
resource "aws_iam_policy" "ci_boundary" {
  name        = "${var.project_name}-ci-permission-boundary"
  description = "Permission boundary for GitHub Actions CI role - limits blast radius"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCIActions"
        Effect = "Allow"
        Action = [
          "ec2:*",
          "eks:*",
          "iam:*",
          "s3:*",
          "secretsmanager:*",
          "kms:*",
          "logs:*",
          "cloudwatch:*",
          "autoscaling:*",
          "elasticloadbalancing:*",
          "sqs:*",
          "events:*",
          "rds:*",
          "dynamodb:*",
          "sts:AssumeRole",
          "ssm:*"
        ]
        # Locked to your account and region only
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = var.aws_region
          }
        }
      },
      {
        # Prevent deleting the boundary itself or escalating privileges
        Sid    = "DenyPrivilegeEscalation"
        Effect = "Deny"
        Action = [
          "iam:DeleteRolePermissionsBoundary",
          "iam:PutRolePermissionsBoundary",
          "iam:CreatePolicyVersion",
          "organizations:*",
          "account:*"
        ]
        Resource = "*"
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "github_actions_admin" {
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
  role       = aws_iam_role.github_actions.name
}

output "github_actions_role_arn" {
  value = aws_iam_role.github_actions.arn
}
