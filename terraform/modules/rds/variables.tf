variable "project_name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "eks_node_sg_id" {
  type = string
}

variable "db_name" {
  type    = string
  default = "todoapp"
}

variable "db_username" {
  type    = string
  default = "postgres"
}

variable "tags" {
  type    = map(string)
  default = {}
}
