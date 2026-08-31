# Multi-Tenancy & Namespace Isolation — Low-Level Design

## Repo layout added

```
platform/multi-tenancy/
  base/                             # ArgoCD-managed (GitOps)
    stage/   namespace.yaml, networkpolicy.yaml (5 policies), rolebinding.yaml, kustomization.yaml
    prod/    same shape
  manual/                           # NOT ArgoCD-managed — see manual/README.md
    stage/   resourcequota.yaml, limitrange.yaml
    prod/    resourcequota.yaml, limitrange.yaml
  templates/
    helm/tenant-namespace/       Helm project template (+ values-stage.yaml, values-prod.yaml)
    terraform/
      modules/tenant-namespace/  Terraform module (main/variables/outputs/versions.tf)
      environments/stage/        root module consuming it (local backend, lab-only)
      environments/prod/         root module consuming it
  openshift/
    project-template.yaml        OpenShift Template for `oc new-project` self-service
    README.md                    how to wire projectRequestTemplate (manual, cluster-admin)
  onboarding/
    ONBOARDING.md                the 3 onboarding paths, step by step

apps/app-of-apps/
  multi-tenancy-project.yaml     AppProject scoping stage+prod destinations
  stage-namespace.yaml           Application -> platform/multi-tenancy/base/stage
  prod-namespace.yaml            Application -> platform/multi-tenancy/base/prod
  kustomization.yaml             updated to include the 3 files above

.github/
  workflows/validate-multi-tenancy.yaml
  ISSUE_TEMPLATE/new-tenant-request.yml

docs/
  multi-tenancy-hld.md, multi-tenancy-lld.md (this file),
  multi-tenancy-timeline.md, multi-tenancy-validation.md
```

## Manifest details

### Namespace

Labeled `argocd.argoproj.io/managed-by`, `tenant-environment`, and
`pod-security.kubernetes.io/{enforce,audit,warn}: restricted`. The restricted
Pod Security Standard blocks privileged containers, host namespaces/paths,
and non-default capabilities at admission — enforced independently of
NetworkPolicy/RBAC.

### ResourceQuota — applied manually, not via ArgoCD (`platform/multi-tenancy/manual/`)

| Namespace | requests.cpu | requests.memory | limits.cpu | limits.memory | pods | PVCs |
|---|---|---|---|---|---|---|
| stage | 1 | 1Gi | 2 | 2Gi | 10 | 5 |
| prod | 1.5 | 1.5Gi | 3 | 3Gi | 15 | 10 |

Sized for this lab's actual capacity (2 worker nodes × 5GB RAM, shared with
`redis-platform`, `metallb-system`, monitoring, and OVN — see
`docs/session-context.md`). For a real production cluster, resize per actual
node capacity and workload profile; the values are parameters in every one
of the three onboarding paths, not hardcoded.

**Why manual:** confirmed live on this cluster — the OpenShift GitOps
operator auto-grants the `argocd-application-controller` service account an
`admin`-equivalent Role in any namespace labeled
`argocd.argoproj.io/managed-by`, and the Kubernetes built-in `admin`
ClusterRole explicitly restricts `resourcequotas`/`limitranges` to
`get/list/watch` — never `create`. `tenant-stage`/`tenant-prod` failed to
sync with `resourcequotas is forbidden: ... cannot create resource` until
these two kinds were pulled out of `base/` into `manual/`. This mirrors the
same fix already in place for `redis-platform`
(`redis-gitops/apps/redis-platform/manual/README.md`) — it's a deliberate
Kubernetes RBAC guardrail (a namespace admin, or a GitOps controller with
admin-equivalent rights, must not be able to grant itself more quota), not
something to route around by widening the controller's RBAC.

### LimitRange — same manual path as ResourceQuota

Per-container `default`/`defaultRequest`/`max`/`min` for cpu/memory, plus a
per-Pod `max`. Prevents the "no requests/limits set → one pod eats a whole
node" failure mode without requiring every deployment author to remember to
set them.

### NetworkPolicy (5 policies per namespace)

1. `default-deny-all` — `policyTypes: [Ingress, Egress]`, empty `podSelector`
   → baseline zero-trust.
2. `allow-same-namespace` — pods in the namespace can reach each other
   (ingress) and initiate to each other (egress).
3. `allow-from-openshift-ingress` — the OpenShift router namespace can reach
   any pod, so `Route`-exposed services keep working.
4. `allow-from-monitoring` — `openshift-monitoring` and
   `openshift-user-workload-monitoring` can scrape `/metrics` endpoints.
5. `allow-dns-egress` — egress to `openshift-dns` on 5353/UDP+TCP (OpenShift's
   node-local DNS port), otherwise nothing in the deny-by-default namespace
   can resolve names at all.

No rule references the sibling namespace (`stage` policies never mention
`prod` and vice versa) — that absence is what enforces tenant isolation.

### RBAC

One `RoleBinding` per namespace: `ClusterRole/admin` (namespace-scoped by
virtue of being a RoleBinding, not a ClusterRoleBinding) to a `Group`
(`stage-team` / `prod-team`). Not cluster-admin — no access to other
namespaces, nodes, or cluster-scoped objects. Group membership itself is an
IdP/OAuth concern outside this repo's scope; the group names are placeholders
until wired to a real identity provider.

### ArgoCD AppProject

`multi-tenancy` AppProject restricts:
- `sourceRepos` to this repo only.
- `destinations` to exactly `stage` and `prod` namespaces on the in-cluster
  API server.
- `clusterResourceWhitelist` to `Namespace` only (nothing else cluster-scoped
  can be synced through this project).
- `namespaceResourceWhitelist` to core (`''`) + `networking.k8s.io`
  (NetworkPolicy) + `rbac.authorization.k8s.io` (RoleBinding) — no
  arbitrary CRDs or cross-cutting resources.

This bounds the blast radius of the GitOps pipeline itself: even a malicious
or mistaken commit under `platform/multi-tenancy/` cannot deploy outside
`stage`/`prod` or create cluster-scoped RBAC.

## Deployment steps (what actually ran)

1. `git push` this branch/PR → CI validates (see workflow above).
2. Merge to `main`.
3. `app-of-apps` Application (already `automated: {prune: true, selfHeal:
   true}`) picks up the new `multi-tenancy-project.yaml`,
   `stage-namespace.yaml`, `prod-namespace.yaml` in its own sync.
4. ArgoCD creates the `multi-tenancy` `AppProject`, then the `tenant-stage`
   and `tenant-prod` `Application` objects, which sync
   `platform/multi-tenancy/base/{stage,prod}` (Namespace, NetworkPolicy,
   RoleBinding) into the cluster.
5. Cluster-admin applies `platform/multi-tenancy/manual/{stage,prod}/*.yaml`
   out-of-band (`oc apply -f ...`) — required once per namespace; ArgoCD
   cannot create these (see `manual/README.md`).
6. Verify per `docs/multi-tenancy-validation.md`.
