resource "kubernetes_namespace" "this" {
  metadata {
    name = var.tenant_name
    labels = merge(
      {
        "app.kubernetes.io/part-of"                = "multi-tenancy"
        "tenant-environment"                        = var.environment
        "pod-security.kubernetes.io/enforce"        = "restricted"
        "pod-security.kubernetes.io/audit"          = "restricted"
        "pod-security.kubernetes.io/warn"           = "restricted"
      },
      var.argocd_managed ? { "argocd.argoproj.io/managed-by" = "openshift-gitops" } : {}
    )
    annotations = {
      "openshift.io/description"  = "Self-service ${var.environment} tenant namespace"
      "openshift.io/display-name" = var.tenant_name
    }
  }
}

resource "kubernetes_resource_quota" "this" {
  metadata {
    name      = "${var.tenant_name}-quota"
    namespace = kubernetes_namespace.this.metadata[0].name
  }
  spec {
    hard = {
      "requests.cpu"    = var.quota.requests_cpu
      "requests.memory" = var.quota.requests_memory
      "limits.cpu"      = var.quota.limits_cpu
      "limits.memory"   = var.quota.limits_memory
      "pods"            = var.quota.pods
      "persistentvolumeclaims" = var.quota.pvcs
      "services"        = var.quota.services
      "configmaps"      = var.quota.configmaps
      "secrets"         = var.quota.secrets
    }
  }
}

resource "kubernetes_limit_range" "this" {
  metadata {
    name      = "${var.tenant_name}-limits"
    namespace = kubernetes_namespace.this.metadata[0].name
  }
  spec {
    limit {
      type = "Container"
      default = {
        cpu    = var.limit_range.default_cpu
        memory = var.limit_range.default_memory
      }
      default_request = {
        cpu    = var.limit_range.default_request_cpu
        memory = var.limit_range.default_request_mem
      }
      max = {
        cpu    = var.limit_range.max_cpu
        memory = var.limit_range.max_memory
      }
      min = {
        cpu    = var.limit_range.min_cpu
        memory = var.limit_range.min_memory
      }
    }
  }
}

resource "kubernetes_network_policy" "default_deny_all" {
  metadata {
    name      = "default-deny-all"
    namespace = kubernetes_namespace.this.metadata[0].name
  }
  spec {
    pod_selector {}
    policy_types = ["Ingress", "Egress"]
  }
}

resource "kubernetes_network_policy" "allow_same_namespace" {
  metadata {
    name      = "allow-same-namespace"
    namespace = kubernetes_namespace.this.metadata[0].name
  }
  spec {
    pod_selector {}
    policy_types = ["Ingress", "Egress"]
    ingress {
      from {
        pod_selector {}
      }
    }
    egress {
      to {
        pod_selector {}
      }
    }
  }
}

resource "kubernetes_network_policy" "allow_dns_egress" {
  metadata {
    name      = "allow-dns-egress"
    namespace = kubernetes_namespace.this.metadata[0].name
  }
  spec {
    pod_selector {}
    policy_types = ["Egress"]
    egress {
      to {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = "openshift-dns"
          }
        }
      }
      ports {
        protocol = "UDP"
        port     = "5353"
      }
      ports {
        protocol = "TCP"
        port     = "5353"
      }
    }
  }
}

resource "kubernetes_network_policy" "allow_from_ingress" {
  count = var.allow_from_ingress ? 1 : 0
  metadata {
    name      = "allow-from-openshift-ingress"
    namespace = kubernetes_namespace.this.metadata[0].name
  }
  spec {
    pod_selector {}
    policy_types = ["Ingress"]
    ingress {
      from {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = "openshift-ingress"
          }
        }
      }
    }
  }
}

resource "kubernetes_network_policy" "allow_from_monitoring" {
  count = var.allow_from_monitoring ? 1 : 0
  metadata {
    name      = "allow-from-monitoring"
    namespace = kubernetes_namespace.this.metadata[0].name
  }
  spec {
    pod_selector {}
    policy_types = ["Ingress"]
    ingress {
      from {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = "openshift-monitoring"
          }
        }
      }
      from {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = "openshift-user-workload-monitoring"
          }
        }
      }
    }
  }
}

resource "kubernetes_role_binding" "admin" {
  count = var.admin_group != "" ? 1 : 0
  metadata {
    name      = "${var.admin_group}-admin"
    namespace = kubernetes_namespace.this.metadata[0].name
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "admin"
  }
  subject {
    kind      = "Group"
    name      = var.admin_group
    api_group = "rbac.authorization.k8s.io"
  }
}
