# OCP GitOps POC - Session Context & Cluster State

## Cluster Access
- **Proxmox Host (tiny1)**: `ssh -o StrictHostKeyChecking=no root@192.168.29.2` (password auth auto-accepted)
- **From tiny1 to svc-infra**: `ssh centos@192.168.29.10`
- **OCP SSH key on svc-infra**: `~/.ssh/ocp4-key`
- **From tiny1 to masters**: `ssh -i /root/.ssh/ocp4-key core@192.168.29.{21,22,23}`
- **OCP API**: `https://api.lab.ocp.local:6443`
- **kubeadmin password**: `aWXgw-ePDZe-WPdDT-Am8gY`
- **OCP version**: 4.15.59

## ArgoCD Access
- **Route**: `https://openshift-gitops-server-openshift-gitops.apps.lab.ocp.local`
- **Admin password**: `EvRtK9IjMU3HhPqGpiA1Jea6nrc0TwlL`
- **Operator version**: Red Hat OpenShift GitOps v1.20.1

## GitHub Repository
- **Repo**: https://github.com/esarath/ocp-gitops-poc
- **Visibility**: Public
- **Workflow Permissions**: Read and write permissions enabled

## Container Registry
- **Registry**: ghcr.io (GitHub Container Registry)
- **Image path**: ghcr.io/esarath/sample-app
- **Visibility**: Public
- **Auth**: Built-in GITHUB_TOKEN (no external secrets)
- **Package URL**: https://github.com/users/esarath/packages/container/sample-app

## Cluster Topology
| Node | IP | Role | Proxmox VMID | RAM |
|---|---|---|---|---|
| svc-infra | 192.168.29.10 | HAProxy LB / DNS | 100 | 6GB |
| master-1 | 192.168.29.21 | control-plane,master | 201 | 13.5GB |
| master-2 | 192.168.29.22 | control-plane,master | 202 | 13.5GB |
| master-3 | 192.168.29.23 | control-plane,master | 203 | 13.5GB |
| worker-1 | 192.168.29.31 | worker | 301 | 5GB |
| worker-2 | 192.168.29.32 | worker | 302 | 5GB |

## Current Cluster State (as of 2026-04-05)
- All 5 nodes: **Ready**
- All 33 cluster operators: **Available=True, Degraded=False**
- `mastersSchedulable: false` - masters have NoSchedule taint
- Worker VMs are running
- NFS provisioner: running (StorageClass: nfs-storage)

## Application State (as of 2026-04-05)

### ArgoCD Applications
| Application | Sync | Health | Revision |
|---|---|---|---|
| app-of-apps | Synced | Healthy | main (HEAD) |
| sample-app-staging | Synced | Healthy | main (HEAD) |
| sample-app-production | Synced | Healthy | main (HEAD) |

### Sample App Deployments
| Environment | Namespace | Replicas | Image Tag | Endpoint |
|---|---|---|---|---|
| Staging | sample-app-staging | 1 | `e132cfe` | https://sample-app-sample-app-staging.apps.lab.ocp.local |
| Production | sample-app-production | 2 | `a81ba91` | https://sample-app-sample-app-production.apps.lab.ocp.local |

### CI/CD Pipeline
- **CI runs**: 7 total, last 3 successful (#5, #6, #7)
- **Pipeline flow**: Code push -> GitHub Actions (test, build, push to ghcr.io) -> manifest update -> ArgoCD auto-sync -> pod rollout
- **Image tags**: Using commit SHA tags via kustomize `images.newTag` (not `:latest`)

## OpenShift GitOps / ArgoCD
- **Operator**: openshift-gitops-operator v1.20.1 (redhat-operators catalog)
- **ArgoCD CR**: openshift-gitops in openshift-gitops namespace
- **Status**: Available, all pods Running
- **Pod placement**: Most pods on worker-2, applicationset-controller on master-1 (via nodePlacement tolerations)
- **PDBs**: 3 deployed (server, repo-server, controller)
- **ServiceMonitors**: 3 deployed (server, repo-server, controller)
- **User workload monitoring**: enabled (enableUserWorkload: true)
- **Monitoring replicas**: Scaled down to 1 (lab environment) - prometheus, alertmanager, thanos-ruler
- **Resource constraint notes**: Workers are 5GB RAM each; OVN (1630Mi) + platform pods consume most capacity. ArgoCD resources tuned to minimal requests for lab.

## HAProxy Config (svc-infra /etc/haproxy/haproxy.cfg)
- API (6443): master-1, master-2, master-3
- Machine Config (22623): master-1, master-2, master-3
- HTTP Ingress (80): worker-1, worker-2, master-1, master-2, master-3
- HTTPS Ingress (443): worker-1, worker-2, master-1, master-2, master-3
- Stats page: http://192.168.29.10:9000/stats

## DNS
- Nameserver: 192.168.29.10 (svc-infra)
- Domain: lab.ocp.local
- Apps wildcard: *.apps.lab.ocp.local

## Storage
- NFS provisioner running in `nfs-provisioner` namespace
- StorageClass: `nfs-storage`

## Network
- OVN-Kubernetes CNI
- Pod network: 10.128.0.0/14
- Service network: 172.30.0.0/16
- Default gateway: 192.168.29.1
- Internet access: Yes (ghcr.io reachable from nodes)

## Completed Phases
1. **Phase 1**: Cluster Assessment - all checks passed (see docs/phase1-cluster-assessment.md)
2. **Phase 2**: ArgoCD Installation - operator, CR, PDBs, ServiceMonitors deployed
3. **Phase 3**: Sample App CI/CD - Flask app, GitHub Actions CI, ghcr.io registry, ArgoCD App-of-Apps, staging + production deployed and verified end-to-end

## Previous Issues Fixed
1. Worker VMs (301,302) were stopped on Proxmox - started them
2. HAProxy only routed ingress to workers, but routers were on masters - added masters to ingress backends
3. openshift-apiserver pods stuck in ImagePullBackOff - force deleted to retry
4. Router pods CrashLoopBackOff - force deleted, rescheduled to workers
5. mastersSchedulable set to false - removed worker role from masters
6. Released PVs from old Jenkins - cleaned up
7. User workload monitoring not configured - enabled
8. ArgoCD pods Pending due to worker resource constraints - tuned resources, used nodePlacement tolerations, scaled down monitoring replicas
9. CI pipeline failing with "Username and password required" - svc-infra repo had old Quay.io workflow files; fixed by transferring corrected ghcr.io workflow from Windows (see docs/ci-pipeline-fix-rca.md)
10. Image tag `:latest` not triggering pod rollouts - switched to commit SHA tags via kustomize `images.newTag` so ArgoCD detects deployment spec changes and triggers rolling updates automatically
