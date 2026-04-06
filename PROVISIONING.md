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

TF_VAR_github_oauth_client_id="<CLIENT_ID>" \
TF_VAR_github_oauth_client_secret="<CLIENT_SECRET>" \

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

### Step 4: Verify ArgoCD Self-Management
ArgoCD is now deployed via Terraform and manages itself automatically:

```bash
# Check ArgoCD is running
kubectl get pods -n argocd

# Verify ArgoCD is managing itself
kubectl get applications -n argocd | grep argocd

# Check all apps are being deployed
kubectl get applications -n argocd
```

### Step 5: Configure DuckDNS (HTTP-01)
Point your DuckDNS records to the Traefik load balancer:

```bash
# Get Traefik LB hostname
LB_HOST=$(kubectl -n traefik get svc traefik -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Resolve to an IP and set DuckDNS to that IP
LB_IP=$(dig +short $LB_HOST | head -n1)
echo "Set DuckDNS A records to: $LB_IP"

# Test API once DNS propagates
curl https://api.eks-cluster-lab.duckdns.org/health
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
- **Traefik**:
  `kubectl get pods -n traefik` (Should be `Running`).
- **Gateway API**:
  `kubectl get gateway -n traefik` and `kubectl get httproute -A` (Should be `Accepted`).
- **App Health**:
  `kubectl get pods -n flask-app` (Should be `Running`).

### C. Application Functionality
Once the Traefik load balancer is provisioned, verify the health endpoint:
```bash
curl https://api.eks-cluster-lab.duckdns.org/health
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
- **Traefik LB not creating?** Check Traefik logs: `kubectl -n traefik logs -l app.kubernetes.io/name=traefik`.
- **App Pods failing?** Check `kubectl describe pod -n flask-app <pod-name>` for events.

## Argo CD Bootstrap (Two-Phase Apply)

The Argo CD module uses a toggle `enable_argocd` to avoid Kubernetes provider errors on the very first apply (when kubeconfig is not yet available).

1. **Phase 1 – Infrastructure only**
   - Run Terraform with `enable_argocd = false` (default). This creates the VPC/EKS and all AWS infrastructure.
   - Update kubeconfig: `aws eks update-kubeconfig --region <region> --name <cluster>`

2. **Phase 2 – Argo CD bootstrap**
   - Re-run Terraform from `terraform/environments/production` with `enable_argocd = true`.
   - The module installs Argo CD CRDs/components first, waits for `argocd-server`, then applies the root app via `kubectl` (avoids CRD timing errors).

Example:
```
cd terraform/environments/production
terraform apply -auto-approve -var="enable_argocd=true"
```

## GitHub OAuth (oauth2-proxy)

Provide the GitHub OAuth credentials at apply time (do not commit them):

```
TF_VAR_github_oauth_client_id="<CLIENT_ID>" TF_VAR_github_oauth_client_secret="<CLIENT_SECRET>" terraform apply -auto-approve -var="enable_argocd=true"
```

## DNS + TLS (DuckDNS)

This setup uses cert-manager with HTTP-01 for per-host certs. A wildcard cert resource is included, but **wildcards require DNS-01**, so it will remain pending until a DNS-01 provider is configured. Ensure the following DNS A records point to your Traefik load balancer:

- `backstage.eks-cluster-lab.duckdns.org`
- `grafana.eks-cluster-lab.duckdns.org`
- `argocd.eks-cluster-lab.duckdns.org`
- `auth.eks-cluster-lab.duckdns.org`
- `api.eks-cluster-lab.duckdns.org`
