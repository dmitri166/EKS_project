variable "project_name" {
  type = string
}

variable "oidc_provider_arn" {
  type = string
}

variable "oidc_provider_url" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "controller_version" {
  type        = string
  description = "The version of the AWS Load Balancer Controller to use for the IAM policy"
  default     = "v2.7.2"
}
