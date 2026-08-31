# Walkthrough: Onboard redis-app/redis-db into `stage` via ArgoCD

A concrete, manually-run instance of onboarding Path A
(`ONBOARDING.md`) — deploying a real workload into the `stage` tenant
namespace to prove the multi-tenancy scaffold (quota, limits, network
isolation, scoped RBAC) actually holds up end to end, not just that the
namespace exists.

**Run this yourself, step by step** — nothing here is applied automatically.
`app-of-apps` on the live cluster already has `automated: {prune: true,
selfHeal: true}`, so **do not** commit the Application/kustomization wiring
in Steps 3/6 until you're ready for ArgoCD to actually deploy it — the
moment it lands on `main`, it syncs.

Numbers below (quota headroom, node CPU capacity) were checked live against
`api.lab.ocp.local` on 2026-08-31 — re-check if it's been a while
(`oc describe resourcequota stage-quota -n stage`, `oc describe nodes
worker-1.lab.ocp.local worker-2.lab.ocp.local | grep -A3 "Allocated
resources"`).

## Prerequisites

- `stage` namespace already exists and is ArgoCD-managed (`tenant-stage`
  Application) with `stage-quota`/`stage-limits` applied — see
  `platform/multi-tenancy/base/stage/` and `manual/stage/`. Confirm:
  ```bash
  oc get application tenant-stage -n openshift-gitops
  oc get resourcequota,limitrange -n stage
  ```
- Push access to `https://github.com/esarath/ocp-gitops-poc.git`, `oc`/`kubectl`
  pointed at a cluster-admin-capable context (needed for Step 1 and the
  manual Secret in Step 4).
- Current headroom used for the sizing below: `stage-quota` has
  `requests.cpu: 0/1`, `requests.memory: 0/1Gi` used; both worker nodes have
  several hundred `m` CPU free. The sizing chosen (Step 2) fits comfortably
  either way — resize if your situation has changed.

## Step 1 — Widen the `multi-tenancy` AppProject

`apps/app-of-apps/multi-tenancy-project.yaml` currently only whitelists
core (`''`), `NetworkPolicy`, and `RoleBinding` — enough for the namespace
scaffold, **not enough for an actual workload** (`Deployment`,
`StatefulSet`, `HorizontalPodAutoscaler`, `PodDisruptionBudget` are all
different API groups). Without this step, ArgoCD will reject the sync with
`... is not permitted in project 'multi-tenancy'`.

Edit `apps/app-of-apps/multi-tenancy-project.yaml`, add three entries to
`namespaceResourceWhitelist`:

```yaml
  namespaceResourceWhitelist:
    - group: ''
      kind: '*'
    - group: networking.k8s.io
      kind: NetworkPolicy
    - group: rbac.authorization.k8s.io
      kind: RoleBinding
    - group: apps
      kind: '*'
    - group: autoscaling
      kind: '*'
    - group: policy
      kind: '*'
```

This is a real, permanent platform decision (any future tenant workload
needs it, not just this test) — safe to commit and push on its own first,
separately from Steps 3/6:

```bash
cd ~/git/ocp-gitops-poc
git add apps/app-of-apps/multi-tenancy-project.yaml
git commit -m "feat: allow apps/autoscaling/policy kinds in multi-tenancy AppProject"
git push
```

ArgoCD will pick this up on its own via `app-of-apps`'s existing automated
sync (AppProject changes alone don't deploy any workload, so this is safe to
let sync immediately). Confirm:

```bash
oc get appproject multi-tenancy -n openshift-gitops -o yaml | grep -A10 namespaceResourceWhitelist
```

## Step 2 — Write the manifests (don't commit yet)

Create `platform/multi-tenancy/examples/redis-stage/` with the files below.
Sized to fit comfortably inside `stage-quota` (1 CPU / 1Gi requests total)
and `stage-limits` (1 CPU / 1Gi max per container) with a lot of headroom
left for anything else.

`platform/multi-tenancy/examples/redis-stage/kustomization.yaml`:
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - redis-app-deployment.yaml
  - redis-app-service.yaml
  - redis-db-statefulset.yaml
  - redis-db-service.yaml
  - redis-db-hpa.yaml
  - redis-db-pdb.yaml
```

`platform/multi-tenancy/examples/redis-stage/redis-app-deployment.yaml`:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: redis-app
  namespace: stage
  labels:
    app: redis-app
spec:
  replicas: 1
  selector:
    matchLabels:
      app: redis-app
  template:
    metadata:
      labels:
        app: redis-app
    spec:
      containers:
        - name: redis-app
          image: docker.io/bitnamilegacy/redis:7.2.5-debian-12-r6
          ports:
            - containerPort: 6379
          env:
            - name: REDIS_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: redis-stage-auth
                  key: redis-password
          resources:
            requests: { cpu: 100m, memory: 128Mi }
            limits: { cpu: 250m, memory: 256Mi }
          securityContext:
            allowPrivilegeEscalation: false
            capabilities: { drop: ["ALL"] }
            runAsNonRoot: true
            seccompProfile: { type: RuntimeDefault }
```

