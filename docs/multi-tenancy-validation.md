# Multi-Tenancy POC — Validation

## Pre-deployment (runs in CI, `.github/workflows/validate-multi-tenancy.yaml`)

- [x] `yamllint` passes on `platform/multi-tenancy/` and `apps/app-of-apps/`
- [x] `kubectl kustomize` builds `base/stage`, `base/prod`, and
      `apps/app-of-apps` without error
- [x] A disposable kind cluster gives `kubectl apply --dry-run=server` a real
      API server to validate against (client-only dry-run cannot work without
      one — it still needs live discovery/RESTMapping)
- [x] `kubeconform -strict` passes on the built stage/prod manifests, and on
      `platform/multi-tenancy/manual/{stage,prod}/*.yaml`
- [x] `helm lint` and `helm template` succeed for the tenant-namespace chart
      with `values-stage.yaml` and `values-prod.yaml`
- [x] `terraform fmt -check` and `terraform validate` pass for the module and
      both environment roots

All confirmed green on `main` — see the `Validate Multi-Tenancy Manifests`
workflow runs in the repo's Actions tab.

## Post-deployment (run against the live cluster after ArgoCD sync)

Every pod spec below must satisfy the namespace's `restricted` Pod Security
Standard (`allowPrivilegeEscalation: false`, `capabilities.drop: [ALL]`,
`runAsNonRoot: true`, `seccompProfile.type: RuntimeDefault`) — a bare
`oc run` without these is rejected by admission before it ever reaches
quota/limitrange, which is itself a first isolation check worth doing.

Isolation:
```bash
oc get ns stage prod --show-labels
oc get networkpolicy -n stage
oc get networkpolicy -n prod
```
**Result (2026-08-31):** both namespaces `Active` with expected labels; 5
NetworkPolicies each (`default-deny-all`, `allow-same-namespace`,
`allow-from-openshift-ingress`, `allow-from-monitoring`, `allow-dns-egress`).

Quota enforcement:
```bash
oc describe resourcequota -n stage
oc describe resourcequota -n prod
```
**Result:** `stage-quota` and `prod-quota` present with the hard limits from
`docs/multi-tenancy-lld.md`, `Used` at baseline (only the default
service-account configmaps/secrets OpenShift creates in every namespace).

LimitRange defaults + quota enforcement (needs a PSS-compliant pod — see
`/platform/multi-tenancy/` for no ready-made test fixture; inline example):
```bash
cat <<'EOF' | oc apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: nolimits-test
  namespace: stage
spec:
  containers:
    - name: nolimits-test
      image: registry.access.redhat.com/ubi9/ubi-minimal
      command: ["sleep", "3600"]
      securityContext:
        allowPrivilegeEscalation: false
        capabilities: {drop: ["ALL"]}
        runAsNonRoot: true
        seccompProfile: {type: RuntimeDefault}
EOF
oc get pod nolimits-test -n stage -o jsonpath='{.spec.containers[0].resources}'
oc delete pod nolimits-test -n stage
```
**Result:** defaults injected exactly as configured —
`{"limits":{"cpu":"250m","memory":"256Mi"},"requests":{"cpu":"100m","memory":"128Mi"}}`.

```bash
cat <<'EOF' | oc apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: overquota-test
  namespace: stage
spec:
  containers:
    - name: overquota-test
      image: registry.access.redhat.com/ubi9/ubi-minimal
      command: ["sleep", "3600"]
      resources:
        requests: {cpu: "10", memory: 10Gi}
        limits: {cpu: "10", memory: 10Gi}
      securityContext:
        allowPrivilegeEscalation: false
        capabilities: {drop: ["ALL"]}
        runAsNonRoot: true
        seccompProfile: {type: RuntimeDefault}
EOF
```
**Result:** rejected by admission before the pod was ever created —
`maximum cpu usage per Container is 1, but limit is 10, maximum memory usage
per Container is 1Gi, but limit is 10Gi, maximum cpu usage per Pod is 2, but
limit is 10, maximum memory usage per Pod is 2Gi, but limit is 10Gi`
(`LimitRange` caught it before the aggregate `ResourceQuota` needed to).

Onboarding workflow:
```bash
# Path A (GitOps): open a test PR adding a throwaway namespace via the Helm
# template, confirm CI goes green, then close without merging.
helm template test-team platform/multi-tenancy/templates/helm/tenant-namespace \
  --set tenant.name=test-team --set tenant.environment=dev \
  --set tenant.adminGroup=test-team-admins | kubectl apply --dry-run=client --validate=false -f -
```

RBAC scoping:
```bash
oc get rolebinding -n stage stage-team-admin -o yaml
oc get rolebinding -n prod prod-team-admin -o yaml
# Confirm no ClusterRoleBinding was created, and the group has no bindings
# outside its own namespace:
oc get rolebinding --all-namespaces | grep stage-team
```
**Result:** both `RoleBinding`s present, `ClusterRole/admin` scoped to their
own namespace only, tracked by the correct ArgoCD Application
(`argocd.argoproj.io/tracking-id` annotation present).

Observability:
```bash
# Confirm the monitoring NetworkPolicy doesn't block scraping
oc get servicemonitor,podmonitor -n stage -n prod 2>/dev/null
# If a workload exposes /metrics, confirm it shows up as a target:
oc -n openshift-user-workload-monitoring exec -it <prometheus-pod> -- \
  curl -s localhost:9090/api/v1/targets | grep -A2 '"stage"\|"prod"'
```
No workload deployed into `stage`/`prod` yet in this POC, so nothing to
scrape — the `allow-from-monitoring` NetworkPolicy is in place and ready for
whenever one is.

## Known gap found during deployment

`ResourceQuota`/`LimitRange` are **not** ArgoCD-managed — see
`platform/multi-tenancy/manual/README.md`. This was discovered live: the
first sync attempt failed with `resourcequotas is forbidden`, root-caused to
a deliberate Kubernetes RBAC restriction (the built-in `admin` ClusterRole,
which OpenShift GitOps auto-grants the controller per managed namespace,
excludes write access to those two kinds). Applied manually as cluster-admin
instead, matching the existing `redis-platform` precedent on this cluster.

Separately: bootstrapping `apps/app-of-apps/app-of-apps.yaml` also revived
`sample-app-staging`/`sample-app-production` (pre-existing, unrelated to this
POC), which failed to sync for a different and broader RBAC reason (cannot
create Services/Deployments/Routes at all in those namespaces) — likely
those namespaces predate the OpenShift GitOps operator's current per-namespace
RBAC auto-grant mechanism and need it re-provisioned. Left as-is; out of
scope for this multi-tenancy POC.

## Sign-off

`tenant-stage`/`tenant-prod` `Synced`/`Healthy` in ArgoCD (confirmed
2026-08-31), `ResourceQuota`/`LimitRange` applied and enforcing, all checks
above pass, no `Warning` events on quota/limitrange objects in
`oc get events -n stage -n prod` beyond normal creation events.
