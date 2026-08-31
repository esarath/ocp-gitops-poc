# Walkthrough: Onboard redis-app/redis-db into `stage` via ArgoCD

A concrete, manually-run instance of onboarding Path A
(`ONBOARDING.md`) — deploying a real workload into the `stage` tenant
namespace to prove the multi-tenancy scaffold (quota, limits, network
isolation, scoped RBAC) actually holds up end to end, not just that the
namespace exists.

**Status: executed and fully verified against `api.lab.ocp.local` on
2026-08-31.** Every command below was actually run, in order, one step at a
time; each step's **Executed — result:** block shows the real command and
real output captured at the time, not a predicted/expected one. This is
both a runnable guide (re-run it fresh for a future tenant/namespace) and
the audit trail of this specific run — `stage-redis-test` is currently
`Synced`/`Healthy` with `redis-app` (Deployment, 1/1) and `redis-db`
(StatefulSet, 1/1) live in `stage` as a result.

**How it was run** — step by step, not all at once. `app-of-apps` on the
live cluster already has `automated: {prune: true, selfHeal: true}`, so
Steps 1–5 were deliberately kept as local, uncommitted changes (validated
with `kubectl apply --dry-run=server` against the real API server each
time, but nothing pushed) until Step 6 — the single point where `git push`
actually triggers ArgoCD to deploy anything.

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

