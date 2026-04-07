terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
  }
}

# Clean up stuck argocd namespace from a previous failed destroy
resource "null_resource" "cleanup_stuck_namespace" {
  count = var.enable_argocd ? 1 : 0

  triggers = {
    aws_region   = var.aws_region
    cluster_name = var.cluster_name
  }

  provisioner "local-exec" {
    command = <<-EOT
      aws eks update-kubeconfig --region ${var.aws_region} --name ${var.cluster_name}
      STATUS=$(kubectl get namespace argocd -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
      if [ "$STATUS" = "Terminating" ]; then
        echo "Namespace argocd stuck in Terminating - force cleaning..."
        for app in $(kubectl get applications -n argocd -o name 2>/dev/null); do
          kubectl patch $app -n argocd --type=merge -p '{"metadata":{"finalizers":[]}}' 2>/dev/null || true
        done
        kubectl get namespace argocd -o json | \
          python3 -c "import sys,json; ns=json.load(sys.stdin); ns['spec']['finalizers']=[]; print(json.dumps(ns))" | \
          kubectl replace --raw "/api/v1/namespaces/argocd/finalize" -f - 2>/dev/null || true
        sleep 5
      fi
    EOT
  }
}

# Deploy ArgoCD via Helm - fully declarative with resource limits and anti-affinity
resource "helm_release" "argocd" {
  count = var.enable_argocd ? 1 : 0

  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "7.7.0"
  namespace        = "argocd"
  create_namespace = true
  timeout          = 600
  wait             = true

  depends_on = [null_resource.cleanup_stuck_namespace[0]]

  values = [<<-YAML
    global:
      # Spread ArgoCD pods across nodes
      affinity:
        podAntiAffinity: soft

    server:
      resources:
        requests:
          cpu: 50m
          memory: 128Mi
        limits:
          cpu: 300m
          memory: 256Mi

    repoServer:
      resources:
        requests:
          cpu: 50m
          memory: 128Mi
        limits:
          cpu: 300m
          memory: 256Mi

    applicationSet:
      resources:
        requests:
          cpu: 20m
          memory: 64Mi
        limits:
          cpu: 100m
          memory: 128Mi

    notifications:
      resources:
        requests:
          cpu: 10m
          memory: 32Mi
        limits:
          cpu: 100m
          memory: 64Mi

    dex:
      resources:
        requests:
          cpu: 10m
          memory: 32Mi
        limits:
          cpu: 100m
          memory: 64Mi

    redis:
      resources:
        requests:
          cpu: 10m
          memory: 32Mi
        limits:
          cpu: 100m
          memory: 64Mi

    controller:
      resources:
        requests:
          cpu: 50m
          memory: 128Mi
        limits:
          cpu: 300m
          memory: 256Mi

    configs:
      params:
        server.insecure: true
  YAML
  ]
}

# Deploy root application that manages all apps via GitOps
resource "null_resource" "apply_root_app" {
  count = var.enable_argocd ? 1 : 0

  depends_on = [helm_release.argocd[0]]

  triggers = {
    aws_region   = var.aws_region
    cluster_name = var.cluster_name
  }

  provisioner "local-exec" {
    command = <<-EOT
      aws eks update-kubeconfig --region ${var.aws_region} --name ${var.cluster_name}
      kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd

      # Register Karpenter OCI registry so ArgoCD can pull the chart
      argocd login --core
      argocd repo add public.ecr.aws/karpenter \
        --type helm \
        --name karpenter-ecr \
        --enable-oci \
        --insecure-skip-server-verification 2>/dev/null || true

      kubectl apply -n argocd -f ${path.module}/../../../argo-cd/root-app.yaml
    EOT
  }
}

# Clear all finalizers on destroy to avoid namespace stuck in Terminating
resource "null_resource" "clear_finalizers_on_destroy" {
  count = var.enable_argocd ? 1 : 0

  depends_on = [null_resource.apply_root_app[0]]

  triggers = {
    aws_region   = var.aws_region
    cluster_name = var.cluster_name
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      aws eks update-kubeconfig --region ${self.triggers.aws_region} --name ${self.triggers.cluster_name}

      for app in $(kubectl get applications -n argocd -o name 2>/dev/null); do
        kubectl patch $app -n argocd --type=merge -p '{"metadata":{"finalizers":[]}}' 2>/dev/null || true
      done

      kubectl delete applications --all -n argocd --timeout=60s 2>/dev/null || true

      for proj in $(kubectl get appprojects -n argocd -o name 2>/dev/null); do
        kubectl patch $proj -n argocd --type=merge -p '{"metadata":{"finalizers":[]}}' 2>/dev/null || true
      done
    EOT
  }
}
