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
  metadata {
    name = "argocd"
    labels = {
      name = "argocd"
    }
  }
}


# Bootstrap ArgoCD from repo manifests (CRDs + core components)
resource "null_resource" "bootstrap_argocd" {
  depends_on = [kubernetes_namespace_v1.argocd]

  provisioner "local-exec" {
    command = <<-EOT
      aws eks update-kubeconfig --region ${var.aws_region} --name ${var.cluster_name}
      kubectl apply -n argocd -f ${path.module}/../../../argo-cd/manifests/install.yaml
    EOT
  }
}

# Deploy root application that manages all apps (including ArgoCD self-management)
resource "kubernetes_manifest" "argocd_root_app" {
  manifest = yamldecode(file("${path.module}/../../../argo-cd/root-app.yaml"))

  depends_on = [null_resource.wait_for_argocd]
}

# Wait for ArgoCD to be ready before deploying apps
resource "null_resource" "wait_for_argocd" {
  depends_on = [null_resource.bootstrap_argocd]

  provisioner "local-exec" {
    command = <<-EOT
      aws eks update-kubeconfig --region ${var.aws_region} --name ${var.cluster_name}
      kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd
    EOT
  }
}
