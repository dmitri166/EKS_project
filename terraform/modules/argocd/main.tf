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
  version    = "v2.8.3"
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

# Create ArgoCD application to manage itself
resource "kubectl_manifest" "argocd_self_management" {
  yaml_body = <<-EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: argocd
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://github.com/dmitri166/EKS_project.git
    targetRevision: master
    path: argo-cd/manifests
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - PrunePropagationPolicy=foreground
      - PruneLast=true
EOF

  depends_on = [helm_release.argocd]
}

# Wait for ArgoCD to be ready
resource "null_resource" "wait_for_argocd" {
  depends_on = [kubectl_manifest.argocd_self_management]

  provisioner "local-exec" {
    command = <<-EOT
      aws eks update-kubeconfig --region us-east-1 --name flask-devops-cluster
      kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd
    EOT
  }
}
