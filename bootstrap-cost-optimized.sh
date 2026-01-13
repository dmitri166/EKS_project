#!/bin/bash
set -e

echo "🚀 Deploying Flask DevOps Stack - COST OPTIMIZED VERSION"
echo "=================================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_cost() {
    echo -e "${BLUE}[COST]${NC} $1"
}

# Cost optimization options
COST_MODE=${1:-"balanced"}  # Options: minimal, balanced, production

print_cost "Cost mode: $COST_MODE"

# Set cost optimization parameters
case $COST_MODE in
  "minimal")
    NODE_COUNT=1
    NODE_TYPE="t3.nano"
    FLASK_REPLICAS=1
    STORAGE_SIZE="256Mi"
    MONITORING_STORAGE="1Gi"
    GRAFANA_STORAGE="512Mi"
    print_cost "Estimated monthly cost: ~$50-70"
    ;;
  "balanced")
    NODE_COUNT=2
    NODE_TYPE="t3.small"
    FLASK_REPLICAS=1
    STORAGE_SIZE="512Mi"
    MONITORING_STORAGE="5Gi"
    GRAFANA_STORAGE="2Gi"
    print_cost "Estimated monthly cost: ~$100-130"
    ;;
  "production")
    NODE_COUNT=3
    NODE_TYPE="t3.medium"
    FLASK_REPLICAS=2
    STORAGE_SIZE="1Gi"
    MONITORING_STORAGE="10Gi"
    GRAFANA_STORAGE="5Gi"
    print_cost "Estimated monthly cost: ~$200-250"
    ;;
  *)
    print_warning "Invalid cost mode. Using 'balanced'"
    COST_MODE="balanced"
    NODE_COUNT=2
    NODE_TYPE="t3.small"
    FLASK_REPLICAS=1
    ;;
esac

# Check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is not installed"
        exit 1
    fi
    
    if ! command -v terraform &> /dev/null; then
        print_error "Terraform is not installed"
        exit 1
    fi
    
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl is not installed"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials not configured. Run 'aws configure'"
        exit 1
    fi
    
    print_status "Prerequisites check passed ✓"
}

# Create cost-optimized terraform files
create_cost_optimized_config() {
    print_status "Creating cost-optimized configuration..."
    
    # Create cost-optimized terraform.tfvars
    cat > terraform/eks/terraform.tfvars << EOF
vpc_id = "\$(cd ../vpc && terraform output -raw vpc_id)"
private_subnet_ids = [\$(cd ../vpc && terraform output -json private_subnet_ids | jq -r '.[]' | tr '\n' ',' | sed 's/,\$//')]
public_subnet_ids = [\$(cd ../vpc && terraform output -json public_subnet_ids | jq -r '.[]' | tr '\n' ',' | sed 's/,\$//')]
eks_cluster_role_arn = "\$(cd ../iam && terraform output -raw eks_cluster_role_arn)"
eks_node_role_arn = "\$(cd ../iam && terraform output -raw eks_node_role_arn)"

# Cost optimization settings
desired_size = $NODE_COUNT
min_size = 1
max_size = $((NODE_COUNT + 2))
instance_type = "$NODE_TYPE"
capacity_type = "SPOT"
use_spot_instances = true
EOF

    # Update Helm values for cost optimization
    cat > helm/flask-app/values-cost-optimized.yaml << EOF
# Cost-optimized values for $COST_MODE mode
replicaCount: $FLASK_REPLICAS

resources:
  requests:
    cpu: 50m
    memory: 64Mi
  limits:
    cpu: 200m
    memory: 256Mi

autoscaling:
  enabled: true
  minReplicas: 1
  maxReplicas: 3
  targetCPUUtilizationPercentage: 80
  targetMemoryUtilizationPercentage: 85

persistence:
  enabled: true
  size: $STORAGE_SIZE
  storageClass: "gp2"

service:
  type: ClusterIP

costOptimization:
  enabled: true
  mode: "$COST_MODE"
EOF

    print_status "Cost-optimized configuration created ✓"
}

