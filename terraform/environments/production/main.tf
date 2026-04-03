terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket = "eks-project-terraform-state-025988852505"
    key    = "terraform.tfstate"
    region = "us-east-1"
    dynamodb_table = "terraform-locks"
    encrypt = true
  }
}

provider "aws" {
  region = var.aws_region
}

# VPC Module
module "vpc" {
  source = "../../modules/vpc"

  aws_region            = var.aws_region
  project_name          = var.project_name
  environment           = var.environment
  vpc_cidr              = var.vpc_cidr
  public_subnet_cidrs   = var.public_subnet_cidrs
  private_subnet_cidrs  = var.private_subnet_cidrs
  availability_zones    = var.availability_zones
  cluster_name          = var.cluster_name
  tags                  = var.tags
}

# IAM Module
module "iam" {
  source = "../../modules/iam"

  aws_region        = var.aws_region
  project_name      = var.project_name
  environment       = var.environment
  eks_cluster_name  = var.cluster_name
  tags              = var.tags
}

# EKS Module
module "eks" {
  source = "../../modules/eks"

  aws_region                = var.aws_region
  cluster_name              = var.cluster_name
  environment               = var.environment
  kubernetes_version        = var.kubernetes_version
  vpc_id                    = module.vpc.vpc_id
  private_subnet_ids        = module.vpc.private_subnet_ids
  public_subnet_ids         = module.vpc.public_subnet_ids
  eks_cluster_role_arn      = module.iam.eks_cluster_role_arn
  eks_node_role_arn         = module.iam.eks_node_role_arn
  endpoint_private_access   = var.endpoint_private_access
  endpoint_public_access    = var.endpoint_public_access
  public_access_cidrs       = var.public_access_cidrs
  enabled_cluster_log_types = var.enabled_cluster_log_types
  desired_size              = var.desired_size
  max_size                  = var.max_size
  min_size                  = var.min_size
  instance_type             = var.instance_type
  ssh_key_name              = var.ssh_key_name
  cluster_ingress_cidrs     = var.cluster_ingress_cidrs
  tags                      = var.tags

  depends_on = [module.vpc, module.iam]
}

# OIDC Module
module "oidc" {
  source = "../../modules/oidc"

  project_name = var.project_name
  github_repo  = "dmitri166/EKS_project"
  tags         = var.tags
}

# Karpenter Module
module "karpenter" {
  source = "../../modules/karpenter"

  project_name      = var.project_name
  cluster_name      = module.eks.cluster_name
  cluster_arn       = module.eks.cluster_arn
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
  tags              = var.tags

  depends_on = [module.eks]
}

# RDS Module
module "rds" {
  source = "../../modules/rds"

  project_name       = var.project_name
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  eks_node_sg_id     = module.eks.cluster_security_group_id # Using cluster SG for now, node SG is also a candidate
  db_password        = var.db_password
  tags               = var.tags

  depends_on = [module.vpc, module.eks]
}

# ESO Module
module "eso" {
  source = "../../modules/eso"

  project_name      = var.project_name
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
  tags              = var.tags

  depends_on = [module.eks]
}
