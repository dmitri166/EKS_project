terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }
    kubectl = {
      source  = "alekc/kubectl"
      version = "~> 2.0"
    }
  }
}

# Create ArgoCD namespace
resource "kubernetes_namespace_v1" "argocd" {
  metadata {
    name = "argocd"
    labels = {
      name = "argocd"
    }
  }
}

# Deploy ArgoCD via Helm (bootstrap only)
resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "5.46.2"
  namespace  = kubernetes_namespace_v1.argocd.metadata[0].name

  set {
    name  = "crds.install"
    value = "true"
  }

  set {
    name  = "server.insecure"
    value = "true"
  }

  depends_on = [kubernetes_namespace_v1.argocd]
}

# Deploy root application that manages all apps (including ArgoCD self-management)
resource "kubectl_manifest" "argocd_root_app" {
  yaml_body = file("${path.module}/../../../argo-cd/root-app.yaml")

  depends_on = [helm_release.argocd]
}

# Wait for ArgoCD to be ready before deploying apps
resource "null_resource" "wait_for_argocd" {
  depends_on = [kubectl_manifest.argocd_root_app]

  provisioner "local-exec" {
    command = <<-EOT
      aws eks update-kubeconfig --region ${var.aws_region} --name ${var.cluster_name}
      kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd
    EOT
  }
}