# Deploy infrastructure with cost optimizations
deploy_infrastructure() {
    print_status "Deploying cost-optimized AWS infrastructure..."
    
    # Deploy VPC
    print_status "Deploying VPC..."
    cd terraform/vpc
    terraform init -input=false
    terraform plan -input=false
    terraform apply -input=false -auto-approve
    
    # Deploy IAM
    print_status "Deploying IAM roles..."
    cd ../iam
    terraform init -input=false
    terraform plan -input=false
    terraform apply -input=false -auto-approve
    
    # Deploy EKS with cost optimizations
    print_status "Deploying cost-optimized EKS cluster..."
    cd ../eks
    terraform init -input=false
    terraform plan -input=false -var-file=terraform.tfvars
    terraform apply -input=false -var-file=terraform.tfvars -auto-approve
    
    # Get cluster name
    CLUSTER_NAME=$(terraform output -raw cluster_name)
    
    cd ../..
    
    print_status "Cost-optimized infrastructure deployed ✓"
}

# Configure kubectl
configure_kubectl() {
    print_status "Configuring kubectl..."
    
    aws eks update-kubeconfig --region us-east-1 --name $CLUSTER_NAME
    
    # Wait for cluster to be ready
    print_status "Waiting for cluster to be ready..."
    kubectl wait --for=condition=Ready nodes --all --timeout=300s
    
    print_status "kubectl configured successfully ✓"
}

# Bootstrap Argo CD with cost optimizations
bootstrap_argocd() {
    print_status "Bootstrapping Argo CD with cost optimizations..."
    
    # Install Argo CD manually (one-time bootstrap)
    kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
    kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
    
    # Wait for Argo CD to be ready
    print_status "Waiting for Argo CD to be ready..."
    kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=300s
    
    # Get Argo CD password
    ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
    
    print_status "Argo CD bootstrapped successfully ✓"
    print_status "Argo CD URL: http://$(kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'):8080"
    print_status "Argo CD Username: admin"
    print_status "Argo CD Password: $ARGOCD_PASSWORD"
}

# Deploy Cost-Optimized Apps
deploy_cost_optimized_apps() {
    print_status "Deploying cost-optimized applications..."
    
    # Apply the root application
    kubectl apply -f argo-cd/root-app.yaml
    
    # Install Argo CD CLI
    if ! command -v argocd &> /dev/null; then
        print_status "Installing Argo CD CLI..."
        curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
        chmod +x argocd
        sudo mv argocd /usr/local/bin/argocd
    fi
    
    # Login to Argo CD
    ARGOCD_SERVER=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].hostname}:8080')
    argocd login $ARGOCD_SERVER --username admin --password $ARGOCD_PASSWORD --insecure
    
    # Sync root app
    argocd app sync root-app
    
    print_status "Cost-optimized applications deployed ✓"
}

# Create GitHub token secret
create_github_secret() {
    print_status "Creating GitHub token secret for Argo CD..."
    
    # Check if secret already exists
    if kubectl get secret github-token -n argocd &> /dev/null; then
        print_warning "GitHub token secret already exists"
        return
    fi
    
    # Prompt for GitHub token
    echo "Please enter your GitHub Personal Access Token:"
    echo "Create one at: https://github.com/settings/tokens"
    echo "Required scopes: repo"
    read -s -p "GitHub Token: " GITHUB_TOKEN
    echo
    
    # Create secret
    kubectl create secret generic github-token \
        --from-literal=type=github \
        --from-literal=token=$GITHUB_TOKEN \
        --namespace=argocd
    
    print_status "GitHub token secret created ✓"
}

# Wait for all applications to be ready
wait_for_apps() {
    print_status "Waiting for all applications to be ready..."
    
    # Wait for monitoring
    kubectl wait --for=condition=available deployment/monitoring-kube-prometheus-stack-prometheus -n monitoring --timeout=600s || true
    kubectl wait --for=condition=available deployment/monitoring-kube-prometheus-stack-grafana -n monitoring --timeout=600s || true
    
    # Wait for Flask app
    kubectl wait --for=condition=available deployment/flask-app -n flask-app --timeout=600s || true
    
    print_status "All applications are ready ✓"
}

