# Awesome Flask DevOps Project

A production-ready DevOps project showcasing a Flask To-Do API with complete infrastructure as code, CI/CD pipeline, and monitoring stack.

## 🏗️ Architecture Overview

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   GitHub Repo   │───▶│  GitHub Actions │───▶│   Artifactory   │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                                                        │
                                                        ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Argo CD       │◀───│   Helm Chart    │◀───│  Docker Image   │
└─────────────────┘    └─────────────────┘    └─────────────────┘
        │
        ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   AWS EKS       │───▶│  Flask App      │───▶  Prometheus    │
│   (Terraform)   │    │  (Pods)         │    │  + Grafana      │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

## 📁 Project Structure

```
awesome-flask-devops/
├─ app/
│  ├─ Dockerfile              # Multi-stage Docker build
│  ├─ requirements.txt        # Python dependencies
│  └─ main.py                 # Flask API with metrics
├─ helm/
│  └─ flask-app/
│     ├─ Chart.yaml           # Helm chart metadata
│     ├─ values.yaml          # Default configuration
│     └─ templates/
│        ├─ deployment.yaml   # Kubernetes deployment
│        ├─ service.yaml      # Service configuration
│        └─ hpa.yaml          # Horizontal Pod Autoscaler
├─ terraform/
│  ├─ eks/
│  │  ├─ main.tf             # EKS cluster configuration
│  │  ├─ variables.tf        # Input variables
│  │  └─ outputs.tf          # Output values
│  ├─ vpc/
│  │  ├─ main.tf             # VPC with subnets
│  │  ├─ variables.tf        # VPC configuration
│  │  └─ outputs.tf          # VPC outputs
│  └─ iam/
│     ├─ main.tf             # IAM roles for EKS
│     ├─ variables.tf        # IAM variables
│     └─ outputs.tf          # IAM outputs
├─ argo-cd/
│  └─ application.yaml       # Argo CD app manifest
├─ github-actions/
│  └─ ci-cd.yaml             # CI/CD pipeline
├─ monitoring/
│  ├─ prometheus/
│  │  └─ config.yaml         # Prometheus config
│  └─ grafana/
│     └─ dashboard.json      # Grafana dashboard
└─ README.md                 # This file
```

## 🚀 Quick Start - Cost Optimized

### Prerequisites

