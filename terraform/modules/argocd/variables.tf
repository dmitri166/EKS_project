variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "flask-devops-cluster"
}


variable "enable_argocd" {
  description = "Whether to create Argo CD Kubernetes resources (set true after kubeconfig is available)"
  type        = bool
  default     = false
}
