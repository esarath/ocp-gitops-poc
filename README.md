# OCP GitOps POC

Production-grade GitOps proof of concept on OpenShift 4.15 using ArgoCD (Red Hat OpenShift GitOps).

## Repository Structure

```
ocp-gitops-poc/
├── apps/                          # Application manifests (GitOps)
│   ├── app-of-apps/               # App-of-Apps pattern (root ArgoCD app)
│   │   ├── app-of-apps.yaml       # Root Application
│   │   ├── project.yaml           # AppProject
│   │   ├── sample-app-staging.yaml
│   │   ├── sample-app-production.yaml
│   │   └── kustomization.yaml
│   └── sample-app/                # Sample app Kustomize manifests
│       ├── base/                  # Base: Deployment, Service, ConfigMap, Route
│       └── overlays/
│           ├── staging/           # Staging overlay (1 replica)
│           └── production/        # Production overlay (2 replicas)
├── argocd/                        # ArgoCD bootstrap manifests
│   ├── base/                      # Operator subscription + ArgoCD CR
│   ├── components/
│   │   ├── pdb/                   # PodDisruptionBudgets
│   │   └── servicemonitor/        # ServiceMonitors for observability
│   └── overlays/
│       └── cluster/               # Cluster-specific overlay
├── ci/                            # CI pipeline definitions
│   └── .github/workflows/
│       ├── ci.yaml                # Build, test, push to quay.io
│       └── promote.yaml           # Promote image tag to production
├── sample-app/                    # Application source code
│   ├── src/
│   │   ├── app.py                 # Flask application
│   │   └── requirements.txt
│   ├── tests/
│   │   ├── test_app.py
│   │   └── requirements-test.txt
│   ├── Dockerfile                 # Multi-stage build
│   └── .dockerignore
└── docs/                          # Documentation
    ├── session-context.md
    ├── requirements.md
    └── phase1-cluster-assessment.md
```

## Quick Start

### Prerequisites
- OpenShift 4.15+ cluster
- `oc` CLI authenticated
- Quay.io account

### Deploy ArgoCD
```bash
oc apply -k argocd/overlays/cluster
```

### Deploy App-of-Apps
```bash
oc apply -f apps/app-of-apps/app-of-apps.yaml
```

### Access ArgoCD
```
URL: https://openshift-gitops-server-openshift-gitops.apps.lab.ocp.local
User: admin
```

### Access Sample App
```
Staging:    https://sample-app-sample-app-staging.apps.lab.ocp.local
Production: https://sample-app-sample-app-production.apps.lab.ocp.local
```

## Architecture

- **CI**: GitHub Actions builds container image, runs tests, pushes to Quay.io
- **CD**: ArgoCD watches this Git repo and auto-syncs to OpenShift
- **Promotion**: CI auto-updates staging tag; manual workflow_dispatch promotes to production
- **Pattern**: App-of-Apps for multi-environment management

## Environments

| Environment | Namespace | Replicas | Sync Policy |
|---|---|---|---|
| Staging | sample-app-staging | 1 | Automated (prune + self-heal) |
| Production | sample-app-production | 2 | Automated (prune + self-heal) |

## Container Image
- **Registry**: quay.io/sarrathbabu/sample-app
- **Build**: Multi-stage (python:3.12-slim), non-root user (UID 1001)
- **Runtime**: Gunicorn with 2 workers