- [Terraform](https://www.terraform.io/) >= 1.0
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [Helm](https://helm.sh/) >= 3.0
- [Docker](https://www.docker.com/)
- Python 3.11+
- AWS CLI configured with credentials

### 🎯 Option 1: Cost-Optimized Bootstrap (Recommended)

```bash
# Clone the repository
git clone https://github.com/dmitri166/EKS_project.git
cd EKS_project

# Make cost-optimized bootstrap script executable
chmod +x bootstrap-cost-optimized.sh

# Deploy with cost optimization (choose mode)
./bootstrap-cost-optimized.sh minimal    # ~$50-70/month
./bootstrap-cost-optimized.sh balanced   # ~$100-130/month  
./bootstrap-cost-optimized.sh production # ~$200-250/month
```

### 🎯 Option 2: Standard Bootstrap
```bash
# Clone the repository
git clone https://github.com/dmitri166/EKS_project.git
cd EKS_project

# Make bootstrap script executable
chmod +x bootstrap.sh

# Deploy everything with one command
./bootstrap.sh
```

### 🎯 Option 3: Manual Step-by-Step

#### 1. Deploy Infrastructure (Terraform)
```bash
# Deploy VPC
cd terraform/vpc
terraform init
terraform apply -auto-approve

# Deploy IAM roles
cd ../iam
terraform init
terraform apply -auto-approve

# Deploy EKS cluster
cd ../eks
terraform init
terraform apply -auto-approve
```

#### 2. Configure kubectl
```bash
# Update kubeconfig
aws eks update-kubeconfig --region us-east-1 --name flask-devops-cluster

# Verify connection
kubectl get nodes
```

#### 3. Bootstrap Argo CD (One-time)
```bash
# Install Argo CD
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for Argo CD to be ready
kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=300s
```

#### 4. Deploy All Applications via GitOps
```bash
# Deploy Root App (App of Apps)
kubectl apply -f argo-cd/root-app.yaml

# Install Argo CD CLI
curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x argocd
sudo mv argocd /usr/local/bin/argocd

# Login and sync
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
ARGOCD_SERVER=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].hostname}:8080')
argocd login $ARGOCD_SERVER --username admin --password $ARGOCD_PASSWORD --insecure
argocd app sync root-app
```

### 🎯 Option 4: GitHub Actions CI/CD

```bash
# Push to main branch - triggers full deployment
git push origin main

# Push to develop branch - triggers testing only
git push origin develop
```

## 💰 Cost Optimization Guide

### **Cost Comparison Table**

| Configuration | Nodes | Instance Type | Monthly Cost | Use Case |
|---------------|---------|---------------|---------------|----------|
| **Minimal** | 1 × t3.nano | $50-70 | Development/Testing |
| **Balanced** | 2 × t3.small | $100-130 | Small Production |
| **Production** | 3 × t3.medium | $200-250 | Full Production |

### **Cost Optimization Features Applied**

#### **1. Infrastructure Savings**
- ✅ **Spot Instances**: 60-70% savings on compute
- ✅ **Reduced Node Count**: 2 nodes instead of 3
- ✅ **Smaller Instances**: t3.small instead of t3.medium
- ✅ **Auto-scaling**: Scale from 1-4 nodes

#### **2. Application Savings**
- ✅ **ClusterIP Services**: No LoadBalancer costs for internal services
- ✅ **Reduced Replicas**: 1 Flask pod instead of 2
- ✅ **Optimized Resources**: Lower CPU/Memory requests
- ✅ **Smaller Storage**: 512Mi instead of 1Gi

#### **3. Monitoring Savings**
- ✅ **ClusterIP Services**: Grafana/Prometheus internal only
- ✅ **Reduced Storage**: 5Gi Prometheus, 2Gi Grafana
- ✅ **Optimized Resources**: Lower CPU/Memory limits
- ✅ **Disabled AlertManager**: Save resources

### **Cost Monitoring Commands**

```bash
# Check resource usage
kubectl top nodes
kubectl top pods --all-namespaces

# Check AWS costs
aws ce get-cost-and-usage --time-period StartOfMonth-EndOfMonth

# Set up cost alerts
aws budgets create-budget \
  --account-id $(aws sts get-caller-identity --query Account --output text) \
  --budget flask-devops \
  --budget-type COST \
  --time-unit MONTHLY \
  --budget-amount 150 \
  --notification-with-subscribers \
  --subscriber Email=your-email@example.com
```

### **Advanced Cost Optimization**

#### **Schedule-Based Scaling**
```bash
# Scale down during off-hours (9 PM - 9 AM)
kubectl scale deployment flask-app --replicas=1 -n flask-app

# Scale up during work hours (9 AM - 9 PM)
kubectl scale deployment flask-app --replicas=2 -n flask-app
```

#### **Resource Right-Sizing**
```bash
# Monitor actual resource usage
kubectl describe pod <pod-name> | grep -A 10 "Requests:"

# Adjust resources based on actual usage
# Edit helm/flask-app/values.yaml
```

#### **Storage Optimization**
```bash
# Check storage usage
kubectl exec -it deployment/flask-app -n flask-app -- du -sh /app/data

# Clean up unused resources
kubectl delete pvc --all -n monitoring
```

## 🏗️ Architecture Overview

### **Hybrid Approach Separation:**

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Terraform     │───▶│   AWS Resources  │───▶│   Empty EKS     │
│   (Infrastructure)│   │   (VPC, IAM)     │    │   Cluster       │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                                                        │
                                                        ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   GitHub Repo   │───▶│   Argo CD       │───▶│   Kubernetes    │
│   (GitOps)      │    │   (GitOps)       │    │   Applications  │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                                │
                                ▼
                       ┌─────────────────┐
                       │   Helm Charts   │
                       │   (Packaging)   │
                       └─────────────────┘
```

### **What Each Tool Manages:**

- **Terraform**: AWS infrastructure (VPC, EKS cluster, IAM roles)
- **Argo CD**: Kubernetes resources via GitOps
- **Helm**: Package format for applications
- **GitHub Actions**: CI/CD pipeline automation

## 📊 API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/tasks` | List all tasks |
| POST | `/tasks` | Create a new task |
| PUT | `/tasks/<id>` | Update task status |
| DELETE | `/tasks/<id>` | Delete a task |
| GET | `/health` | Health check |
| GET | `/metrics` | Prometheus metrics |

## 📈 Monitoring & Observability

### Metrics Available
- `flask_requests_total` - Total requests per endpoint
- `flask_tasks_total` - Total number of tasks
- `flask_request_duration_seconds` - Request latency

### Grafana Dashboard
- Request rate per endpoint
- Task count over time
- Pod health status
- Resource utilization

## 🔧 DevOps Best Practices

### Infrastructure as Code
- **Terraform modules** for reusable infrastructure
- **Environment separation** (dev/staging/prod)
- **State management** with remote backend
- **Drift detection** and automated remediation

### CI/CD Pipeline
- **Automated testing** on every push/PR
- **Security scanning** and vulnerability checks
- **Docker image optimization** with multi-stage builds
- **GitOps deployment** via Argo CD
- **Rollback capabilities** with Helm

### Security
- **Least privilege** IAM roles
- **Network policies** for pod communication
- **Secrets management** with Kubernetes secrets
- **Image scanning** in CI pipeline
- **RBAC** for cluster access

### Scaling & Performance
- **Horizontal Pod Autoscaler** based on CPU/memory
- **Pod disruption budgets** for availability
- **Resource limits** and requests
- **Health checks** and readiness probes
- **Graceful shutdown** handling

### Monitoring & Alerting
- **Prometheus metrics** collection
- **Grafana dashboards** for visualization
- **Alertmanager** for notifications
- **SLI/SLO** monitoring
- **Log aggregation** with structured logging

## 🗄️ Database Migration Guide

### From SQLite to PostgreSQL

1. **Update requirements.txt:**
```txt
# Replace sqlite3 with:
psycopg2-binary==2.9.7
SQLAlchemy==2.0.21
```

2. **Update database configuration:**
```python
# In main.py, replace SQLite connection with:
DATABASE_URL = os.getenv('DATABASE_URL', 'postgresql://user:pass@localhost:5432/todoapp')
```

3. **Add Kubernetes secret:**
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: database-secret
type: Opaque
data:
  DATABASE_URL: <base64-encoded-connection-string>
```

4. **Update Helm values.yaml:**
```yaml
env:
  - name: DATABASE_URL
    valueFrom:
      secretKeyRef:
        name: database-secret
        key: DATABASE_URL
```

5. **Deploy PostgreSQL:**
```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm install postgresql bitnami/postgresql
```

## 🚨 Alerting Rules

### High Request Rate Alert
```yaml
- alert: HighRequestRate
  expr: rate(flask_requests_total[5m]) > 10
  for: 2m
  labels:
    severity: warning
  annotations:
    summary: "High request rate detected"
```

### Unhealthy Pods Alert
```yaml
- alert: UnhealthyPods
  expr: up{job="flask-app"} == 0
  for: 1m
  labels:
    severity: critical
  annotations:
    summary: "Flask application pods are unhealthy"
```

## 🔍 Troubleshooting

### Common Issues

1. **Pods not starting:**
   ```bash
   kubectl describe pod <pod-name>
   kubectl logs <pod-name>
   ```

2. **Helm deployment issues:**
   ```bash
   helm status flask-app
   helm history flask-app
   ```

3. **Terraform state issues:**
   ```bash
   terraform state list
   terraform refresh
   ```

4. **Argo CD sync issues:**
   ```bash
   argocd app get flask-app
   argocd app sync flask-app
   ```

## 📚 Additional Resources

- [Flask Documentation](https://flask.palletsprojects.com/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Terraform Provider AWS](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Helm Best Practices](https://helm.sh/docs/topics/best_practices/)
- [Argo CD User Guide](https://argoproj.github.io/argo-cd/user-guide/)
- [Prometheus Monitoring](https://prometheus.io/docs/)

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.
