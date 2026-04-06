terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }
  }
}

# Create ArgoCD namespace
resource "kubernetes_namespace_v1" "argocd" {
  count = var.enable_argocd ? 1 : 0
  metadata {
    name = "argocd"
    labels = {
      name = "argocd"
    }
  }
}


# Bootstrap ArgoCD from repo manifests (CRDs + core components)
resource "null_resource" "bootstrap_argocd" {
  count = var.enable_argocd ? 1 : 0
  depends_on = [kubernetes_namespace_v1.argocd[0]]

  provisioner "local-exec" {
    command = <<-EOT
      aws eks update-kubeconfig --region ${var.aws_region} --name ${var.cluster_name}
      kubectl apply -n argocd -f ${path.module}/../../../argo-cd/manifests/install.yaml
    EOT
  }
}

# Deploy root application that manages all apps (including ArgoCD self-management)
resource "kubernetes_manifest" "argocd_root_app" {
  count = var.enable_argocd ? 1 : 0
  manifest = yamldecode(file("${path.module}/../../../argo-cd/root-app.yaml"))

  depends_on = [null_resource.wait_for_argocd[0]]
}


# Clear root-app finalizer on destroy to avoid Terraform timeout
resource "null_resource" "clear_root_app_finalizer" {
  count = var.enable_argocd ? 1 : 0
  depends_on = [kubernetes_manifest.argocd_root_app[0]]

  triggers = {
    aws_region   = var.aws_region
    cluster_name = var.cluster_name
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      aws eks update-kubeconfig --region ${self.triggers.aws_region} --name ${self.triggers.cluster_name}
      kubectl -n argocd patch application root-app --type=merge -p '{"metadata":{"finalizers":[]}}'
    EOT
  }
}

# Wait for ArgoCD to be ready before deploying apps
resource "null_resource" "wait_for_argocd" {
  count = var.enable_argocd ? 1 : 0
  depends_on = [null_resource.bootstrap_argocd[0]]

  provisioner "local-exec" {
    command = <<-EOT
      aws eks update-kubeconfig --region ${var.aws_region} --name ${var.cluster_name}
      kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd
    EOT
  }
}
