# Step-by-Step: Deploy Sample App with CI/CD

## Overview - What happens end-to-end

```
You push code → GitHub Actions builds image → Pushes to ghcr.io → Updates manifest → ArgoCD detects change → Deploys to OpenShift
```

---

## Step 1: Create GitHub Repository

1. Go to https://github.com/new
2. Repository name: `ocp-gitops-poc`
3. Visibility: **Public** (ArgoCD needs to read it; private requires extra auth setup)
4. Do NOT initialize with README (we already have one)
5. Click **Create repository**

## Step 2: Push Local Repo to GitHub

Open your terminal and run:
```bash
cd C:\Users\babus16\ocp-gitops-poc
git remote add origin https://github.com/esarath/ocp-gitops-poc.git
git push -u origin main
```
You may be prompted for GitHub credentials. Use a **Personal Access Token** (not password):
- Go to https://github.com/settings/tokens → Generate new token (classic)
- Select scopes: `repo` (full control)
- Copy the token and use it as your password

## Step 3: Configure GitHub Actions Workflow Permissions

1. Go to `https://github.com/esarath/ocp-gitops-poc/settings/actions`
2. Scroll to **Workflow permissions**
3. Select **"Read and write permissions"**
4. Check **"Allow GitHub Actions to create and approve pull requests"**
5. Click **Save**

> **Why?** The CI workflow uses `GITHUB_TOKEN` to push images to ghcr.io and commit
> manifest updates. This requires write access to both packages and contents.

## Step 4: (No External Secrets Needed)

Unlike Quay.io, **ghcr.io uses the built-in `GITHUB_TOKEN`** for authentication.
No external secrets, robot accounts, or encrypted passwords are needed.

The CI workflow authenticates using:
```yaml
username: ${{ github.actor }}
password: ${{ secrets.GITHUB_TOKEN }}
```

Your image will be at: `ghcr.io/esarath/sample-app`

## Step 5: (Reserved - No Action Needed)

> **Note**: Previously this step configured Quay.io secrets (`QUAY_USERNAME`/`QUAY_PASSWORD`).
> With ghcr.io, `GITHUB_TOKEN` is automatically available - no manual secrets required.

## Step 6: Trigger the First CI Build

The CI pipeline triggers on pushes to `main` that change files in `sample-app/`.

Make a small change to trigger it:
```bash
cd C:\Users\babus16\ocp-gitops-poc

# Add a version comment to the app
echo "" >> sample-app/src/app.py
git add sample-app/src/app.py
git commit -m "trigger: initial CI build"
git push
```

### Monitor the build:
1. Go to https://github.com/esarath/ocp-gitops-poc/actions
2. You should see a workflow run starting
3. Click on it to watch the progress:
   - **test** job: installs dependencies, runs pytest
   - **build-and-push** job: builds Docker image, pushes to ghcr.io
   - **update-manifests** job: updates staging image tag in the repo

The workflow takes ~1-3 minutes.

### If the build succeeds:
- Image will be at: `ghcr.io/esarath/sample-app:<commit-sha>`
- The staging kustomization.yaml will be auto-updated with the new image tag
- ArgoCD will detect the change and deploy it

## Step 7: Make the Container Package Public

> **IMPORTANT**: ghcr.io packages are **private by default**. OpenShift cannot pull
> private images without pull secrets.

1. Go to `https://github.com/users/esarath/packages/container/sample-app/settings`
2. Scroll to **Danger Zone**
3. Click **"Change visibility"**
4. Select **"Public"** and confirm

### Verify Image on ghcr.io
1. Go to `https://github.com/esarath?tab=packages`
2. Click on `sample-app`
3. You should see tags: `latest` and a 7-character SHA tag (e.g., `0a96677`)

## Step 8: Configure ArgoCD to Access Your GitHub Repo

Since the repo is public, ArgoCD can read it without credentials. But we need to
register it:

### Option A: Via ArgoCD CLI (from svc-infra)
```bash
# SSH to the cluster
ssh root@192.168.29.2
ssh centos@192.168.29.10

# Login to ArgoCD CLI
argocd login openshift-gitops-server-openshift-gitops.apps.lab.ocp.local \
  --username admin \
  --password EvRtK9IjMU3HhPqGpiA1Jea6nrc0TwlL \
  --insecure

# Add the repo
argocd repo add https://github.com/esarath/ocp-gitops-poc.git
```

### Option B: Via ArgoCD Web UI
1. Open https://openshift-gitops-server-openshift-gitops.apps.lab.ocp.local
2. Login: `admin` / `EvRtK9IjMU3HhPqGpiA1Jea6nrc0TwlL`
3. Go to **Settings** (gear icon, left sidebar) → **Repositories**
4. Click **+ Connect Repo**
5. Method: **VIA HTTPS**
6. Repository URL: `https://github.com/esarath/ocp-gitops-poc.git`
7. Click **Connect**

