#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if kubectl is configured
if ! kubectl cluster-info &> /dev/null; then
    print_error "kubectl is not configured or cluster is not accessible"
    exit 1
fi

print_status "Starting ArgoCD and K8s setup..."

# Step 1: Create namespace
print_status "Creating argocd namespace..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

# Step 2: Add Helm repo
print_status "Adding ArgoCD Helm repository..."
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

# Step 3: Install ArgoCD
print_status "Installing ArgoCD..."
helm upgrade --install argocd argo/argo-cd \
  --namespace argocd \
  --create-namespace \
  --set crds.install=true \
  --wait \
  --timeout=10m

# Step 4: Wait for ArgoCD to be ready
print_status "Waiting for ArgoCD to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd

# Step 5: Deploy gp3 StorageClass
print_status "Deploying gp3 StorageClass..."
kubectl apply -f k8s/storage/gp3-sc.yaml

# Step 6: Delete gp2 StorageClass
print_status "Deleting gp2 StorageClass..."
kubectl delete storageclass gp2 --ignore-not-found=true

# Step 7: Verify StorageClass
print_status "Verifying StorageClass configuration..."
kubectl get storageclass

# Step 8: Deploy Karpenter
print_status "Deploying Karpenter..."
kubectl apply -f argo-cd/apps/karpenter.yaml

# Step 9: Wait for Karpenter namespace to be created
print_status "Waiting for Karpenter namespace to be created..."
for i in {1..10}; do
  if kubectl get namespace karpenter &>/dev/null; then
    print_status "Karpenter namespace found!"
    break
  fi
  if [ $i -eq 10 ]; then
    print_warning "Karpenter namespace not found after 5 minutes, creating manually..."
    kubectl create namespace karpenter
  fi
  print_status "Waiting for ArgoCD to create namespace... ($i/10)"
  sleep 30
done

# Step 10: Wait for Karpenter pods to be ready
print_status "Waiting for Karpenter to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/karpenter -n karpenter || print_warning "Karpenter deployment timeout"

# Step 11: Deploy all applications
print_status "Deploying all applications via ArgoCD..."
kubectl apply -f argo-cd/apps/

# Step 12: Wait for Flask app
print_status "Waiting for Flask app to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/flask-app -n flask-app

print_status "✅ Setup completed successfully!"
print_status "📊 Next steps:"
echo "   1. Get ALB DNS: kubectl get ingress -n flask-app"
echo "   2. Configure Cloudflare CNAME"
echo "   3. Test: curl https://eks-cluster-lab.duckdns.org/health"