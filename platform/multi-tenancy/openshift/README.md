# OpenShift native self-service (`oc new-project`)

`project-template.yaml` is a `template.openshift.io/v1` `Template` — the
mechanism OpenShift itself uses for self-service project provisioning. Wiring
it in makes every `oc new-project` (by any user with the `self-provisioner`
cluster role) come out pre-loaded with quota, limits, and default-deny
NetworkPolicies, instead of an ungoverned bare namespace.

This is **not** applied by ArgoCD or CI. It's a manual, cluster-admin,
opt-in step because it changes cluster-wide self-provisioning behavior:

```bash
# 1. Create the template (namespace openshift-config is a fixed OpenShift convention)
oc apply -f project-template.yaml

# 2. Point the cluster at it
oc patch project.config.openshift.io/cluster --type=merge -p '
spec:
  projectRequestTemplate:
    name: project-request
'

# 3. Verify
oc get project.config.openshift.io/cluster -o yaml
oc new-project demo-self-service --display-name="Demo" --description="test"
oc get resourcequota,limitrange,networkpolicy -n demo-self-service
```

To roll back: `oc patch project.config.openshift.io/cluster --type=merge -p 'spec: {projectRequestTemplate: null}'`.

For this POC, `stage` and `prod` are provisioned via the GitOps path
(`platform/multi-tenancy/base/`) instead, since they're platform-team-owned
tenant environments rather than a user's ad hoc `oc new-project`. This
template is the complementary path for genuine per-user/per-team self-service
onboarding and is exercised in the Day 5 step of the timeline as an optional
stretch goal, gated on explicit confirmation before touching the cluster-wide
setting.
