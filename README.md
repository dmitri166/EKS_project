# EKS Project - Flask DevOps Infrastructure

A production-ready DevOps project showcasing a Flask To-Do API deployed on AWS EKS with complete infrastructure as code, GitOps deployment, and comprehensive monitoring stack.

## 🏗️ Architecture Overview

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Terraform     │───▶│   AWS Resources  │───▶│   EKS Cluster   │
│   (IaC)         │    │   (VPC, RDS, IAM)│    │                 │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                                                        │
                                                        ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Argo CD       │◀───│   Git Repo      │───▶│   Helm Charts   │
│   (GitOps)      │    │   (Source)       │    │   (Packaging)   │
└─────────────────┘    └─────────────────┘    └─────────────────┘
        │                                             │
        ▼                                             ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Kubernetes    │───▶│  Flask App      │───▶│  Monitoring     │
│   Applications  │    │  (Canary/Deploy)│    │  (Prometheus)   │
└─────────────────┘    └─────────────────┘    └─────────────────┘
        │
        ▼
┌─────────────────┐    ┌─────────────────┐
│  RDS / Redis    │◀───│ Secrets Manager │
│ (PostgreSQL)    │    │ (Auto-Generated)│
└─────────────────┘    └─────────────────┘
```

## 📁 Project Structure

```
EKS_project/
├── app/                          # Flask API Application
│   ├── main.py                   # Flask application with PostgreSQL & Redis
│   ├── Dockerfile                # Multi-stage Docker build
│   ├── requirements.txt          # Python dependencies
│   └── test_app.py               # Application tests
├── helm/
│   └── flask-app/                # Helm Chart for Flask App
│       ├── Chart.yaml
│       ├── values.yaml
│       └── templates/            # Kubernetes manifests
├── terraform/
│   ├── bootstrap/                # S3/DynamoDB Backend Setup
│   ├── environments/
│   │   └── production/           # Production environment config
│   └── modules/                  # Reusable Terraform modules
│       ├── vpc/                  # VPC configuration
│       ├── eks/                  # EKS cluster
│       ├── iam/                  # IAM roles
│       ├── rds/                  # RDS PostgreSQL
│       ├── oidc/                 # OIDC for GitHub Actions
│       ├── karpenter/            # Karpenter autoscaler
│       ├── alb-controller/       # AWS Load Balancer Controller
│       └── eso/                  # External Secrets Operator
├── argo-cd/                      # GitOps Application manifests
│   ├── root-app.yaml             # App of Apps pattern
│   └── apps/                     # Individual ArgoCD applications
│       ├── argocd.yaml
│       ├── flask-app.yaml
│       ├── monitoring.yaml
│       ├── redis.yaml
│       ├── external-secrets.yaml
│       ├── alb-controller.yaml
│       ├── kyverno.yaml
│       ├── falco.yaml
│       ├── loki.yaml
│       ├── kubecost.yaml
│       ├── argo-rollouts.yaml
│       └── eso-resources.yaml
├── k8s/                          # Supplementary K8s manifests
│   ├── eso/                      # External Secrets configs
│   ├── eso-resources/            # ESO resource definitions
│   ├── kyverno-policies/         # Kyverno policy definitions
│   ├── flask-app-canary.yaml     # Canary deployment example
│   └── flask-app-canary-analysis.yaml
├── monitoring/
│   └── prometheus/               # Prometheus configuration
│       ├── config.yaml
│       └── alert_rules.yml
├── PROVISIONING.md               # Detailed step-by-step guide
└── README.md                     # This file
```

## 🚀 Quick Start

For a comprehensive, step-by-step guide on how to provision this project from zero, including variable configuration and verification commands, please see:

👉 **[PROVISIONING.md](./PROVISIONING.md)**

### Prerequisites

- **Terraform**: v1.5 or higher
- **AWS CLI**: Authenticated with appropriate IAM permissions
- **kubectl**: For Kubernetes cluster interaction
- **Helm**: For managing Kubernetes applications

### Quick Deployment

```bash
# 1. Bootstrap Terraform backend
cd terraform/bootstrap
terraform init
terraform apply -auto-approve

# 2. Deploy core infrastructure
cd ../environments/production
terraform init
terraform apply -auto-approve

# 3. Configure kubectl
aws eks update-kubeconfig --region us-east-1 --name flask-devops-cluster

# 4. Deploy ArgoCD and applications
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd
kubectl apply -f argo-cd/apps/
```

## 🏗️ Infrastructure Components

### **Terraform Modules**

| Module | Description |
|--------|-------------|
| `vpc` | VPC with public/private subnets, NAT gateways, VPC endpoints |
| `eks` | EKS cluster with managed node group and OIDC provider |
| `iam` | IAM roles for EKS cluster and node groups |
| `rds` | PostgreSQL RDS instance with Secrets Manager integration |
| `oidc` | OIDC provider for GitHub Actions |
| `karpenter` | Karpenter autoscaler for efficient node provisioning |
| `alb-controller` | AWS Load Balancer Controller for ingress |
| `eso` | External Secrets Operator for secrets management |

### **Kubernetes Components (via ArgoCD)**

| Component | Description |
|-----------|-------------|
| **ArgoCD** | GitOps continuous deployment |
| **Flask App** | Python Flask API with PostgreSQL & Redis |
| **Monitoring** | Prometheus & Grafana stack |
| **Redis** | In-memory cache (Bitnami chart) |
| **External Secrets** | Syncs AWS Secrets Manager to K8s secrets |
| **ALB Controller** | Manages AWS Application Load Balancers |
| **Kyverno** | Kubernetes native policy management |
| **Falco** | Runtime security monitoring |
| **Loki** | Log aggregation system |
| **Kubecost** | Cost monitoring and optimization |
| **Argo Rollouts** | Advanced deployment strategies (Canary) |

## 📊 API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/tasks` | List all tasks (with Redis caching) |
| POST | `/tasks` | Create a new task |
| PUT | `/tasks/<id>` | Update task status |
| DELETE | `/tasks/<id>` | Delete a task |
| GET | `/health` | Health check (DB & Redis status) |
| GET | `/ready` | Readiness probe for K8s |
| GET | `/metrics` | Prometheus metrics |

