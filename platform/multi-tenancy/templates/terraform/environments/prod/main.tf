terraform {
  required_version = ">= 1.5.0"
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.31"
    }
  }
  # Local state for this lab POC. Point this at a remote backend
  # (S3/GCS/Terraform Cloud) before using this against a real prod cluster.
}

provider "kubernetes" {
  config_path = var.kubeconfig_path
}

variable "kubeconfig_path" {
  description = "Path to a kubeconfig with access to the target cluster"
  type        = string
  default     = "~/.kube/config"
}

module "prod_namespace" {
  source = "../../modules/tenant-namespace"

  tenant_name = "prod"
  environment = "prod"
  admin_group = "prod-team"

  quota = {
    requests_cpu    = "1500m"
    requests_memory = "1536Mi"
    limits_cpu      = "3"
    limits_memory   = "3Gi"
    pods            = "15"
    pvcs            = "10"
    services        = "15"
    configmaps      = "30"
    secrets         = "30"
  }

  limit_range = {
    default_cpu         = "500m"
    default_memory      = "512Mi"
    default_request_cpu = "200m"
    default_request_mem = "256Mi"
    max_cpu             = "2"
    max_memory          = "2Gi"
    min_cpu             = "100m"
    min_memory          = "128Mi"
  }
}

output "prod_namespace" {
  value = module.prod_namespace.namespace
}
