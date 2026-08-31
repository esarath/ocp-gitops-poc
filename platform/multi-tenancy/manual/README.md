# Manually-applied governance objects

`stage/{resourcequota,limitrange}.yaml` and `prod/{resourcequota,limitrange}.yaml`
live here, not in `../base/`, for the same reason `redis-gitops` keeps its
quota/limitrange manual (see `redis-gitops/apps/redis-platform/manual/README.md`
on this cluster): OpenShift GitOps' auto-granted namespace role for the
`argocd-application-controller` service account (created automatically for
any namespace labeled `argocd.argoproj.io/managed-by`) mirrors the
Kubernetes built-in `admin` ClusterRole, which explicitly restricts
`resourcequotas`/`limitranges` to `get/list/watch` — never `create`. That's
deliberate upstream Kubernetes RBAC design (a namespace admin can't raise
their own quota), and it applies just as much to a GitOps controller with
admin-equivalent rights as it would to a human. Confirmed on this cluster:
`tenant-stage`/`tenant-prod` Applications failed to sync with
`resourcequotas is forbidden: ... cannot create resource "resourcequotas"`
until these two object types were pulled out of the ArgoCD-managed path.

This is not routed around by widening the ArgoCD controller's RBAC — that
would defeat the exact guardrail this POC is demonstrating (a tenant,
even an automated one, must not be able to grant itself more quota).
Quota/limit governance stays a platform-team, out-of-band decision.

Apply once per tenant namespace, out-of-band, as cluster-admin:

```bash
oc apply -f platform/multi-tenancy/manual/stage/resourcequota.yaml
oc apply -f platform/multi-tenancy/manual/stage/limitrange.yaml
oc apply -f platform/multi-tenancy/manual/prod/resourcequota.yaml
oc apply -f platform/multi-tenancy/manual/prod/limitrange.yaml
```

Any new tenant onboarded via `onboarding/ONBOARDING.md` Path A needs this
same manual step repeated for its namespace — call it out explicitly in the
onboarding PR/issue so it isn't missed.
