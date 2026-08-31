# tenant-namespace (Terraform project template)

Equivalent of the Helm chart in `../helm/tenant-namespace`, for teams that
provision namespaces via Terraform instead of GitOps manifests. Not used to
manage `stage`/`prod` in this POC (those are ArgoCD-managed, see
`platform/multi-tenancy/base/`) — this exists as the alternative onboarding
path documented in `../../onboarding/ONBOARDING.md`.

## Usage

```bash
cd environments/stage   # or environments/prod
terraform init
terraform fmt -check
terraform validate       # no cluster connectivity required
terraform plan            # requires a working kubeconfig for the target cluster
terraform apply
```

CI (`validate-multi-tenancy.yaml`) runs `fmt -check` and `validate` only —
`plan`/`apply` require connectivity to `api.lab.ocp.local:6443`, which is a
private lab network unreachable from GitHub-hosted runners, so those steps
stay manual/local.
