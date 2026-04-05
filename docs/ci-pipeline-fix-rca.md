# CI Pipeline Fix - Root Cause Analysis & Resolution

## Date: April 5, 2026
## Status: RESOLVED
## CI Runs Affected: #1 through #4 (all failed)
## CI Run Fixed: #5 (commit `0a96677`) - SUCCESS

---

## 1. Problem Statement

The GitHub Actions CI pipeline ("CI - Build and Push") was failing consistently at the **build-and-push** job with the error:

```
Error: Username and password required
```

The failure occurred at the **"Log in to Quay.io"** step (docker/login-action@v3), preventing the container image from being built and pushed to the container registry.

---

## 2. Root Cause Analysis

### Primary Root Cause: Repository Divergence Between Local Environments

The project had **two separate local clones** of the repository that were out of sync:

| Location | Path | Purpose |
|---|---|---|
| **Windows (local dev)** | `C:\Users\babus16\ocp-gitops-poc` | Primary development - where all phases were built |
| **svc-infra (CentOS)** | `/home/centos/git/ocp-gitops-poc` | Git push relay to GitHub (has SSH key access) |

During the initial project setup (Phases 1-6), all files were created and edited on the **Windows machine**. A decision was made during development to **switch the container registry from Quay.io to ghcr.io** (GitHub Container Registry) because:
- ghcr.io uses the built-in `GITHUB_TOKEN` for authentication (no external secrets needed)
- Simpler setup with fewer manual steps (no robot accounts, no external secrets)
- Tighter integration with GitHub Actions

The registry switch was applied to the **Windows repo** only. The files updated on Windows were:
- `.github/workflows/ci.yaml`
- `.github/workflows/promote.yaml`
- `apps/sample-app/base/deployment.yaml`
- `README.md`
- `docs/session-context.md`

However, when the code was pushed to GitHub, it was done from the **svc-infra machine** (which had SSH key-based GitHub access). The svc-infra repo was initialized independently and **still contained the original Quay.io configuration**. This meant the svc-infra push **overwrote** the Windows changes, and the workflow files on GitHub were the old Quay.io versions.

### Secondary Contributing Factor: GitHub Actions Workflow Permissions

The initial GitHub repository did not have **"Read and write permissions"** enabled for the `GITHUB_TOKEN` under:
- **Settings > Actions > General > Workflow permissions**

Even after fixing the registry references, the `GITHUB_TOKEN` needed `packages:write` scope to push to ghcr.io, which required this repo-level setting to be enabled.

### Summary of What Was Wrong

| File | What Was On GitHub (WRONG) | What Should Have Been (CORRECT) |
|---|---|---|
| `.github/workflows/ci.yaml` | `REGISTRY: quay.io` | `REGISTRY: ghcr.io` |
| `.github/workflows/ci.yaml` | `IMAGE_NAME: sarrathbabu/sample-app` | `IMAGE_NAME: esarath/sample-app` |
| `.github/workflows/ci.yaml` | `secrets.QUAY_USERNAME` / `secrets.QUAY_PASSWORD` | `github.actor` / `secrets.GITHUB_TOKEN` |
| `.github/workflows/ci.yaml` | No `permissions:` block | `permissions: contents: write, packages: write` |
| `.github/workflows/ci.yaml` | Step name: "Log in to Quay.io" | Step name: "Log in to GitHub Container Registry" |
| `.github/workflows/promote.yaml` | `REGISTRY: quay.io` env vars, no permissions | Removed quay env vars, added `permissions: contents: write` |
| `apps/sample-app/base/deployment.yaml` | `image: quay.io/sarrathbabu/sample-app:latest` | `image: ghcr.io/esarath/sample-app:latest` |

---

## 3. Timeline of CI Runs

| Run # | Commit | Status | Error | Notes |
|---|---|---|---|---|
| #1 | `1c7eefb` | FAILED | Username and password required | Original trigger - Quay.io workflow, no secrets configured |
| #2 | `506de68` | FAILED | Username and password required | User retried push, same old workflow |
| #3 | `589e2e2` | FAILED | Username and password required | User updated repo permissions, but workflow still had Quay.io |
| #4 | `60203c8` | FAILED | Username and password required | Same issue - workflow on GitHub unchanged |
| **#5** | **`0a96677`** | **SUCCESS** | **None** | **Fixed workflow pushed via commit `de3014e`, triggered by `0a96677`** |

---

## 4. Fix Applied - Step by Step

### Step 1: Identified the Root Cause
- Reviewed the CI error screenshots (`cierror1.png`, `cierror2.png`)
- Key observation: The step name was **"Log in to Quay.io"** not "Log in to GitHub Container Registry"
- Fetched the workflow file from GitHub (`https://github.com/esarath/ocp-gitops-poc/blob/main/.github/workflows/ci.yaml`) and confirmed it still had `quay.io` configuration
- Compared with the Windows local version which had the correct `ghcr.io` configuration

