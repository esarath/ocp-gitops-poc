# Multi-Tenancy POC — Timeline & Resource Requirements

## Task timeline

| Day | Task | Deliverable | Depends on |
|---|---|---|---|
| 1 | Prerequisites: confirm cluster access, kubectl/Helm/Terraform installed, repo branch created | Verified tooling, feature branch | cluster-admin kubeconfig |
| 2 | Write & validate namespace manifests (`namespace.yaml` for stage/prod) | `base/{stage,prod}/namespace.yaml` | Day 1 |
| 3 | Implement `ResourceQuota` + `LimitRange` (applied manually, not via ArgoCD — see `manual/README.md`) | `manual/{stage,prod}/{resourcequota,limitrange}.yaml` | Day 2 |
| 4 | Implement `NetworkPolicy` set (5 policies × 2 namespaces) | `base/{stage,prod}/networkpolicy.yaml` | Day 2 |
| 5 | Build project templates (Helm chart + Terraform module) + OpenShift native template; write onboarding docs | `templates/helm/`, `templates/terraform/`, `openshift/`, `onboarding/ONBOARDING.md` | Day 2–4 |
| 6 | Wire ArgoCD (`AppProject` + `Application`×2), CI workflow, issue template; push to repo, run validation pipeline | `apps/app-of-apps/*`, `.github/workflows/validate-multi-tenancy.yaml`, green CI run | Day 2–5 |
| 7 | Deploy to cluster (bootstrap `app-of-apps`, ArgoCD sync, manual quota/limitrange apply), run post-deployment checks, sign off | Synced `stage`/`prod` namespaces, completed validation checklist | Day 6, green CI |

This POC was executed with Day 1–6 compressed into a single session (all
manifests, templates, CI, and docs generated and pushed together). Day 7
(cluster deployment) surfaced a real finding worth keeping in the timeline:
`app-of-apps` wasn't registered on the cluster yet (dormant since an OCP
upgrade), and the first sync attempt failed because ArgoCD's
auto-granted namespace role can't create `ResourceQuota`/`LimitRange` — both
fixed by bootstrapping the root Application and moving those two kinds to
`platform/multi-tenancy/manual/` (see `docs/multi-tenancy-lld.md`).

## Resource requirements

### Cluster capacity (existing, from `docs/session-context.md`)

- 3 masters (13.5GB RAM each, `mastersSchedulable: false` — not available for
  tenant workloads), 2 workers (5GB RAM each, schedulable).
- Already resident on the workers: OVN-Kubernetes (~1.6Gi), `redis-platform`,
  `metallb-system`, `openshift-gitops`, monitoring stack.

### What this POC adds to that capacity

| Namespace | requests.cpu | requests.memory | Notes |
|---|---|---|---|
| stage | up to 1 vCPU | up to 1Gi | quota ceiling; 0 until a workload is actually deployed into it |
| prod | up to 1.5 vCPU | up to 1.5Gi | quota ceiling; 0 until a workload is actually deployed into it |

The namespaces, quotas, limits, network policies, and RBAC objects
themselves consume no compute — `ResourceQuota` is a ceiling, not a
reservation. Actual consumption only appears once a team deploys workloads
into `stage`/`prod`, at which point the quota caps what they can consume
regardless of what they request.

### Human/process resources

- 1 cluster-admin (you) for Day 1 prerequisites and Day 7 sync verification.
- GitHub Actions minutes: 4 short jobs (yamllint, kustomize/kubeconform,
  helm lint, terraform validate) per push/PR — all free-tier eligible for a
  public repo.
- No new infrastructure spend: reuses the existing `openshift-gitops`
  ArgoCD instance, no new operators or storage.
