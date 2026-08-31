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

module "stage_namespace" {
  source = "../../modules/tenant-namespace"

  tenant_name = "stage"
  environment = "stage"
  admin_group = "stage-team"

  quota = {
    requests_cpu    = "1"
    requests_memory = "1Gi"
    limits_cpu      = "2"
    limits_memory   = "2Gi"
    pods            = "10"
    pvcs            = "5"
    services        = "10"
    configmaps      = "20"
    secrets         = "20"
  }
}

output "stage_namespace" {
  value = module.stage_namespace.namespace
}
