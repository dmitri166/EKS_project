# VPC Outputs
output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = module.vpc.private_subnet_ids
}

# IAM Outputs
output "eks_cluster_role_arn" {
  description = "ARN of the EKS cluster role"
  value       = module.iam.eks_cluster_role_arn
}

output "eks_node_role_arn" {
  description = "ARN of the EKS node role"
  value       = module.iam.eks_node_role_arn
}

# EKS Outputs
output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = module.eks.cluster_endpoint
}

output "cluster_arn" {
  description = "EKS cluster ARN"
  value       = module.eks.cluster_arn
}

output "ecr_repository_url" {
  description = "ECR repository URL"
  value       = module.eks.ecr_repository_url
}

# Security Groups Outputs
output "alb_security_group_id" {
  description = "Security group ID for ALB"
  value       = module.security_groups.alb_security_group_id
}

output "eks_nodes_security_group_id" {
  description = "Security group ID for EKS nodes"
  value       = module.security_groups.eks_nodes_security_group_id
}

# ACM Certificate Output
# output "acm_certificate_arn" {
#   description = "ACM certificate ARN"
#   value       = module.acm.certificate_arn
# }
