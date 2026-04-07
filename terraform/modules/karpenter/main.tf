# IAM Role for Karpenter Controller
resource "aws_iam_role" "karpenter_controller" {
  name = "${var.project_name}-karpenter-controller"

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
            "${replace(var.oidc_provider_url, "https://", "")}:sub" = "system:serviceaccount:karpenter:karpenter"
            "${replace(var.oidc_provider_url, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = var.tags
}

# Karpenter Controller Policy
resource "aws_iam_role_policy" "karpenter_controller" {
  name = "${var.project_name}-karpenter-controller-policy"
  role = aws_iam_role.karpenter_controller.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "ssm:GetParameter",
          "ec2:DescribeImages",
          "ec2:RunInstances",
          "ec2:DescribeSubnets",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeLaunchTemplates",
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeInstanceTypeOfferings",
          "ec2:DescribeAvailabilityZones",
          "ec2:DeleteLaunchTemplate",
          "ec2:CreateTags",
          "ec2:CreateLaunchTemplate",
          "ec2:CreateFleet",
          "ec2:DescribeSpotPriceHistory",
          "pricing:GetProducts"
        ]
        Effect   = "Allow"
        Resource = "*"
      },
      {
        Action   = "ec2:TerminateInstances"
        Effect   = "Allow"
        Resource = "*"
        Condition = {
          StringEquals = {
            "ec2:ResourceTag/karpenter.sh/discovery" = var.cluster_name
          }
        }
      },
      {
        Action   = "iam:PassRole"
        Effect   = "Allow"
        Resource = aws_iam_role.karpenter_node.arn
      },
      {
        Action   = "eks:DescribeCluster"
        Effect   = "Allow"
        Resource = var.cluster_arn
      },
      {
        Action = [
          "iam:CreateInstanceProfile",
          "iam:AddRoleToInstanceProfile",
          "iam:RemoveRoleFromInstanceProfile",
          "iam:DeleteInstanceProfile",
          "iam:GetInstanceProfile",
          "iam:TagInstanceProfile",
          "iam:UntagInstanceProfile"
        ]
        Effect   = "Allow"
        Resource = "*"
      },
      {
        Action = [
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:ReceiveMessage"
        ]
        Effect   = "Allow"
        Resource = aws_sqs_queue.karpenter.arn
      }
    ]
  })
}

# IAM Role for Karpenter Nodes
resource "aws_iam_role" "karpenter_node" {
  name = "${var.project_name}-karpenter-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "karpenter_node_policies" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  ])

  policy_arn = each.value
  role       = aws_iam_role.karpenter_node.name
}

# SQS Queue for Spot Interruption
resource "aws_sqs_queue" "karpenter" {
  name                      = "${var.cluster_name}-karpenter"
  message_retention_seconds = 300
}

# EventBridge Rules for Spot Interruption
resource "aws_cloudwatch_event_rule" "spot_interruption" {
  name        = "${var.cluster_name}-spot-interruption"
  description = "EKS Spot Interruption Handler"
  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Spot Instance Interruption Warning"]
  })
}

resource "aws_cloudwatch_event_target" "spot_interruption" {
  rule      = aws_cloudwatch_event_rule.spot_interruption.name
  target_id = "KarpenterK8sInternal"
  arn       = aws_sqs_queue.karpenter.arn
}

# Allow EventBridge to send interruption events to SQS
resource "aws_sqs_queue_policy" "karpenter" {
  queue_url = aws_sqs_queue.karpenter.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowEventBridgeSendMessage"
        Effect    = "Allow"
        Principal = { Service = "events.amazonaws.com" }
        Action    = "sqs:SendMessage"
        Resource  = aws_sqs_queue.karpenter.arn
      }
    ]
  })
}