## 📈 Monitoring & Observability

### **Prometheus Metrics**

- `flask_requests_total` - Total requests per endpoint (method, endpoint, status)
- `flask_tasks_total` - Total number of tasks (created, updated, deleted)
- `flask_request_duration_seconds` - Request latency histogram

### **Alerting Rules**

| Alert | Condition | Severity |
|-------|-----------|----------|
| FlaskAppDown | Application down for >1m | Critical |
| HighRequestRate | >10 req/s for >2m | Warning |
| HighErrorRate | >10% errors for >3m | Warning |
| HighResponseTime | p95 >1s for >5m | Warning |
| TooManyTasks | >1000 tasks for >10m | Info |

### **Grafana Dashboards**

- Request rate per endpoint
- Task count over time
- Pod health status
- Resource utilization (CPU/Memory)

## 🔐 Security Features

### **Secrets Management**

- **AWS Secrets Manager**: Automatic password generation for RDS and Redis
- **External Secrets Operator**: Secure sync from AWS to Kubernetes
- **No hardcoded credentials**: All secrets managed via infrastructure

### **Policy Enforcement**

- **Kyverno**: Kubernetes native policy management
  - Disallows privileged containers
  - Enforces security best practices

### **Runtime Security**

- **Falco**: Runtime security monitoring with modern eBPF driver
- **Security alerts**: Real-time threat detection

## 💰 Cost Optimization

### **Current Configuration**

| Resource | Configuration | Estimated Monthly Cost |
|----------|---------------|------------------------|
| EKS Cluster | 1-2 nodes (t3.small) | $70-100 |
| RDS PostgreSQL | db.t3.micro | $15-20 |
| Redis | Standalone (8Gi) | $15-20 |
| Monitoring | Prometheus + Grafana | $20-30 |
| **Total** | | **$120-170** |

### **Cost Optimization Features**

- ✅ **Auto-scaling**: HPA scales pods based on CPU/Memory
- ✅ **ClusterIP Services**: No LoadBalancer costs for internal services
- ✅ **Optimized Resources**: Right-sized CPU/Memory requests
- ✅ **Karpenter**: Efficient node provisioning
- ✅ **Kubecost**: Cost monitoring and optimization insights

### **Cost Monitoring**

```bash
# Check resource usage
kubectl top nodes
kubectl top pods --all-namespaces

# Access Kubecost dashboard
kubectl port-forward -n kubecost svc/kubecost-cost-analyzer 9090:9090
```

## 🔧 Configuration

### **Environment Variables**

The Flask application uses the following environment variables:

| Variable | Description | Default |
|----------|-------------|---------|
| `DATABASE_URL` | PostgreSQL connection string | From Secrets Manager |
| `REDIS_HOST` | Redis hostname | `redis-master.default.svc.cluster.local` |
| `REDIS_PORT` | Redis port | `6379` |
| `FLASK_HOST` | Flask bind address | `0.0.0.0` |
| `FLASK_PORT` | Flask port | `5000` |
| `FLASK_DEBUG` | Debug mode | `false` |
| `LOG_LEVEL` | Logging level | `INFO` |

### **Helm Values**

Key configuration options in `helm/flask-app/values.yaml`:

```yaml
replicaCount: 2
autoscaling:
  enabled: true
  minReplicas: 1
  maxReplicas: 4
rollout:
  enabled: false  # Enable for canary deployments
persistence:
  enabled: false  # Using PostgreSQL instead of SQLite
```

## 🔍 Troubleshooting

### **Common Issues**

1. **Pods not starting:**
   ```bash
   kubectl describe pod <pod-name> -n flask-app
   kubectl logs <pod-name> -n flask-app
   ```

2. **Secrets not syncing:**
   ```bash
   kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets
   kubectl get externalsecrets -A
   ```

3. **ALB not creating:**
   ```bash
   kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
   kubectl get ingress -n flask-app
   ```

4. **ArgoCD sync issues:**
   ```bash
   argocd app get flask-app
   argocd app sync flask-app
   ```

5. **Terraform state issues:**
   ```bash
   cd terraform/environments/production
   terraform state list
   terraform refresh
   ```

### **Verification Commands**

```bash
# Check cluster health
kubectl get nodes
kubectl get pods -A

# Check application status
kubectl get pods -n flask-app
kubectl get ingress -n flask-app

# Check ArgoCD applications
kubectl get applications -n argocd

# Test application endpoint
ALB_URL=$(kubectl get ingress -n flask-app -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}')
curl http://$ALB_URL/health
```

## 📚 Additional Resources

- [Flask Documentation](https://flask.palletsprojects.com/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Helm Documentation](https://helm.sh/docs/)
- [ArgoCD Documentation](https://argoproj.github.io/argo-cd/)
- [Prometheus Documentation](https://prometheus.io/docs/)

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes
4. Add tests if applicable
5. Commit your changes (`git commit -m 'Add amazing feature'`)
6. Push to the branch (`git push origin feature/amazing-feature`)
7. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.