variable "tenant_name" {
  description = "Namespace name for the tenant"
  type        = string
}

variable "environment" {
  description = "Free-text environment label, e.g. dev/stage/prod"
  type        = string
}

variable "admin_group" {
  description = "OAuth/IdP group granted namespace-scoped admin (empty string skips the RoleBinding)"
  type        = string
  default     = ""
}

variable "argocd_managed" {
  description = "Whether to label the namespace as ArgoCD-managed"
  type        = bool
  default     = true
}

variable "quota" {
  description = "ResourceQuota hard limits"
  type = object({
    requests_cpu    = string
    requests_memory = string
    limits_cpu      = string
    limits_memory   = string
    pods            = string
    pvcs            = string
    services        = string
    configmaps      = string
    secrets         = string
  })
  default = {
    requests_cpu    = "500m"
    requests_memory = "512Mi"
    limits_cpu      = "1"
    limits_memory   = "1Gi"
    pods            = "10"
    pvcs            = "5"
    services        = "10"
    configmaps      = "20"
    secrets         = "20"
  }
}

variable "limit_range" {
  description = "Per-container LimitRange defaults"
  type = object({
    default_cpu         = string
    default_memory      = string
    default_request_cpu = string
    default_request_mem = string
    max_cpu             = string
    max_memory          = string
    min_cpu              = string
    min_memory           = string
  })
  default = {
    default_cpu          = "250m"
    default_memory       = "256Mi"
    default_request_cpu  = "100m"
    default_request_mem  = "128Mi"
    max_cpu               = "1"
    max_memory            = "1Gi"
    min_cpu                = "50m"
    min_memory             = "64Mi"
  }
}

variable "allow_from_ingress" {
  description = "Allow ingress from the OpenShift router namespace"
  type        = bool
  default     = true
}

variable "allow_from_monitoring" {
  description = "Allow ingress from cluster + user-workload monitoring for metrics scraping"
  type        = bool
  default     = true
}
