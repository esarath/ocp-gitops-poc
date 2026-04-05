# Phase 1: Cluster Assessment Report

**Date**: 2026-04-04  
**Cluster**: OCP 4.15.59 | API: https://api.lab.ocp.local:6443  
**Verdict**: **PASS** — Cluster is ready for GitOps POC deployment

---

## 1. Node Health

| Node | IP | Role | Status | CPU | Memory |
|---|---|---|---|---|---|
| master-1 | 192.168.29.21 | control-plane,master | Ready | 11% (407m) | 53% (6459Mi) |
| master-2 | 192.168.29.22 | control-plane,master | Ready | 18% (631m) | 74% (9026Mi) |
| master-3 | 192.168.29.23 | control-plane,master | Ready | 37% (1323m) | 93% (11244Mi) |
| worker-1 | 192.168.29.31 | worker | Ready | 3% (51m) | 41% (1518Mi) |
| worker-2 | 192.168.29.32 | worker | Ready | 3% (52m) | 41% (1539Mi) |

- **All 5 nodes**: Ready
- **Masters**: NoSchedule taint applied, `mastersSchedulable: false`
- **Workers**: No taints, sufficient headroom for workloads

> **Note**: master-3 memory at 93% — monitor during ArgoCD deployment.  
> Workers have ~59% memory free — adequate for sample-app + ArgoCD workloads.

## 2. Cluster Operators

- **All 33 operators**: Available=True, Progressing=False, Degraded=False
- Cluster version: 4.15.59 (stable, not progressing)

## 3. Networking

| Check | Result |
|---|---|
| CNI | OVN-Kubernetes |
| Pod Network | 10.128.0.0/14 |
| Service Network | 172.30.0.0/16 |
| DNS (api.lab.ocp.local) | Resolves to 192.168.29.10 |
| DNS (*.apps.lab.ocp.local) | Resolves to 192.168.29.10 |
| API healthz | HTTP 200 |
| Console | HTTP 200 |
| quay.io reachability | HTTP 200 |

- **Ingress**: 2 router pods on worker-1 and worker-2
- **HAProxy**: Routes API (6443) to masters, Ingress (80/443) to workers + masters

## 4. Storage

| Item | Status |
|---|---|
| StorageClass | `nfs-storage` (default) |
| NFS Provisioner | Running (1/1) in `nfs-provisioner` namespace |
| Stale PVs | **Cleaned up** (4 Released PVs from old Jenkins/test deleted) |
| Active PVs | 2 Bound (Prometheus data) |
| Reclaim Policy | Retain |

## 5. Monitoring & Observability

| Item | Status |
|---|---|
| Platform monitoring | Running (Prometheus, Alertmanager, node-exporter, kube-state-metrics) |
| ServiceMonitor CRD | Present |
| User workload monitoring | **Enabled** (cluster-monitoring-config updated) |
| User workload pods | prometheus-operator spinning up in openshift-user-workload-monitoring |

> User workload monitoring was not previously configured — now enabled to support  
> ArgoCD ServiceMonitors in Phase 2.

## 6. OLM & Operator Catalog

| Item | Status |
|---|---|
| PackageServer | Running (2 replicas) |
| redhat-operators catalog | Available |
| `openshift-gitops-operator` | **Available** in redhat-operators catalog |
| community-operators | Available |
| certified-operators | Available |

## 7. Security

| Item | Status |
|---|---|
| SCCs | All default SCCs present (restricted-v2, anyuid, privileged, etc.) |
| Certificate expiry | kube-apiserver signer valid until 2027-03-29 |
| Auth | kubeadmin active |

## 8. etcd

- All 3 etcd pods Running (4/4 containers each)
- 3 etcd-guard pods Running

## 9. Cleanup Performed

1. Deleted 4 stale Released PVs (leftover from Jenkins/test)
2. Enabled user workload monitoring (`enableUserWorkload: true`)

## 10. Pre-Deployment Checklist

| Requirement | Status |
|---|---|
| OCP 4.x cluster operational | ✅ |
| All nodes Ready | ✅ |
| All cluster operators healthy | ✅ |
| DNS wildcard configured | ✅ |
| Ingress operational | ✅ |
| Storage class available | ✅ |
| NFS provisioner running | ✅ |
| OLM operational | ✅ |
| GitOps operator available in catalog | ✅ |
| Monitoring stack running | ✅ |
| User workload monitoring enabled | ✅ |
| ServiceMonitor CRD present | ✅ |
| Internet access (quay.io) | ✅ |
| No conflicting GitOps artifacts | ✅ |
| Previous cleanup complete | ✅ |

---

**Next Step**: Phase 2 — Install OpenShift GitOps Operator and bootstrap ArgoCD
