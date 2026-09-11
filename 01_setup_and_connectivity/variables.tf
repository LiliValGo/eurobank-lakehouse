variable "azure_location" {
  type        = string
  description = "Región de Azure donde se desplegarán los recursos de almacenamiento"
  default     = "northeurope"
}

variable "azure_resource_group_name" {
  type        = string
  description = "Nombre del grupo de recursos en Azure"
  default     = "rg-eurobank-lakehouse"
}

variable "gcp_project_id" {
  type        = string
  description = "ID del proyecto de Google Cloud"
  default     = "databricks-508217"
}

variable "gcp_region" {
  type        = string
  description = "Región de Google Cloud para el bucket GCS"
  default     = "europe-west1"
}

variable "aws_account_id" {
  type        = string
  description = "AWS account ID (placeholder: sustituye por el tuyo)"
  default     = "123456789012"
}

variable "aws_region" {
  type        = string
  description = "Región de AWS para el bucket S3"
  default     = "eu-west-1" # Irlanda, zona europea alineada con Azure northeurope y GCP europe-west1
}
