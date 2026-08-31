output "namespace" {
  description = "Name of the created tenant namespace"
  value       = kubernetes_namespace.this.metadata[0].name
}