## Step 9: Deploy the App-of-Apps

This is the master ArgoCD Application that manages all other applications.

```bash
# From svc-infra (already SSH'd in)
oc apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: app-of-apps
  namespace: openshift-gitops
spec:
  project: default
  source:
    repoURL: https://github.com/esarath/ocp-gitops-poc.git
    targetRevision: main
    path: apps/app-of-apps
  destination:
    server: https://kubernetes.default.svc
    namespace: openshift-gitops
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF
```

### What this creates:
```
app-of-apps (root)
├── AppProject: sample-app
├── Application: sample-app-staging    → deploys to sample-app-staging namespace
└── Application: sample-app-production → deploys to sample-app-production namespace
```

## Step 10: Watch ArgoCD Deploy

### In the ArgoCD Web UI:
1. Open https://openshift-gitops-server-openshift-gitops.apps.lab.ocp.local
2. You'll see 3 applications appear:
   - `app-of-apps` — should be **Synced/Healthy**
   - `sample-app-staging` — will sync and deploy
   - `sample-app-production` — will sync and deploy
3. Click on `sample-app-staging` to see the resource tree:
   - Deployment → ReplicaSet → Pod
   - Service
   - ConfigMap
   - Route

### Via CLI:
```bash
oc get applications -n openshift-gitops
oc get pods -n sample-app-staging
oc get pods -n sample-app-production
```

## Step 11: Test the Application

```bash
# Staging
curl -sk https://sample-app-sample-app-staging.apps.lab.ocp.local
# Expected: {"app":"sample-app","environment":"staging","version":"1.0.0"}

# Production
curl -sk https://sample-app-sample-app-production.apps.lab.ocp.local
# Expected: {"app":"sample-app","environment":"production","version":"1.0.0"}
```

## Step 12: Test the Full CI/CD Loop

Now make a real code change and watch the entire pipeline:

### 1. Edit the app
```bash
cd C:\Users\babus16\ocp-gitops-poc
```
Edit `sample-app/src/app.py` — change the index route to add a message:
```python
@app.route("/")
def index():
    return jsonify({
        "app": "sample-app",
        "version": os.getenv("APP_VERSION", "1.0.0"),
        "environment": os.getenv("APP_ENV", "development"),
        "message": "Hello from GitOps!",
    })
```

### 2. Commit and push
```bash
git add sample-app/src/app.py
git commit -m "feat: add greeting message"
git push
```

### 3. Watch the pipeline
1. **GitHub Actions** (https://github.com/esarath/ocp-gitops-poc/actions):
   - Tests run → Image builds → Pushes to ghcr.io → Updates staging manifest
2. **ArgoCD detects the new image tag (via kustomize newTag change) and auto-syncs
3. **Staging endpoint**: Pod rolls out automatically (newTag change triggers rollout) - new response within ~3-5 minutes

### 4. Promote to Production
Once staging looks good, promote the same image to production:
1. Go to https://github.com/esarath/ocp-gitops-poc/actions
2. In the left sidebar, click **Promote to Production**
3. Click **Run workflow**
4. Enter the image tag (the 7-char SHA from the CI build, e.g., `a1b2c3d`)
5. Click **Run workflow**
6. This updates the production manifest → ArgoCD auto-syncs → Production updated

---

## Troubleshooting

### CI build fails with "Username and password required"
- **Most likely cause**: The workflow file still references Quay.io instead of ghcr.io
- Verify the workflow on GitHub: check `.github/workflows/ci.yaml` has `REGISTRY: ghcr.io`
- Ensure GitHub repo settings have **"Read and write permissions"** under Settings > Actions > General > Workflow permissions
- See `docs/ci-pipeline-fix-rca.md` for the full root cause analysis of this exact issue

### ArgoCD shows "ComparisonError"
- Check that the GitHub repo URL is correct and accessible
- In ArgoCD UI → Settings → Repositories → verify connection is green

### Pods stuck in ImagePullBackOff
- The image hasn't been pushed to ghcr.io yet (wait for CI to complete)
- The ghcr.io package may be **private** - make it public (see Step 7)
- Check: `oc describe pod <pod-name> -n sample-app-staging`
- Verify image exists: `https://github.com/esarath?tab=packages`

### ArgoCD app shows "Unknown" or "Missing"
- The Git repo hasn't been pushed yet, or the path in the Application doesn't match
- Check: ArgoCD UI → click the app → check the source path

### Cannot access ArgoCD UI
- Make sure you're on the same network as the cluster
- URL: https://openshift-gitops-server-openshift-gitops.apps.lab.ocp.local
- Try from svc-infra: `curl -sk https://openshift-gitops-server-openshift-gitops.apps.lab.ocp.local`

### CI workflow not triggering after push
- The CI only triggers on changes to `sample-app/**` path
- Changes to `.github/workflows/`, `apps/`, `docs/`, etc. will NOT trigger CI
- Push a change inside `sample-app/` directory to trigger
