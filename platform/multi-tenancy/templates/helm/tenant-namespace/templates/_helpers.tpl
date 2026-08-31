{{- define "tenant-namespace.name" -}}
{{- required "tenant.name is required" .Values.tenant.name -}}
{{- end -}}