### Step 2: Updated GitHub Actions Workflow Permissions
- Navigate to: `https://github.com/esarath/ocp-gitops-poc/settings/actions`
- Changed **Workflow permissions** from "Read repository contents and packages permissions" to **"Read and write permissions"**
- Checked **"Allow GitHub Actions to create and approve pull requests"**
- Clicked **Save**

### Step 3: Fixed `.github/workflows/ci.yaml` on svc-infra
The correct file was base64-encoded from the Windows repo and transferred to svc-infra via SSH.

**Changes made:**
```yaml
# BEFORE (wrong - Quay.io)
env:
  REGISTRY: quay.io
  IMAGE_NAME: sarrathbabu/sample-app

# No permissions block

      - name: Log in to Quay.io
        uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ secrets.QUAY_USERNAME }}
          password: ${{ secrets.QUAY_PASSWORD }}
```

```yaml
# AFTER (correct - ghcr.io)
env:
  REGISTRY: ghcr.io
  IMAGE_NAME: esarath/sample-app

permissions:
  contents: write
  packages: write

      - name: Log in to GitHub Container Registry
        uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
```

### Step 4: Fixed `.github/workflows/promote.yaml` on svc-infra
- Removed `quay.io` environment variables (not needed - promote workflow only updates manifests)
- Added `permissions: contents: write` block

### Step 5: Fixed `apps/sample-app/base/deployment.yaml` on svc-infra
```yaml
# BEFORE
image: quay.io/sarrathbabu/sample-app:latest

# AFTER
image: ghcr.io/esarath/sample-app:latest
```

### Step 6: Committed and Pushed the Fix
```bash
cd /home/centos/git/ocp-gitops-poc
git add -A
git commit -m "fix: switch container registry from quay.io to ghcr.io"
git push origin main
# Result: commit de3014e pushed successfully
```

Note: This commit did NOT trigger the CI because it only changed `.github/workflows/` and `apps/` files, not `sample-app/**` which is the CI trigger path.

### Step 7: Triggered a CI Build with the Fixed Workflow
```bash
echo "# Sample App - CI trigger" >> sample-app/README.md
git add sample-app/README.md
git commit -m "ci: trigger build with ghcr.io registry fix"
git push origin main
# Result: commit 0a96677 pushed, CI run #5 triggered
```

### Step 8: Verified Success
- CI run #5 completed in **1m 1s** (vs ~18s for failed runs - indicating it progressed past login to actually build/push)
- Container image published at `ghcr.io/esarath/sample-app`
- Package visible at `https://github.com/esarath?tab=packages` with tags: `latest` + SHA tag

---

## 5. Commands Used for the Fix

```bash
# Transfer corrected ci.yaml from Windows to svc-infra via base64 encoding
# (needed because ${{ }} GitHub Actions syntax conflicts with bash)
cat .github/workflows/ci.yaml | base64 -w0  # on Windows
ssh root@192.168.29.2 "ssh centos@192.168.29.10 'echo <base64> | base64 -d > /path/ci.yaml'"

# Same approach for promote.yaml and deployment.yaml

# Verify changes
grep -n REGISTRY .github/workflows/ci.yaml
grep image apps/sample-app/base/deployment.yaml

# Commit and push
git add -A
git commit -m "fix: switch container registry from quay.io to ghcr.io"
git push origin main

# Trigger CI
echo "# Sample App - CI trigger" >> sample-app/README.md
git add sample-app/README.md
git commit -m "ci: trigger build with ghcr.io registry fix"
git push origin main
```

---

## 6. Lessons Learned

1. **Keep repository clones in sync**: When working across multiple machines, always pull latest before pushing to avoid overwriting changes.
2. **Verify what's on the remote**: Before debugging CI, always check the actual file content on GitHub (not just the local copy).
3. **ghcr.io simplifies authentication**: Using GitHub Container Registry eliminates the need for external secrets (`QUAY_USERNAME`/`QUAY_PASSWORD`) - the built-in `GITHUB_TOKEN` handles everything.
4. **Workflow permissions matter**: Even with `permissions:` declared in the workflow YAML, the repository-level setting must allow "Read and write permissions" for `GITHUB_TOKEN`.
5. **CI trigger paths**: Changes to `.github/workflows/` don't trigger a CI run if the trigger path filter is `sample-app/**` - a separate commit touching that path is needed.

---

## 7. Current Working Configuration

- **Container Registry**: ghcr.io (GitHub Container Registry)
- **Image Path**: `ghcr.io/esarath/sample-app`
- **Authentication**: `GITHUB_TOKEN` (automatic, no manual secrets needed)
- **CI Workflow**: `.github/workflows/ci.yaml` - triggers on push to `main` with changes in `sample-app/**`
- **Promote Workflow**: `.github/workflows/promote.yaml` - manual trigger (workflow_dispatch)
- **GitHub Repo Settings**: Workflow permissions set to "Read and write permissions"
