variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name (e.g., username/repo)"
  type        = string
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
