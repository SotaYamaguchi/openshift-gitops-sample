variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-2"
}

variable "cluster_name" {
  description = "ROSA cluster name"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where ROSA cluster is deployed"
  type        = string
}

variable "private_subnet_id" {
  description = "Existing private subnet ID in the ROSA VPC (used for Aurora)"
  type        = string
}

variable "oidc_provider_arn" {
  description = "OIDC provider ARN for IRSA (from ROSA cluster)"
  type        = string
}

variable "oidc_provider_url" {
  description = "OIDC provider URL for IRSA (without https://)"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, stg, prod)"
  type        = string
  default     = "dev"
}
