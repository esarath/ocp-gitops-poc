# Multi-Tenancy POC — Validation

## Pre-deployment (runs in CI, `.github/workflows/validate-multi-tenancy.yaml`)

- [ ] `yamllint` passes on `platform/multi-tenancy/` and `apps/app-of-apps/`
- [ ] `kubectl kustomize` builds `base/stage`, `base/prod`, and
      `apps/app-of-apps` without error
- [ ] `kubectl apply --dry-run=client` accepts the built manifests
      (schema-valid, no cluster connectivity required)
- [ ] `kubeconform -strict` passes on the built stage/prod manifests
- [ ] `helm lint` and `helm template` succeed for the tenant-namespace chart
      with `values-stage.yaml` and `values-prod.yaml`
- [ ] `terraform fmt -check` and `terraform validate` pass for the module and
      both environment roots

## Post-deployment (run manually against the live cluster after ArgoCD sync)

Isolation:
```bash
oc get ns stage prod --show-labels
oc get networkpolicy -n stage
oc get networkpolicy -n prod

# From a throwaway pod in stage, confirm prod is unreachable and stage is reachable
oc run -n stage netcheck --rm -it --image=registry.access.redhat.com/ubi9/ubi-minimal -- \
  bash -c "curl -m3 -s -o /dev/null -w 'stage-svc: %{http_code}\n' http://<a-stage-service>.stage.svc.cluster.local || true"
oc run -n stage netcheck2 --rm -it --image=registry.access.redhat.com/ubi9/ubi-minimal -- \
  bash -c "curl -m3 -s -o /dev/null -w 'prod-svc (expect timeout): %{http_code}\n' http://<a-prod-service>.prod.svc.cluster.local || true"
```

Quota enforcement:
```bash
oc describe resourcequota -n stage
oc describe resourcequota -n prod
# Attempt to exceed pod count or unbounded resources and confirm the API server rejects it
oc run -n stage overquota --image=registry.access.redhat.com/ubi9/ubi-minimal \
  --requests='cpu=10,memory=10Gi' -- sleep 3600   # expect: forbidden, exceeds quota
```

LimitRange defaults:
```bash
oc run -n stage nolimits --image=registry.access.redhat.com/ubi9/ubi-minimal -- sleep 3600
oc get pod nolimits -n stage -o jsonpath='{.spec.containers[0].resources}'
# expect: defaults injected (250m/256Mi limits, 100m/128Mi requests for stage)
```

Onboarding workflow:
```bash
# Path A (GitOps): open a test PR adding a throwaway namespace via the Helm
# template, confirm CI goes green, then close without merging (or merge to
# a scratch namespace and delete it after).
helm template test-team platform/multi-tenancy/templates/helm/tenant-namespace \
  --set tenant.name=test-team --set tenant.environment=dev \
  --set tenant.adminGroup=test-team-admins | kubectl apply --dry-run=client -f -
```

RBAC scoping:
```bash
oc get rolebinding -n stage stage-team-admin -o yaml
oc get rolebinding -n prod prod-team-admin -o yaml
# Confirm no ClusterRoleBinding was created, and the group has no bindings
# outside its own namespace: oc get rolebinding --all-namespaces | grep stage-team
```

Observability:
```bash
# Confirm the monitoring NetworkPolicy doesn't block scraping
oc get servicemonitor,podmonitor -n stage -n prod 2>/dev/null
# If a workload exposes /metrics, confirm it shows up as a target:
oc -n openshift-user-workload-monitoring exec -it <prometheus-pod> -- \
  curl -s localhost:9090/api/v1/targets | grep -A2 '"stage"\|"prod"'
```

## Sign-off

Both namespaces `Synced`/`Healthy` in ArgoCD, all checks above pass, and no
`Warning` events on quota/limitrange objects in `oc get events -n stage -n
prod`.
