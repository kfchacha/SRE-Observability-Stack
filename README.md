# SRE Observability Stack — Production-Grade Monitoring on Kubernetes

A fully functional Site Reliability Engineering observability platform built on Kubernetes, implementing the three pillars of observability: metrics, logs, and alerting.

## Architecture

┌─────────────────────────────────────────┐
│         Kubernetes Cluster (Minikube)   │
│                                         │
│  ┌─────────────┐  ┌─────────────────┐   │
│  │ Google      │  │ Observability   │   │
│  │ Microsvcs   │  │ Stack           │   │
│  │ Demo (11    │  │                 │   │
│  │ services)   │  │ • Prometheus    │   │
│  │             │  │ • Loki          │   │
│  │             │  │ • Alertmanager  │   │
│  │             │  │ • Grafana       │   │
│  └─────────────┘  └─────────────────┘   │
└─────────────────────────────────────────┘

## Stack

| Component | Purpose | Version |
|-----------|---------|---------|
| Kubernetes | Container orchestration | Minikube v1.x |
| Prometheus | Metrics collection and alerting | kube-prometheus-stack |
| Loki | Log aggregation | loki-stack 2.10.3 |
| Promtail | Log shipping agent | bundled with loki-stack |
| Alertmanager | Alert routing and management | bundled with kube-prometheus-stack |
| Grafana | Visualisation and dashboards | 12.4.2 |
| Helm | Package management | v3.x |

## Prerequisites

- Ubuntu 20.04+
- 16GB RAM minimum
- Docker
- kubectl
- Minikube
- Helm 3

## Quick Start

### 1. Start the cluster
```bash
minikube start --cpus=4 --memory=8192 --disk-size=20g --driver=docker
```

### 2. Deploy the sample microservices app
```bash
git clone https://github.com/GoogleCloudPlatform/microservices-demo.git
kubectl create namespace demo-app
kubectl apply -f microservices-demo/release/kubernetes-manifests.yaml -n demo-app
```

### 3. Deploy the observability stack
```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

kubectl create namespace monitoring

helm install kube-prom-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --set grafana.adminPassword=admin123 \
  --set prometheus.prometheusSpec.scrapeInterval=15s \
  --set alertmanager.enabled=true

helm install loki grafana/loki-stack \
  --namespace monitoring \
  --set promtail.enabled=true \
  --set loki.persistence.enabled=false
```

### 4. Apply alert rules
```bash
kubectl apply -f manifests/alert-rules.yaml
```

### 5. Access the dashboards
```bash
# Grafana
kubectl patch svc kube-prom-stack-grafana -n monitoring -p '{"spec": {"type": "NodePort"}}'
minikube service kube-prom-stack-grafana -n monitoring

# Prometheus
kubectl patch svc kube-prom-stack-kube-promethe-prometheus -n monitoring -p '{"spec": {"type": "NodePort"}}'

# Alertmanager
kubectl patch svc kube-prom-stack-alertmanager -n monitoring -p '{"spec": {"type": "NodePort"}}'
```

Grafana credentials: `admin` / `admin123`

## Alert Rules

Three alert groups implemented:

**pod-health**
- `PodCrashLooping` — fires when a pod restarts more than once per 5 minutes (critical)
- `PodNotReady` — fires when a pod is not ready for more than 2 minutes (warning)

**node-resources**
- `HighCPUUsage` — fires when CPU exceeds 80% for 5 minutes (warning)
- `HighMemoryUsage` — fires when memory exceeds 85% for 5 minutes (critical)
- `DiskSpaceLow` — fires when disk usage exceeds 80% for 10 minutes (warning)

**kubernetes-health**
- `DeploymentReplicasMismatch` — fires when available replicas don't match desired (critical)

## Custom Grafana Dashboard — PromQL Queries