`platform/multi-tenancy/examples/redis-stage/redis-app-service.yaml`:
```yaml
apiVersion: v1
kind: Service
metadata:
  name: redis-app
  namespace: stage
spec:
  selector:
    app: redis-app
  ports:
    - port: 6379
      targetPort: 6379
```

`platform/multi-tenancy/examples/redis-stage/redis-db-statefulset.yaml`:
```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: redis-db
  namespace: stage
spec:
  serviceName: redis-db
  replicas: 1
  selector:
    matchLabels:
      app: redis-db
  template:
    metadata:
      labels:
        app: redis-db
    spec:
      containers:
        - name: redis-db
          image: docker.io/bitnamilegacy/redis:7.2.5-debian-12-r6
          ports:
            - containerPort: 6379
          env:
            - name: REDIS_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: redis-stage-auth
                  key: redis-password
            - name: REDIS_AOF_ENABLED
              value: "yes"
          resources:
            requests: { cpu: 100m, memory: 128Mi }
            limits: { cpu: 250m, memory: 256Mi }
          securityContext:
            allowPrivilegeEscalation: false
            capabilities: { drop: ["ALL"] }
            runAsNonRoot: true
            seccompProfile: { type: RuntimeDefault }
          volumeMounts:
            - name: data
              mountPath: /bitnami/redis/data
          livenessProbe:
            exec:
              command: ["redis-cli", "-a", "$(REDIS_PASSWORD)", "--no-auth-warning", "ping"]
            initialDelaySeconds: 15
            periodSeconds: 10
  volumeClaimTemplates:
    - metadata:
        name: data
      spec:
        accessModes: ["ReadWriteOnce"]
        storageClassName: nfs-storage
        resources: { requests: { storage: 2Gi } }
```
(2Gi, not the original 10Gi — this is a throwaway verification test, not
a real workload; `stage-quota` allows up to 5 PVCs but doesn't cap storage
size itself, so keep it small on purpose.)

`platform/multi-tenancy/examples/redis-stage/redis-db-service.yaml`:
```yaml
apiVersion: v1
kind: Service
metadata:
  name: redis-db
  namespace: stage
spec:
  clusterIP: None
  selector:
    app: redis-db
  ports:
    - port: 6379
      targetPort: 6379
```

`platform/multi-tenancy/examples/redis-stage/redis-db-hpa.yaml`:
```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: redis-db
  namespace: stage
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: StatefulSet
    name: redis-db
  minReplicas: 1
  maxReplicas: 2
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 50
```

`platform/multi-tenancy/examples/redis-stage/redis-db-pdb.yaml`:
```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: redis-db
  namespace: stage
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: redis-db
```

Notice what's **not** here: no new `NetworkPolicy`. `stage`'s existing
`allow-same-namespace` policy (from the onboarding scaffold) already lets
`redis-app` and `redis-db` pods talk to each other — proving the isolation
model composes with real workloads instead of needing per-app tweaks.

Validate before committing anything:
```bash
kubectl kustomize platform/multi-tenancy/examples/redis-stage
kubectl kustomize platform/multi-tenancy/examples/redis-stage | kubectl apply --dry-run=server -f -
```

## Step 3 — Wire the ArgoCD Application (don't push yet — see Step 6)

`apps/app-of-apps/stage-redis-test.yaml`:
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: stage-redis-test
  namespace: openshift-gitops
  labels:
    app.kubernetes.io/part-of: multi-tenancy
    environment: stage
spec:
  project: multi-tenancy
  source:
    repoURL: https://github.com/esarath/ocp-gitops-poc.git
    targetRevision: main
    path: platform/multi-tenancy/examples/redis-stage
  destination:
    server: https://kubernetes.default.svc
    namespace: stage
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=false
      - PruneLast=true
    retry:
      limit: 3
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
```

Add it to `apps/app-of-apps/kustomization.yaml`:
```yaml
resources:
  - project.yaml
  - sample-app-staging.yaml
  - sample-app-production.yaml
  - multi-tenancy-project.yaml
  - stage-namespace.yaml
  - prod-namespace.yaml
  - stage-redis-test.yaml
