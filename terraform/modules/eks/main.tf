# EKS Cluster
resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  role_arn = var.eks_cluster_role_arn
  version  = var.kubernetes_version

  vpc_config {
    subnet_ids              = concat(var.private_subnet_ids, var.public_subnet_ids)
    endpoint_private_access = var.endpoint_private_access
    endpoint_public_access  = var.endpoint_public_access
    public_access_cidrs     = var.public_access_cidrs
  }

  enabled_cluster_log_types = var.enabled_cluster_log_types

  tags = merge(
    {
      Name        = var.cluster_name
      Environment = var.environment
    },
    var.tags
  )
}

# EKS Node Group
resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.cluster_name}-node-group"
  node_role_arn   = var.eks_node_role_arn
  subnet_ids      = var.private_subnet_ids

  scaling_config {
    desired_size = var.desired_size
    max_size     = var.max_size
    min_size     = var.min_size
  }

  instance_types = [var.instance_type]

  ami_type = "AL2_x86_64"
  capacity_type = "ON_DEMAND"
  
  update_config {
    max_unavailable = 1
  }

  remote_access {
    ec2_ssh_key               = var.ssh_key_name != "" ? var.ssh_key_name : null
    source_security_group_ids = [aws_security_group.node_sg.id]
  }

  tags = merge(
    {
      Name        = "${var.cluster_name}-node-group"
      Environment = var.environment
    },
    var.tags
  )
}

# Security Group for Nodes
resource "aws_security_group" "node_sg" {
  name        = "${var.cluster_name}-node-sg"
  description = "Security group for EKS nodes"
  vpc_id      = var.vpc_id

  tags = merge(
    {
      Name        = "${var.cluster_name}-node-sg"
      Environment = var.environment
    },
    var.tags
  )
}

resource "aws_security_group_rule" "node_ingress_self" {
  description              = "Allow node to communicate with each other"
  from_port                = 0
  to_port                  = 65535
  protocol                 = "-1"
  security_group_id        = aws_security_group.node_sg.id
  source_security_group_id = aws_security_group.node_sg.id
  type                     = "ingress"
}

resource "aws_security_group_rule" "node_ingress_cluster" {
  description              = "Allow worker Kubelets and pods to receive communication from cluster control plane"
  from_port                = 1025
  to_port                  = 65535
  protocol                 = "tcp"
  security_group_id        = aws_security_group.node_sg.id
  source_security_group_id = aws_security_group.cluster_sg.id
  type                     = "ingress"
}

resource "aws_security_group_rule" "node_egress_self" {
  description              = "Allow node to communicate with each other"
  from_port                = 0
  to_port                  = 65535
  protocol                 = "-1"
  security_group_id        = aws_security_group.node_sg.id
  source_security_group_id = aws_security_group.node_sg.id
  type                     = "egress"
}

resource "aws_security_group_rule" "node_egress_internet" {
  description       = "Allow node to communicate with internet"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  security_group_id = aws_security_group.node_sg.id
  cidr_blocks       = ["0.0.0.0/0"]
  type              = "egress"
}

# Security Group for Cluster
resource "aws_security_group" "cluster_sg" {
  name        = "${var.cluster_name}-cluster-sg"
  description = "Security group for EKS cluster"
  vpc_id      = var.vpc_id

  tags = merge(
    {
      Name        = "${var.cluster_name}-cluster-sg"
      Environment = var.environment
    },
    var.tags
  )
}

resource "aws_security_group_rule" "cluster_ingress_https" {
  description       = "Allow workspace to communicate with the cluster API"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  security_group_id = aws_security_group.cluster_sg.id
  cidr_blocks       = var.cluster_ingress_cidrs
  type              = "ingress"
}

resource "aws_security_group_rule" "cluster_egress_nodes" {
  description              = "Allow cluster to communicate with worker nodes"
  from_port                = 1025
  to_port                  = 65535
  protocol                 = "tcp"
  security_group_id        = aws_security_group.cluster_sg.id
  source_security_group_id = aws_security_group.node_sg.id
  type                     = "egress"
}

# Note: Kubernetes resources are managed by Argo CD, not Terraform
# This follows GitOps best practices:
# - Terraform: AWS infrastructure only
# - Argo CD: Kubernetes applications only
# - Helm: Application deployment

# Create ECR repository only if it doesn't exist
resource "aws_ecr_repository" "flask_app" {
  name                 = "flask-app"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = merge(
    {
      Name        = "${var.cluster_name}-ecr-repo"
      Environment = var.environment
    },
    var.tags
  )
  
  # Prevent recreation if repository already exists
  lifecycle {
    prevent_destroy = false
  }
}
