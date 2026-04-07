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

  depends_on = [null_resource.cleanup_stuck_namespace[0]]
}

# Clean up stuck argocd namespace from a previous failed destroy before creating it
resource "null_resource" "cleanup_stuck_namespace" {
  count = var.enable_argocd ? 1 : 0

  triggers = {
    aws_region   = var.aws_region
    cluster_name = var.cluster_name
  }

  provisioner "local-exec" {
    command = <<-EOT
      aws eks update-kubeconfig --region ${var.aws_region} --name ${var.cluster_name}

      # If namespace is stuck in Terminating, force-finalize it
      STATUS=$(kubectl get namespace argocd -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
      if [ "$STATUS" = "Terminating" ]; then
        echo "Namespace argocd is stuck in Terminating - force cleaning..."
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
resource "null_resource" "apply_root_app" {
  count = var.enable_argocd ? 1 : 0
  depends_on = [null_resource.wait_for_argocd[0]]

  provisioner "local-exec" {
    command = <<-EOT
      aws eks update-kubeconfig --region ${var.aws_region} --name ${var.cluster_name}
      kubectl apply -n argocd -f ${path.module}/../../../argo-cd/root-app.yaml
    EOT
  }
}


# Clear root-app finalizer on destroy to avoid Terraform timeout
resource "null_resource" "clear_root_app_finalizer" {
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

      # Remove finalizers from ALL ArgoCD applications
      for app in $(kubectl get applications -n argocd -o name 2>/dev/null); do
        kubectl patch $app -n argocd --type=merge -p '{"metadata":{"finalizers":[]}}' 2>/dev/null || true
      done

      # Delete all ArgoCD applications
      kubectl delete applications --all -n argocd --timeout=60s 2>/dev/null || true

      # Remove finalizers from AppProjects
      for proj in $(kubectl get appprojects -n argocd -o name 2>/dev/null); do
        kubectl patch $proj -n argocd --type=merge -p '{"metadata":{"finalizers":[]}}' 2>/dev/null || true
      done

      # Force-remove any stuck resources in the namespace
      kubectl api-resources --verbs=list --namespaced -o name 2>/dev/null | \
        xargs -I{} kubectl get {} -n argocd --ignore-not-found -o name 2>/dev/null | \
        xargs -I{} kubectl patch {} -n argocd --type=merge -p '{"metadata":{"finalizers":[]}}' 2>/dev/null || true
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
