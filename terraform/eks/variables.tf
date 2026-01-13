variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "flask-devops-cluster"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "kubernetes_version" {
  description = "Kubernetes version for EKS cluster"
  type        = string
  default     = "1.28"
}

variable "vpc_id" {
  description = "VPC ID for the cluster"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs"
  type        = list(string)
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs"
  type        = list(string)
}

variable "eks_cluster_role_arn" {
  description = "ARN of the EKS cluster role"
  type        = string
}

variable "eks_node_role_arn" {
  description = "ARN of the EKS node role"
  type        = string
}

variable "endpoint_private_access" {
  description = "Whether the Amazon EKS private API server endpoint is enabled"
  type        = bool
  default     = true
}

variable "endpoint_public_access" {
  description = "Whether the Amazon EKS public API server endpoint is enabled"
  type        = bool
  default     = true
}

variable "public_access_cidrs" {
  description = "CIDR blocks that can access the Amazon EKS public API server endpoint"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "enabled_cluster_log_types" {
  description = "List of the desired control plane logging to enable"
  type        = list(string)
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
}

variable "desired_size" {
  description = "Desired number of worker nodes"
  type        = number
  default     = 2  # Reduced from 3 for cost savings
}

variable "min_size" {
  description = "Minimum number of worker nodes"
  type        = number
  default     = 1  # Reduced from 2 for cost savings
}

variable "max_size" {
  description = "Maximum number of worker nodes"
  type        = number
  default     = 4  # Reduced from 6 for cost savings
}

variable "instance_type" {
  description = "EC2 instance type for worker nodes"
  type        = string
  default     = "t3.small"  # Reduced from t3.medium for cost savings
}

variable "capacity_type" {
  description = "Capacity type for node group (ON_DEMAND or SPOT)"
  type        = string
  default     = "SPOT"  # Added for cost savings
}

variable "use_spot_instances" {
  description = "Whether to use spot instances for cost savings"
  type        = bool
  default     = true
}

variable "ssh_key_name" {
  description = "SSH key name for worker nodes"
  type        = string
  default     = ""
}

variable "cluster_ingress_cidrs" {
  description = "CIDR blocks that can access the cluster API"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default = {
    Terraform = "true"
    Project   = "flask-devops"
  }
}
