################################################################################
# Monitoring Module - Variables
################################################################################

variable "cluster_name" {
  description = "Name of the EKS cluster (used for resource naming)"
  type        = string
}

variable "chart_repository" {
  description = "Override Helm chart OCI repository. Empty = upstream (prometheus-community, grafana)."
  type        = string
  default     = ""
}

variable "ecr_host" {
  description = "Private ECR host for China image mirrors. Empty = use upstream registries."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
