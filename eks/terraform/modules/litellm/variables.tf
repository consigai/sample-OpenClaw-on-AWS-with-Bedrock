################################################################################
# LiteLLM Module - Variables
################################################################################

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "cluster_oidc_issuer" {
  description = "OIDC issuer URL for the EKS cluster (without https:// prefix)"
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the OIDC provider for the EKS cluster"
  type        = string
}

variable "chart_repository" {
  description = "Override Helm chart OCI repository for litellm (e.g. oci://ECR_HOST/charts for China). Empty = default ghcr.io."
  type        = string
  default     = ""
}

variable "ecr_host" {
  description = "Private ECR host for China image mirrors. Empty = use upstream."
  type        = string
  default     = ""
}

variable "is_china_region" {
  description = "Whether the deployment is in an AWS China region"
  type        = bool
  default     = false
}

variable "partition" {
  description = "AWS partition (aws, aws-cn, aws-us-gov)"
  type        = string
  default     = "aws"
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