Built a custom dashboard with these queries (adapted for Minikube cAdvisor label schema):
```promql
# CPU usage by pod
sum(rate(container_cpu_usage_seconds_total{namespace="demo-app", cpu="total"}[5m])) by (pod)

# Memory usage by pod
sum(container_memory_working_set_bytes{namespace="demo-app"}) by (pod)

# Pod restart rate
sum(increase(kube_pod_container_status_restarts_total{namespace="demo-app"}[1h])) by (pod)

# Running pod count
count(kube_pod_status_phase{namespace="demo-app", phase="Running"})

# Network receive rate
sum(rate(container_network_receive_bytes_total{namespace="demo-app"}[5m])) by (pod)
```

## Incident Simulations

### CPU Spike
```bash
./scripts/simulate-cpu-spike.sh
```
Deploys a CPU stress container consuming 4 cores. Triggers `HighCPUUsage` alert within 5 minutes.

### CrashLoopBackOff
```bash
./scripts/simulate-crashloop.sh
```
Deploys a pod that exits with code 1 every 5 seconds. Triggers `PodCrashLooping` alert within 2 minutes.

### Memory Pressure
```bash
./scripts/simulate-memory-stress.sh
```
Deploys a pod consuming 256MB RAM continuously. Visible on Grafana memory dashboard immediately.

### Cleanup
```bash
./scripts/cleanup-incidents.sh
```

## Real Incidents Diagnosed and Fixed

### 1. recommendationservice CrashLoopBackOff
**Symptom:** Pod stuck in CrashLoopBackOff on fresh deployment  
**Root cause:** gRPC liveness probe firing immediately (`initialDelaySeconds: 0`) with 1 second timeout — Python gRPC server needs ~15 seconds to initialise  
**Fix:** Patched probe timing — `initialDelaySeconds: 20`, `timeoutSeconds: 5`, `failureThreshold: 5`  
**Runbook:** `runbooks/crashloop-runbook.md`

### 2. Grafana startup failure — duplicate default datasource
**Symptom:** Grafana pod in CrashLoopBackOff after Loki installation  
**Root cause:** Both kube-prometheus-stack and loki-stack Helm charts provisioned datasources with `isDefault: true` — Grafana 12.x enforces single default per organisation  
**Fix:** Patched `loki-loki-stack` ConfigMap — set `isDefault: false` for Loki datasource  
**Lesson:** When installing multiple Helm charts that integrate with Grafana, always check for datasource provisioning conflicts

### 3. PromQL queries returning no data on Minikube
**Symptom:** Standard `container!=""` filter returning empty results  
**Root cause:** Minikube cAdvisor exposes pod-level CPU metrics without a `container` label — only `cpu="total"` label available at pod scope  
**Fix:** Replaced `container!=""` with `cpu="total"` in all CPU queries  
**Lesson:** Always inspect raw metric labels before writing queries — never assume label schemas match documentation

## Key Learnings

- Helm chart interactions can cause conflicts — always check provisioning ConfigMaps when multiple charts integrate with the same service
- Minikube cAdvisor exposes metrics with different label schemas than cloud Kubernetes — `cpu="total"` instead of `container!=""`
- PrometheusRule CRDs enable GitOps for alert management — rules live in Git alongside application code
- The difference between a health check failure and a service failure — Loki's `/ready` endpoint returns 404 on this version but log querying works correctly

## Project Structure

sre-observability-stack/
├── README.md
├── manifests/
│   ├── alert-rules.yaml
│   ├── alertmanager-config.yaml
│   └── loki-datasource-configmap.yaml
├── runbooks/
│   ├── high-cpu-runbook.md
│   └── crashloop-runbook.md
├── dashboards/
│   └── sre-demo-pod-health.json
├── scripts/
│   ├── simulate-cpu-spike.sh
│   ├── simulate-crashloop.sh
│   ├── simulate-memory-stress.sh
│   └── cleanup-incidents.sh
└── screenshots/
├── grafana-dashboard.png
├── prometheus-alerts-firing.png
└── alertmanager-active-alerts.png

