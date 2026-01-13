output "eks_cluster_role_arn" {
  description = "ARN of the EKS cluster role"
  value       = aws_iam_role.eks_cluster_role.arn
}

output "eks_node_role_arn" {
  description = "ARN of the EKS node role"
  value       = aws_iam_role.eks_node_role.arn
}

output "argocd_role_arn" {
  description = "ARN of the Argo CD role"
  value       = aws_iam_role.argocd_role.arn
}

output "eks_cluster_role_name" {
  description = "Name of the EKS cluster role"
  value       = aws_iam_role.eks_cluster_role.name
}

output "eks_node_role_name" {
  description = "Name of the EKS node role"
  value       = aws_iam_role.eks_node_role.name
}

output "argocd_role_name" {
  description = "Name of the Argo CD role"
  value       = aws_iam_role.argocd_role.name
}
