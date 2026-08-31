# tenant-namespace (Helm project template)

Self-service Helm chart that provisions one fully isolated tenant namespace:
`Namespace` + `ResourceQuota` + `LimitRange` + baseline `NetworkPolicy` set +
a namespace-scoped `admin` `RoleBinding` for the tenant's own group.

This is the reusable template referenced by the onboarding process in
`platform/multi-tenancy/onboarding/ONBOARDING.md`. `stage` and `prod` in
`platform/multi-tenancy/base/` are this chart's output, committed as static
manifests so ArgoCD has a plain-YAML source of truth.

## Usage

```bash
# Preview a new tenant
helm template team-x . -f values.yaml \
  --set tenant.name=team-x \
  --set tenant.environment=dev \
  --set tenant.adminGroup=team-x-admins

# Or with a checked-in values file (recommended — keep it in the PR)
helm template stage . -f values-stage.yaml
helm template prod . -f values-prod.yaml
```

`helm lint .` and `helm template` (schema/rendering only, no cluster
connectivity) are what CI runs in `validate-multi-tenancy.yaml`.
