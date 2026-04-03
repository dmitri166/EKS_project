# Provisioning Guide: EKS Production Infrastructure

This guide provides a comprehensive walkthrough for deploying the EKS cluster and its associated infrastructure (RDS, Redis, ArgoCD, etc.) from scratch.

## 1. Prerequisites & Required Information

Ensure you have the following information and tools ready:

### Tools
- **Terraform**: v1.5 or higher.
- **AWS CLI**: Authenticated with an IAM role that has `AdministratorAccess`.
- **kubectl**: For interacting with the cluster.
- **helm**: For managing Kubernetes applications.

### Information to Provide
Before starting, review the variables in `terraform/environments/production/variables.tf`. You should create a `terraform/environments/production/terraform.tfvars` file if you want to override defaults:

```hcl
project_name     = "flask-devops"
aws_region       = "us-east-1"
environment      = "production"
cluster_name     = "flask-devops-cluster"
github_repo      = "dmitri166/EKS_project" # Replace with your repo
```

> [!IMPORTANT]
> **Secrets Management**: Database and Redis passwords are now **automatically generated** by Terraform using `random_password` and stored in **AWS Secrets Manager**. You do **not** need to provide them manually.

---

## 2. Step-by-Step Provisioning

### Step 1: Bootstrap Terraform Backend
This step creates the S3 bucket and DynamoDB table for state locking.

```bash
cd terraform/bootstrap
terraform init
terraform apply -auto-approve
```

### Step 2: Provision Core Infrastructure
This deploys the VPC, EKS Cluster, IAM roles, RDS instance, and initial Secrets.

```bash
cd ../environments/production
terraform init
terraform apply -auto-approve
```

### Step 3: Configure kubectl
Connect to your new cluster:

```bash
aws eks update-kubeconfig --region us-east-1 --name flask-devops-cluster
```

### Step 4: Deploy Management Layer (ArgoCD & Apps)
ArgoCD will manage the deployment of all other components (ESO, ALB Controller, Flask App, etc.).

```bash
# Deploy ArgoCD
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for ArgoCD to be ready
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd

# Apply the Application Manifests
kubectl apply -f argo-cd/apps/
```

---

## 3. Verification: How to Check Everything

### A. Infrastructure Health
- **Nodes**: `kubectl get nodes` (Should see at least 1 node ready).
- **RDS**: Login to AWS Console -> RDS -> Databases. Check that `flask-devops-db` is `Available`.
- **Secrets**: Check AWS Secrets Manager for `flask-devops-db-password` and `flask-devops-redis-password`.

### B. Kubernetes Components
- **ESO (External Secrets)**:
  `kubectl get externalsecrets -A` (Status should be `SecretSynced`).
- **ALB Controller**:
  `kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller` (Should be `Running`).
- **App Health**:
  `kubectl get pods -n flask-app` (Should be `Running`).

### C. Application Functionality
Once the ALB is provisioned (check `kubectl get ingress -n flask-app`), verify the health endpoint:
```bash
# Get the ALB DNS name
ALB_URL=$(kubectl get ingress -n flask-app -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}')
curl http://$ALB_URL/health
```
**Expected Response**:
```json
{
  "status": "healthy",
  "database": "connected",
  "redis": "connected",
  "version": "2.0.0"
}
```

---

## 4. Troubleshooting
- **Secrets not syncing?** Check ESO logs: `kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets`.
- **ALB not creating?** Check ALB Controller logs: `kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller`.
- **App Pods failing?** Check `kubectl describe pod -n flask-app <pod-name>` for events.