```

## Step 4 — Create the auth Secret manually (not Git-tracked)

Matches the established convention in this environment (`redis-app-auth`/
`redis-db-auth` in `redis-platform` were never committed to Git either —
see `redis-gitops/apps/redis-platform/manual/README.md` for the same
reasoning applied to quota/limitrange). Pick your own password:

```bash
oc create secret generic redis-stage-auth -n stage \
  --from-literal=redis-password='<choose-a-password>'
```

## Step 5 — Sanity-check everything client-side first

```bash
kubectl kustomize apps/app-of-apps | kubectl apply --dry-run=server -f -
```
This should succeed cleanly (Step 1's AppProject change plus the new
Application/kustomization edit, dry-run only — nothing is created yet since
you haven't pushed).

## Step 6 — Commit and push (this is the deploy trigger)

```bash
cd ~/git/ocp-gitops-poc
git add platform/multi-tenancy/examples/redis-stage apps/app-of-apps/stage-redis-test.yaml apps/app-of-apps/kustomization.yaml
git commit -m "feat: onboard redis-app/redis-db test workload into stage"
git push
```

`app-of-apps`'s automated sync picks up the new `Application` within its
normal poll interval (or force it immediately):
```bash
oc patch application app-of-apps -n openshift-gitops --type merge \
  -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'
sleep 15
oc get application stage-redis-test -n openshift-gitops
```

## Step 7 — Verify onboarding actually worked end to end

**Workload came up:**
```bash
oc get application stage-redis-test -n openshift-gitops -o custom-columns='SYNC:.status.sync.status,HEALTH:.status.health.status'
oc get pods -n stage
```

**Quota is actually tracking usage** (proves governance isn't just present,
it's live):
```bash
oc describe resourcequota stage-quota -n stage
# expect requests.cpu/memory > 0 now, still well under hard limits
```

**Redis actually works:**
```bash
oc exec -n stage redis-app-<pod-suffix> -- redis-cli -a '<password>' --no-auth-warning ping
# expect: PONG
```

**Network isolation still holds with a real workload in place** — try
reaching `stage`'s redis from `prod` (should time out/fail):
```bash
oc run -n prod netcheck --rm -it --restart=Never \
  --image=registry.access.redhat.com/ubi9/ubi-minimal \
  --overrides='{"spec":{"containers":[{"name":"netcheck","image":"registry.access.redhat.com/ubi9/ubi-minimal","command":["sleep","3600"],"securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"runAsNonRoot":true,"seccompProfile":{"type":"RuntimeDefault"}}}]}}' \
  -- bash -c "timeout 3 bash -c '</dev/tcp/redis-app.stage.svc.cluster.local/6379' && echo REACHABLE || echo BLOCKED (expected)"
```
Then confirm it *is* reachable from inside `stage` itself:
```bash
oc run -n stage netcheck --rm -it --restart=Never \
  --image=registry.access.redhat.com/ubi9/ubi-minimal \
  --overrides='{"spec":{"containers":[{"name":"netcheck","image":"registry.access.redhat.com/ubi9/ubi-minimal","command":["sleep","3600"],"securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"runAsNonRoot":true,"seccompProfile":{"type":"RuntimeDefault"}}}]}}' \
  -- bash -c "timeout 3 bash -c '</dev/tcp/redis-app.stage.svc.cluster.local/6379' && echo REACHABLE (expected) || echo BLOCKED"
```

**RBAC self-service scope is correct** — a `stage-team` member can act in
`stage` but not `prod`, without cluster-admin (no real user account needed,
`--as`/`--as-group` impersonation proves the RBAC shape):
```bash
oc auth can-i create deployments -n stage --as=test-user --as-group=stage-team   # yes
oc auth can-i create deployments -n prod  --as=test-user --as-group=stage-team   # no
oc auth can-i delete resourcequotas -n stage --as=test-user --as-group=stage-team  # no (see manual/README.md)
```

If every check above comes back as expected, the multi-tenancy self-service
onboarding flow is proven end to end: a real workload, deployed the same
way any tenant would, landed correctly-quota'd, correctly-isolated, and
correctly-scoped — using nothing but a Git PR and (for the Secret) one
manual command.

## Cleanup (when you're done testing)

```bash
oc patch application stage-redis-test -n openshift-gitops --type merge \
  -p '{"metadata":{"finalizers":["resources-finalizer.argocd.argoproj.io"]}}'
oc delete application stage-redis-test -n openshift-gitops --wait=true
oc delete secret redis-stage-auth -n stage
oc delete pvc -n stage -l app=redis-db   # StatefulSet PVCs always outlive it, same as redis-db-teardown.md
```
Then remove `platform/multi-tenancy/examples/redis-stage/` and
`apps/app-of-apps/stage-redis-test.yaml`, drop the line from
`apps/app-of-apps/kustomization.yaml`, commit, push.
