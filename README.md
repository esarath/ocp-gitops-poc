## OCP GitOps POC

Production-grade GitOps proof of concept on OpenShift 4.15 using ArgoCD (Red Hat OpenShift GitOps).

## Repository Structure

```
ocp-gitops-poc/
├── .github/workflows/             # CI/CD pipeline definitions
│   ├── ci.yaml                    # Build, test, push to ghcr.io, update staging
│   └── promote.yaml               # Promote image tag to production (manual trigger)
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
│           ├── staging/           # Staging overlay (1 replica, auto-updated by CI)
│           └── production/        # Production overlay (2 replicas, manual promote)
├── argocd/                        # ArgoCD bootstrap manifests
│   ├── base/                      # Operator subscription + ArgoCD CR
│   ├── components/
│   │   ├── pdb/                   # PodDisruptionBudgets
│   │   └── servicemonitor/        # ServiceMonitors for observability
│   └── overlays/
│       └── cluster/               # Cluster-specific overlay
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
    ├── step-by-step-guide.md      # Full deployment walkthrough
    ├── ci-pipeline-fix-rca.md     # CI pipeline RCA (Quay.io -> ghcr.io fix)
    ├── session-context.md         # Cluster state & access details
    ├── requirements.md
    └── phase1-cluster-assessment.md
```

## Quick Start

### Prerequisites
- OpenShift 4.15+ cluster
- `oc` CLI authenticated
- GitHub account (ghcr.io uses built-in GITHUB_TOKEN - no external registry account needed)

### Deploy ArgoCD
```bash
oc apply -k argocd/overlays/cluster
```

### Deploy App-of-Apps
```bash
oc apply -f apps/app-of-apps/app-of-apps.yaml -n openshift-gitops
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

```
Code Push --> GitHub Actions CI --> ghcr.io Image --> Manifest Update --> ArgoCD Sync --> Pod Rollout
```

- **CI**: GitHub Actions builds container image, runs tests, pushes to ghcr.io with commit SHA tag
- **CD**: ArgoCD watches this Git repo and auto-syncs to OpenShift
- **Image Tags**: Each overlay uses kustomize `images.newTag` with the commit SHA (not `:latest`), ensuring ArgoCD detects changes and triggers pod rollouts automatically
- **Promotion**: CI auto-updates staging tag; manual `workflow_dispatch` promotes to production
- **Pattern**: App-of-Apps for multi-environment management

## Environments

| Environment | Namespace | Replicas | Sync Policy | Image Update |
|---|---|---|---|---|
| Staging | sample-app-staging | 1 | Automated (prune + self-heal) | Auto (CI commits new tag) |
| Production | sample-app-production | 2 | Automated (prune + self-heal) | Manual (promote workflow) |

## Container Image

- **Registry**: ghcr.io (GitHub Container Registry)
- **Image**: `ghcr.io/esarath/sample-app`
- **Tags**: Commit SHA (e.g., `e132cfe`) + `latest`
- **Auth**: Built-in `GITHUB_TOKEN` (no external secrets needed)
- **Build**: Multi-stage (python:3.12-slim), non-root user (UID 1001), Gunicorn with 2 workers

## CI/CD Pipeline

### Build Pipeline (`.github/workflows/ci.yaml`)
Triggers on push to `main` with changes in `sample-app/**`:
1. **test** - Install deps, run pytest
2. **build-and-push** - Build Docker image, push to ghcr.io with SHA tag + latest
3. **update-manifests** - Update staging `kustomization.yaml` (both `newTag` and `APP_VERSION`)

### Promote Pipeline (`.github/workflows/promote.yaml`)
Manual trigger (`workflow_dispatch`) with image tag input:
- Updates production `kustomization.yaml` (both `newTag` and `APP_VERSION`)

## Documentation

- [Step-by-Step Deployment Guide](docs/step-by-step-guide.md) - Full walkthrough from repo creation to end-to-end testing
- [CI Pipeline RCA](docs/ci-pipeline-fix-rca.md) - Root cause analysis of CI failures (Quay.io to ghcr.io migration)
- [Cluster Assessment](docs/phase1-cluster-assessment.md) - Phase 1 cluster health checks
- [Session Context](docs/session-context.md) - Cluster topology, access details, and current state
