variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Environment name (e.g., production, staging)"
  type        = string
  default     = "production"
}

variable "vpc_id" {
  description = "VPC ID where security groups will be created"
  type        = string
}

variable "allowed_cidrs" {
  description = "List of CIDR blocks allowed to access the ALB"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}
