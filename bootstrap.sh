#!/bin/bash
set -e

echo "🚀 Deploying Flask DevOps Stack - Hybrid Approach"
echo "=================================================="

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
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

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
    
    if ! command -v helm &> /dev/null; then
        print_error "Helm is not installed"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials not configured. Run 'aws configure'"
        exit 1
    fi
    
    print_status "Prerequisites check passed ✓"
}

# Deploy infrastructure with Terraform
deploy_infrastructure() {
    print_status "Deploying AWS infrastructure..."
    
    # Deploy VPC
    print_status "Deploying VPC..."
    cd terraform/vpc
    terraform init -input=false
    terraform plan -input=false
    terraform apply -input=false -auto-approve
    
    # Get VPC outputs
    VPC_ID=$(terraform output -raw vpc_id)
    PRIVATE_SUBNET_IDS=$(terraform output -json private_subnet_ids | jq -r '.[]' | tr '\n' ',' | sed 's/,$//')
    PUBLIC_SUBNET_IDS=$(terraform output -json public_subnet_ids | jq -r '.[]' | tr '\n' ',' | sed 's/,$//')
    
    # Deploy IAM
    print_status "Deploying IAM roles..."
    cd ../iam
    terraform init -input=false
    terraform plan -input=false
    terraform apply -input=false -auto-approve
    
    # Get IAM outputs
    EKS_CLUSTER_ROLE_ARN=$(terraform output -raw eks_cluster_role_arn)
    EKS_NODE_ROLE_ARN=$(terraform output -raw eks_node_role_arn)
    
    # Deploy EKS
    print_status "Deploying EKS cluster..."
    cd ../eks
    
    # Create terraform.tfvars
    cat > terraform.tfvars << EOF
vpc_id = "$VPC_ID"
private_subnet_ids = [$(echo $PRIVATE_SUBNET_IDS | sed 's/,/, /g')]
public_subnet_ids = [$(echo $PUBLIC_SUBNET_IDS | sed 's/,/, /g')]
eks_cluster_role_arn = "$EKS_CLUSTER_ROLE_ARN"
eks_node_role_arn = "$EKS_NODE_ROLE_ARN"
EOF
    
    terraform init -input=false
    terraform plan -input=false -var-file=terraform.tfvars
    terraform apply -input=false -var-file=terraform.tfvars -auto-approve
    
    # Get cluster name
    CLUSTER_NAME=$(terraform output -raw cluster_name)
    
    cd ../..
    
    print_status "Infrastructure deployed successfully ✓"
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

# Bootstrap Argo CD
bootstrap_argocd() {
    print_status "Bootstrapping Argo CD..."
    
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

# Deploy Root App
deploy_root_app() {
    print_status "Deploying Root App (App of Apps)..."
    
    # Apply the root application
    kubectl apply -f argo-cd/root-app.yaml
    
    # Wait for root app to sync
    print_status "Waiting for Root App to sync..."
    sleep 30
    
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
    
    print_status "Root App deployed successfully ✓"
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
    kubectl wait --for=condition=available deployment/prometheus-kube-prometheus-stack-prometheus -n monitoring --timeout=600s || true
    kubectl wait --for=condition=available deployment/prometheus-kube-prometheus-stack-grafana -n monitoring --timeout=600s || true
    
    # Wait for Flask app
    kubectl wait --for=condition=available deployment/flask-app -n flask-app --timeout=600s || true
    
    print_status "All applications are ready ✓"
}

# Print access information
print_access_info() {
    print_status "🎉 Deployment completed successfully!"
    echo ""
    echo "📊 Access Information:"
    echo "======================"
    
    # Argo CD
    ARGOCD_URL=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
    echo "🚀 Argo CD: http://$ARGOCD_URL:8080"
    echo "   Username: admin"
    echo "   Password: $ARGOCD_PASSWORD"
    
    # Grafana
    GRAFANA_URL=$(kubectl get svc monitoring-grafana -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "pending")
    if [ "$GRAFANA_URL" != "pending" ]; then
        echo "📈 Grafana: http://$GRAFANA_URL:3000"
        echo "   Username: admin"
        echo "   Password: admin123"
    fi
    
    # Flask App
    FLASK_URL=$(kubectl get svc flask-app -n flask-app -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "pending")
    if [ "$FLASK_URL" != "pending" ]; then
        echo "🐍 Flask App: http://$FLASK_URL:80"
        echo "   Health Check: http://$FLASK_URL/health"
        echo "   API Tasks: http://$FLASK_URL/tasks"
    fi
    
    echo ""
    echo "🔧 Useful Commands:"
    echo "==================="
    echo "Check pods: kubectl get pods -A"
    echo "Check services: kubectl get svc -A"
    echo "Argo CD apps: argocd app list"
    echo "Sync app: argocd app sync <app-name>"
    echo ""
    echo "📚 Next Steps:"
    echo "============"
    echo "1. Access Argo CD and verify all apps are synced"
    echo "2. Access Grafana and import dashboards"
    echo "3. Test the Flask API endpoints"
    echo "4. Push code changes to trigger automatic deployments"
}

# Main execution
main() {
    print_status "Starting Flask DevOps Stack deployment..."
    
    check_prerequisites
    deploy_infrastructure
    configure_kubectl
    bootstrap_argocd
    create_github_secret
    deploy_root_app
    wait_for_apps
    print_access_info
    
    print_status "🎉 Deployment completed successfully!"
}

# Run main function
main "$@"
