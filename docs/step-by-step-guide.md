# Step-by-Step: Deploy Sample App with CI/CD

## Overview - What happens end-to-end

```
You push code → GitHub Actions builds image → Pushes to Quay.io → Updates manifest → ArgoCD detects change → Deploys to OpenShift
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

## Step 3: Create Quay.io Image Repository

1. Go to https://quay.io and log in (username: `sarrathbabu`)
2. Click **+ Create New Repository** (top right)
3. Repository name: `sample-app`
4. Visibility: **Public**
5. Click **Create Public Repository**

Your image will be at: `quay.io/sarrathbabu/sample-app`

## Step 4: Create Quay.io Robot Account (for CI)

Robot accounts are special accounts for automation (like GitHub Actions).

1. Go to https://quay.io/organization/sarrathbabu?tab=robots
   - OR: Go to https://quay.io → Click your username (top right) → Account Settings → Robot Accounts
2. Click **Create Robot Account**
3. Name: `cicd` (full name will be `sarrathbabu+cicd`)
4. Give it **Write** permission to the `sample-app` repository
5. After creation, click on the robot account name
6. You'll see:
   - **Username**: `sarrathbabu+cicd`
   - **Token**: (a long string) — copy this!

> **Alternative**: If robot accounts aren't available on your plan, you can use your
> Quay.io username and generate an **Encrypted Password** at:
> Account Settings → CLI Password → Generate Encrypted Password

## Step 5: Add Secrets to GitHub Repository

1. Go to https://github.com/esarath/ocp-gitops-poc/settings/secrets/actions
2. Click **New repository secret** and add:

| Secret Name | Value |
|---|---|
| `QUAY_USERNAME` | `sarrathbabu+cicd` (robot account) OR `sarrathbabu` (your username) |
| `QUAY_PASSWORD` | Robot token OR your encrypted password |

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
   - **build-and-push** job: builds Docker image, pushes to quay.io
   - **update-manifests** job: updates staging image tag in the repo

The workflow takes ~3-5 minutes.

### If the build succeeds:
- Image will be at: `quay.io/sarrathbabu/sample-app:<commit-sha>`
- The staging kustomization.yaml will be auto-updated with the new image tag
- ArgoCD will detect the change and deploy it

## Step 7: Verify Image on Quay.io

1. Go to https://quay.io/repository/sarrathbabu/sample-app?tab=tags
2. You should see tags: `latest` and a 7-character SHA tag (e.g., `a1b2c3d`)

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
   - Tests run → Image builds → Pushes to Quay.io → Updates staging manifest
2. **ArgoCD UI**: `sample-app-staging` will show "OutOfSync" briefly, then auto-sync
3. **Staging endpoint**: Will return the new message after ~3-5 minutes

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

### CI build fails with "unauthorized" on Quay.io
- Check that `QUAY_USERNAME` and `QUAY_PASSWORD` secrets are set correctly
- For robot accounts, username format is `sarrathbabu+cicd` (with the `+`)

### ArgoCD shows "ComparisonError"
- Check that the GitHub repo URL is correct and accessible
- In ArgoCD UI → Settings → Repositories → verify connection is green

### Pods stuck in ImagePullBackOff
- The image hasn't been pushed to Quay.io yet (wait for CI to complete)
- Check: `oc describe pod <pod-name> -n sample-app-staging`
- Verify image exists: https://quay.io/repository/sarrathbabu/sample-app?tab=tags

### ArgoCD app shows "Unknown" or "Missing"
- The Git repo hasn't been pushed yet, or the path in the Application doesn't match
- Check: ArgoCD UI → click the app → check the source path

### Cannot access ArgoCD UI
- Make sure you're on the same network as the cluster
- URL: https://openshift-gitops-server-openshift-gitops.apps.lab.ocp.local
- Try from svc-infra: `curl -sk https://openshift-gitops-server-openshift-gitops.apps.lab.ocp.local`
