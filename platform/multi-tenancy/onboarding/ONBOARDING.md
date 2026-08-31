# Self-Service Tenant Onboarding

Two supported paths for getting a new isolated namespace, both landing in
the same governed shape (quota + limits + default-deny NetworkPolicy +
scoped admin RoleBinding).

For a concrete, fully worked example of Path A with a real workload
(deploying redis-app/redis-db into `stage` and verifying quota, isolation,
and RBAC all hold up in practice) see
[`redis-stage-walkthrough.md`](redis-stage-walkthrough.md).

## Path A — GitOps PR (recommended; how `stage`/`prod` were onboarded)

1. Open an issue using `.github/ISSUE_TEMPLATE/new-tenant-request.yml`
   (captures name, environment, admin group, sizing).
2. Render the manifests from the Helm project template:
   ```bash
   cd platform/multi-tenancy/templates/helm/tenant-namespace
   helm template <name> . \
     --set tenant.name=<name> \
     --set tenant.environment=<env> \
     --set tenant.adminGroup=<idp-group> \
     > /tmp/<name>-rendered.yaml
   ```
   (or copy `values-stage.yaml` as a starting point and adjust quota/limits).
3. Split the rendered output into two places, matching `base/stage/` +
   `manual/stage/`:
   - `platform/multi-tenancy/base/<name>/` — `namespace.yaml`,
     `networkpolicy.yaml`, `rolebinding.yaml`, plus a `kustomization.yaml`
     listing them. This part is ArgoCD-managed.
   - `platform/multi-tenancy/manual/<name>/` — `resourcequota.yaml`,
     `limitrange.yaml`. **Not** ArgoCD-managed — see
     `platform/multi-tenancy/manual/README.md` for why (confirmed on this
     cluster: the ArgoCD controller cannot create these, by design).
4. Add an `AppProject` destination entry (`apps/app-of-apps/multi-tenancy-project.yaml`)
   and a new `Application` (copy `apps/app-of-apps/stage-namespace.yaml`,
   point `path` at the new base dir and `destination.namespace` at `<name>`).
5. Add the new resource files to `apps/app-of-apps/kustomization.yaml`.
6. Open a PR. CI (`validate-multi-tenancy.yaml`) lints YAML, runs
   `kustomize build`, and a real (kind-cluster-backed) `kubectl apply
   --dry-run=server` against every new manifest, including `manual/`.
7. On peer approval + merge to `main`, ArgoCD (`app-of-apps`) picks up the
   new `AppProject`/`Application` and auto-syncs `base/<name>/`.
8. Cluster-admin applies `manual/<name>/*.yaml` once, out-of-band
   (`oc apply -f platform/multi-tenancy/manual/<name>/`) — the one step
   that isn't automatic. Flag it explicitly in the onboarding PR/issue.

## Path B — Terraform

For teams that prefer Terraform over GitOps manifests: use
`platform/multi-tenancy/templates/terraform/modules/tenant-namespace` the
same way `environments/stage/main.tf` and `environments/prod/main.tf` do.
`terraform plan`/`apply` are run locally against a kubeconfig with cluster
access (CI only validates `fmt`/`validate`, since GitHub-hosted runners
cannot reach the private `api.lab.ocp.local` network). This path bypasses
ArgoCD, so use it only for namespaces that are intentionally
Terraform-managed rather than GitOps-managed, to avoid two controllers
fighting over the same objects.

## Path C — `oc new-project` (per-user self-service, opt-in)

See `platform/multi-tenancy/openshift/README.md`. Requires a cluster-admin
to wire a cluster-wide `projectRequestTemplate` first; every `oc new-project`
from a `self-provisioner` user then comes out pre-governed automatically.
Best fit for individual developer sandboxes rather than shared team
environments like `stage`/`prod`.

## Guardrails all three paths share

- Namespace can never exceed its `ResourceQuota` (requests/limits/pods/PVCs).
- Every container gets a `LimitRange` default if it doesn't set its own.
- `NetworkPolicy` denies all ingress/egress by default; only same-namespace,
  OpenShift router, DNS, and monitoring traffic are allowed out of the box.
- Namespace admin is scoped RBAC (`admin` ClusterRole via RoleBinding), never
  cluster-admin.
- `pod-security.kubernetes.io/enforce: restricted` on every tenant namespace.
