terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }
  }

  backend "s3" {
    bucket         = "eks-project-terraform-state-025988852505"
    key            = "terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region
}

# VPC Module
module "vpc" {
  source = "../../modules/vpc"

  aws_region           = var.aws_region
  project_name         = var.project_name
  environment          = var.environment
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  availability_zones   = var.availability_zones
  cluster_name         = var.cluster_name
  tags                 = var.tags
}

# IAM Module
module "iam" {
  source = "../../modules/iam"

  aws_region       = var.aws_region
  project_name     = var.project_name
  environment      = var.environment
  eks_cluster_name = var.cluster_name
  tags             = var.tags
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

# Kubernetes and Helm providers for EKS
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.aws_region]
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.aws_region]
    }
  }
}

# OIDC Module
module "oidc" {
  source = "../../modules/oidc"

  project_name = var.project_name
  github_repo  = "dmitri166/EKS_project"
  aws_region   = var.aws_region
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
  eks_node_sg_id     = module.eks.node_security_group_id
  tags               = var.tags

  depends_on = [module.vpc, module.eks]
}


# Backstage RDS Module
module "rds_backstage" {
  source = "../../modules/rds"

  project_name       = "${var.project_name}-backstage"
  db_name            = "backstage"
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  eks_node_sg_id     = module.eks.node_security_group_id
  tags               = var.tags

  depends_on = [module.vpc, module.eks]
}

# oauth2-proxy Secrets (stored in AWS Secrets Manager)
resource "random_password" "oauth2_proxy_cookie_secret" {
  length  = 32
  special = false
}

resource "aws_secretsmanager_secret" "oauth2_proxy_client_id" {
  name        = "oauth2-proxy-github-client-id"
  description = "GitHub OAuth Client ID for oauth2-proxy"
  force_overwrite_replica_secret = true
  recovery_window_in_days = 0
  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "oauth2_proxy_client_id" {
  count         = var.github_oauth_client_id != "" ? 1 : 0
  secret_id     = aws_secretsmanager_secret.oauth2_proxy_client_id.id
  secret_string = var.github_oauth_client_id
}

resource "aws_secretsmanager_secret" "oauth2_proxy_client_secret" {
  name        = "oauth2-proxy-github-client-secret"
  description = "GitHub OAuth Client Secret for oauth2-proxy"
  force_overwrite_replica_secret = true
  recovery_window_in_days = 0
  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "oauth2_proxy_client_secret" {
  count         = var.github_oauth_client_secret != "" ? 1 : 0
  secret_id     = aws_secretsmanager_secret.oauth2_proxy_client_secret.id
  secret_string = var.github_oauth_client_secret
}

resource "aws_secretsmanager_secret" "oauth2_proxy_cookie_secret" {
  name        = "oauth2-proxy-cookie-secret"
  description = "oauth2-proxy cookie secret (base64)"
  force_overwrite_replica_secret = true
  recovery_window_in_days = 0
  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "oauth2_proxy_cookie_secret" {
  secret_id     = aws_secretsmanager_secret.oauth2_proxy_cookie_secret.id
  secret_string = base64encode(random_password.oauth2_proxy_cookie_secret.result)
}

# Grafana admin password (Secrets Manager)
resource "random_password" "grafana_admin_password" {
  length  = 16
  special = true
}

resource "aws_secretsmanager_secret" "grafana_admin_password" {
  name        = "${var.project_name}-grafana-admin-password"
  description = "Grafana admin password"
  force_overwrite_replica_secret = true
  recovery_window_in_days = 0
  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "grafana_admin_password" {
  secret_id     = aws_secretsmanager_secret.grafana_admin_password.id
  secret_string = random_password.grafana_admin_password.result
}


# ESO Module

# Configure AWS VPC CNI for higher pod density on small nodes
resource "null_resource" "configure_aws_cni" {
  depends_on = [module.eks]

  provisioner "local-exec" {
    command = <<-EOT
      aws eks update-kubeconfig --region ${var.aws_region} --name ${var.cluster_name}
      kubectl wait --for=condition=Ready pod -l k8s-app=aws-node -n kube-system --timeout=300s
      kubectl set env daemonset aws-node -n kube-system ENABLE_PREFIX_DELEGATION=true WARM_PREFIX_TARGET=1
      kubectl rollout restart daemonset aws-node -n kube-system
    EOT
  }
}

module "eso" {
  source = "../../modules/eso"

  project_name      = var.project_name
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
  tags              = var.tags

  depends_on = [module.eks]
}

# ACM Certificate Module
# module "acm" {
#   source = "../../modules/acm"
#
#   project_name    = var.project_name
#   environment     = var.environment
#   domain_name     = var.domain_name
#   route53_zone_id = var.route53_zone_id
#
#   depends_on = [module.vpc]
# }


# ArgoCD Module
module "argocd" {
  source = "../../modules/argocd"

  aws_region   = var.aws_region
  cluster_name = var.cluster_name
  enable_argocd = var.enable_argocd

  depends_on = [module.eks, null_resource.configure_aws_cni]
}
