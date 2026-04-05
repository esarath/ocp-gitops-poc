# OCP GitOps POC - Full Requirements

## AI Deployment Instruction – Production-Grade OCP GitOps POC

### References (Must guide architectural choices):
1. Argo CD documentation: https://argo-cd.readthedocs.io/en/stable/
2. Argo CD example apps: https://github.com/argoproj/argocd-example-apps
3. Red Hat OpenShift GitOps at scale: https://www.redhat.com/en/blog/manage-clusters-and-applications-scale-argo-cd-agent-red-hat-openshift-gitops

### Scope of Deployment (Mandatory):

#### 1. Container Build Strategy
- Implement Docker multi-stage builds
- Ensure optimized image size, secure base images, and reproducibility
- Integrate image creation strictly through CI pipelines

#### 2. CI Pipeline (GitHub Actions)
- Design GitHub Actions-based CI workflows to:
  - Build container images
  - Run unit/integration tests
  - Tag and push images to a registry
- CI must integrate cleanly with the GitOps deployment flow

#### 3. GitOps with Argo CD
- Deploy and configure Argo CD on OpenShift using:
  - Kustomize-based bootstrap
  - App-of-Apps pattern
  - Git-driven sync and reconciliation

#### 4. Sample Application Deployment (Mandatory)
- Deploy a sample-app to demonstrate multi-application GitOps management:
  - Base: Deployment, Service, ConfigMap
  - Overlays: Environment-specific patches (replicas, image tags, configs)
- Use the deployment to validate:
  - Automated sync
  - Rollout behavior
  - Environment separation

#### 5. Platform Hardening & Observability
- Configure PodDisruptionBudgets (PDBs) for Argo CD components to survive:
  - Node drains
  - Rolling updates
- Configure ServiceMonitors to scrape Argo CD metrics
- Assume single-cluster scope only (no multi-cluster configuration)

#### 6. OpenShift Platform Responsibilities
- Existing OCP cluster: https://api.lab.ocp.local:6443
- Assess and review the existing OpenShift cluster
- Validate readiness (networking, security, operators, storage, monitoring)
- Install, configure, and integrate all required components on OCP
- Follow enterprise-grade OpenShift best practices

#### 7. Required Deliverables
- End-to-end architecture and deployment flow
- Git repository structure (CI, GitOps, Kustomize layout)
- Argo CD application and sync strategies
- OpenShift manifests and overlays
- Operational and deployment documentation
- A fully working production-grade POC

### Critical Constraint – MCP Servers
- Do NOT perform installation, setup, or configuration of MCP servers without explicit confirmation
- This includes: Jira, GitHub/GitHub Actions, Argo CD, OpenShift integrations via MCP
- Pause and await confirmation before proceeding with anything related to MCP servers

## User-Confirmed Decisions
- **Git Repo**: Create locally first, user pushes to GitHub later
- **Container Registry**: Quay.io
- **ArgoCD Install Method**: Red Hat OpenShift GitOps Operator
- **Environments**: Staging + Production (2 overlays)
- **Sample App**: Python (Flask) — lightweight, simple, fast builds
- **Architecture & Plan**: Approved by user
- **Repo Structure & Phasing**: Approved by user

## Quay.io Account
- **Email**: sarrath.babu@gmail.com
- **Account Number**: 12794692
- **Trial Account**: https://www.redhat.com/en/technologies/cloud-computing/quay/trial
- **Username**: TBD — user to confirm (needed for image paths like quay.io/<username>/sample-app)
- NOTE: If username not available, use placeholder `sarrathbabu` and update later

## Approved Execution Plan (6 Phases)
| Phase | Description |
|---|---|
| 1 | Cluster Assessment - validate OCP readiness |
| 2 | ArgoCD Installation - OpenShift GitOps operator, Kustomize bootstrap, PDBs, ServiceMonitors |
| 3 | Repo Structure & Sample App - full repo, multi-stage Dockerfile, Kustomize base + overlays |
| 4 | CI Pipeline Design - GitHub Actions workflow |
| 5 | GitOps Deployment - App-of-Apps, deploy sample-app, validate sync/rollout/env separation |
| 6 | Documentation & Deliverables |

## Pending for Next Session
1. Confirm Quay.io username (for image paths)
2. Start with Phase 1: Cluster Assessment