**Executed — result:** validated locally first (`kubectl kustomize
apps/app-of-apps` built cleanly, `kubectl apply --dry-run=server`
succeeded), committed as `b1cd311` ("feat: allow apps/autoscaling/policy
kinds in multi-tenancy AppProject"), pushed, CI (`validate-multi-tenancy.yaml`)
green. Forced an immediate refresh instead of waiting for the poll interval:
```bash
oc patch application app-of-apps -n openshift-gitops --type merge \
  -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'
```
`app-of-apps` synced to revision `b1cd311` within ~20s. Confirmed live:
```
$ oc get appproject multi-tenancy -n openshift-gitops -o jsonpath='{.spec.namespaceResourceWhitelist}'
[{"group":"","kind":"*"},{"group":"networking.k8s.io","kind":"NetworkPolicy"},
 {"group":"rbac.authorization.k8s.io","kind":"RoleBinding"},{"group":"apps","kind":"*"},
 {"group":"autoscaling","kind":"*"},{"group":"policy","kind":"*"}]
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

**Executed — result:** all six files written to
`platform/multi-tenancy/examples/redis-stage/`, still untracked in Git
(`git status` showed only `?? platform/multi-tenancy/examples/`).
`kubectl kustomize` built cleanly. `kubectl apply --dry-run=server` (real
API-server admission validation, non-mutating) against `api.lab.ocp.local`:
```
service/redis-app created (server dry run)
service/redis-db created (server dry run)
deployment.apps/redis-app created (server dry run)
statefulset.apps/redis-db created (server dry run)
poddisruptionbudget.policy/redis-db created (server dry run)
horizontalpodautoscaler.autoscaling/redis-db created (server dry run)
```
All six accepted, nothing actually created.

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

**Executed — result:** both files written locally, still uncommitted.
`kubectl kustomize apps/app-of-apps` built cleanly with the new Application
included, `yamllint` passed. `git status` confirmed nothing staged yet
(`M kustomization.yaml`, `?? stage-redis-test.yaml`).

## Step 4 — Create the auth Secret manually (not Git-tracked)

Matches the established convention in this environment (`redis-app-auth`/
`redis-db-auth` in `redis-platform` were never committed to Git either —
see `redis-gitops/apps/redis-platform/manual/README.md` for the same
reasoning applied to quota/limitrange). Pick your own password:

```bash
oc create secret generic redis-stage-auth -n stage \
  --from-literal=redis-password='<choose-a-password>'
```

**Executed — result:** generated with `openssl rand -base64 24 | tr -d
'=+/' | cut -c1-24` rather than a hand-typed password (this doc
deliberately never records the actual value — it lives only in the
cluster's `redis-stage-auth` Secret, same as `redis-app-auth`/`redis-db-auth`
in `redis-platform`). Confirmed:
```
$ oc get secret redis-stage-auth -n stage
NAME               TYPE     DATA   AGE
redis-stage-auth   Opaque   1      6s
$ oc get secret redis-stage-auth -n stage -o jsonpath='{.metadata.annotations}'
                                          # empty — no argocd.argoproj.io/tracking-id, confirming it's NOT ArgoCD-managed
```
`stage-quota`'s `secrets` usage ticked `3 → 4`, well under its `20` limit.

## Step 5 — Sanity-check everything client-side first

```bash
kubectl kustomize apps/app-of-apps | kubectl apply --dry-run=server -f -
```
This should succeed cleanly (Step 1's AppProject change plus the new
Application/kustomization edit, dry-run only — nothing is created yet since
you haven't pushed).

**Executed — result:**
```
appproject.argoproj.io/multi-tenancy configured (server dry run)
appproject.argoproj.io/sample-app configured (server dry run)
application.argoproj.io/sample-app-production configured (server dry run)
application.argoproj.io/sample-app-staging configured (server dry run)
application.argoproj.io/stage-redis-test created (server dry run)
application.argoproj.io/tenant-prod configured (server dry run)
application.argoproj.io/tenant-stage configured (server dry run)
```
The meaningful line: `stage-redis-test` shows `created` (genuinely new),
everything else `configured` (already exists, unchanged) — confirming the
new Application really is new and would deploy cleanly. Double-checked
nothing actually happened: `oc get application stage-redis-test -n
openshift-gitops` still returned `NotFound`, `stage` namespace still empty.

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

**Executed — result:** staged exactly the three expected paths
(`git status` showed `M kustomization.yaml`, plus 8 new files — the
Application and the six `examples/redis-stage/` manifests), committed as
`7787220` ("feat: onboard redis-app/redis-db test workload into stage"),
pushed, CI green. Forced the refresh:
```
$ oc get application stage-redis-test -n openshift-gitops
NAME               SYNC STATUS   HEALTH STATUS
stage-redis-test   Synced        Progressing
```
Within another ~60s it settled to `Synced` / `Healthy`.

## Step 7 — Verify onboarding actually worked end to end

**Workload came up:**
```bash
oc get application stage-redis-test -n openshift-gitops -o custom-columns='SYNC:.status.sync.status,HEALTH:.status.health.status'
oc get pods -n stage
```
**Result:**
```
NAME               SYNC     HEALTH
stage-redis-test   Synced   Healthy

NAME                         READY   STATUS    RESTARTS   AGE
redis-app-854b49975f-csqdr   1/1     Running   0          54s
redis-db-0                   1/1     Running   0          54s
```
`deployment.apps/redis-app` `1/1`, `statefulset.apps/redis-db` `1/1`, HPA
already reporting real metrics (`cpu: 3%/50%`, not `<unknown>` — confirms
metrics-server is working for this workload from the start), PDB active
with `MIN AVAILABLE 1`.

**Quota is actually tracking usage** (proves governance isn't just present,
it's live):
```bash
oc describe resourcequota stage-quota -n stage
```
**Result:**
```
Resource                Used   Hard
--------                ----   ----
count/deployments.apps  1      10
persistentvolumeclaims  1      5
pods                    2      10
requests.cpu            200m   1
requests.memory         256Mi  1Gi
limits.cpu              500m   2
limits.memory           512Mi  2Gi
secrets                 4      20
services                2      10
```
Matches exactly what the two containers declared (100m+100m requests,
250m+250m limits) — quota tracking real consumption, comfortably inside
every hard limit.

**Redis actually works:**
```bash
oc exec -n stage deployment/redis-app -- redis-cli -a '<password>' --no-auth-warning ping
oc exec -n stage redis-db-0 -- redis-cli -a '<password>' --no-auth-warning ping
```
**Result:** `PONG` from both — the app tier and the db tier are each
independently running real Redis, correctly reading `REDIS_PASSWORD` from
the manually-created `redis-stage-auth` Secret.

**Network isolation still holds with a real workload in place** — reaching
`stage`'s redis from `prod` (should fail) vs. from `stage` itself (should
work):
```bash
oc run -n prod netcheck-blocked --rm -i --restart=Never \
  --image=registry.access.redhat.com/ubi9/ubi-minimal \
  --overrides='{"spec":{"containers":[{"name":"netcheck-blocked","image":"registry.access.redhat.com/ubi9/ubi-minimal","command":["bash","-c","timeout 5 bash -c \"</dev/tcp/redis-app.stage.svc.cluster.local/6379\" && echo REACHABLE || echo BLOCKED"],"securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"runAsNonRoot":true,"seccompProfile":{"type":"RuntimeDefault"}}}]}}'

oc run -n stage netcheck-allowed --rm -i --restart=Never \
  --image=registry.access.redhat.com/ubi9/ubi-minimal \
  --overrides='{"spec":{"containers":[{"name":"netcheck-allowed","image":"registry.access.redhat.com/ubi9/ubi-minimal","command":["bash","-c","timeout 5 bash -c \"</dev/tcp/redis-app.stage.svc.cluster.local/6379\" && echo REACHABLE || echo BLOCKED"],"securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"runAsNonRoot":true,"seccompProfile":{"type":"RuntimeDefault"}}}]}}'
```
**Result:** `prod → stage`: `BLOCKED`. `stage → stage`: `REACHABLE`. Exactly
as designed — `default-deny-all` + `allow-same-namespace` in `stage`
isolates it from every other tenant, including a namespace (`prod`) that
also legitimately exists on this same multi-tenancy platform.

**RBAC self-service scope is correct** — a `stage-team` member can act in
`stage` but not `prod`, without cluster-admin (no real user account needed,
`--as`/`--as-group` impersonation proves the RBAC shape):
```bash
oc auth can-i create deployments -n stage --as=test-user --as-group=stage-team
oc auth can-i create deployments -n prod  --as=test-user --as-group=stage-team
oc auth can-i delete resourcequotas -n stage --as=test-user --as-group=stage-team
```
**Result:** `yes`, `no`, `no` — exactly as designed. `stage-team` can
self-manage workloads in `stage`, cannot touch `prod`, and cannot raise its
own quota (that stays a platform-team, out-of-band decision — see
`manual/README.md`).

**Conclusion: every check passed.** The multi-tenancy self-service
onboarding flow is proven end to end on this cluster — a real workload,
deployed the same way any tenant would, landed correctly-quota'd,
correctly-isolated, and correctly-scoped, using nothing but a Git PR and
(for the Secret) one manual command.

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