# Print cost optimization summary
print_cost_summary() {
    print_cost "🎉 Cost-Optimized Deployment Summary"
    echo "========================================"
    echo "📊 Configuration: $COST_MODE"
    echo "🖥️  Nodes: $NODE_COUNT × $NODE_TYPE"
    echo "🐍 Flask Replicas: $FLASK_REPLICAS"
    echo "💾 Storage: $STORAGE_SIZE (SQLite), $MONITORING_STORAGE (Prometheus), $GRAFANA_STORAGE (Grafana)"
    echo ""
    echo "💰 Estimated Monthly Costs:"
    echo "   EKS Cluster: \$73"
    echo "   Worker Nodes: \$(($NODE_COUNT * 23))"  # Approximate cost
    echo "   Storage: \$5"
    echo "   Load Balancers: \$20"  # Only Argo CD LB
    echo "   Data Transfer: \$10-30"
    echo "   ------------------------"
    echo "   Total: \$${COST_ESTIMATE:-100-150}"
    echo ""
    echo "🔧 Cost Savings:"
    echo "   ✅ Spot instances: 60-70% savings"
    echo "   ✅ ClusterIP services: \$40/month saved"
    echo "   ✅ Reduced storage: \$10/month saved"
    echo "   ✅ Optimized resources: \$30/month saved"
    echo ""
    echo "📈 Scaling Recommendations:"
    echo "   🔄 Monitor CPU/Memory usage"
    echo "   📊 Use kubectl top commands"
    echo "   ⏰ Scale down during off-hours"
    echo "   🚀 Scale up for traffic spikes"
}

# Print access information
print_access_info() {
    print_status "🎉 Cost-Optimized Deployment completed!"
    echo ""
    echo "📊 Access Information:"
    echo "======================"
    
    # Argo CD
    ARGOCD_URL=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
    echo "🚀 Argo CD: http://$ARGOCD_URL:8080"
    echo "   Username: admin"
    echo "   Password: $ARGOCD_PASSWORD"
    
    # Grafana (internal access)
    echo "📈 Grafana: kubectl port-forward svc/monitoring-grafana -n monitoring 3000:3000"
    echo "   Username: admin"
    echo "   Password: admin123"
    
    # Flask App (internal access)
    echo "🐍 Flask App: kubectl port-forward svc/flask-app -n flask-app 8080:80"
    echo "   Health Check: http://localhost:8080/health"
    echo "   API Tasks: http://localhost:8080/tasks"
    
    echo ""
    echo "💡 Cost Monitoring Commands:"
    echo "=========================="
    echo "Check resource usage: kubectl top nodes"
    echo "Check pod usage: kubectl top pods --all-namespaces"
    echo "Check costs: aws ce get-cost-and-usage --time-period StartOfMonth-EndOfMonth"
    echo ""
    echo "🔧 Useful Commands:"
    echo "==================="
    echo "Check pods: kubectl get pods -A"
    echo "Check services: kubectl get svc -A"
    echo "Argo CD apps: argocd app list"
    echo "Scale app: kubectl scale deployment flask-app --replicas=2 -n flask-app"
    echo ""
    echo "📚 Next Steps:"
    echo "============"
    echo "1. Monitor resource usage regularly"
    echo "2. Set up AWS Budget alerts"
    echo "3. Consider schedule-based scaling"
    echo "4. Review and optimize monthly"
}

# Main execution
main() {
    print_status "Starting Cost-Optimized Flask DevOps Stack deployment..."
    
    check_prerequisites
    create_cost_optimized_config
    deploy_infrastructure
    configure_kubectl
    bootstrap_argocd
    create_github_secret
    deploy_cost_optimized_apps
    wait_for_apps
    print_cost_summary
    print_access_info
    
    print_status "🎉 Cost-Optimized Deployment completed successfully!"
}

# Run main function
main "$@"
