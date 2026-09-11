output "resource_group_name" {
  description = "Grupo de recursos creado en Azure"
  value       = azurerm_resource_group.rg.name
}

output "storage_account_name" {
  description = "Nombre de la Storage Account (ADLS Gen2) creada"
  value       = azurerm_storage_account.adls.name
}

output "filesystem_name" {
  description = "Nombre del contenedor/filesystem principal"
  value       = azurerm_storage_data_lake_gen2_filesystem.eurobank_logs.name
}

output "adls_mobile_path_abfss" {
  description = "Ruta oficial ABFSS para Databricks / Unity Catalog External Location"
  value       = "abfss://${azurerm_storage_data_lake_gen2_filesystem.eurobank_logs.name}@${azurerm_storage_account.adls.name}.dfs.core.windows.net/mobile/"
}

output "azure_portal_storage_url" {
  description = "URL directa para acceder a la cuenta de almacenamiento en el portal de Azure"
  value       = "https://portal.azure.com/#@/resource${azurerm_storage_account.adls.id}"
}

output "gcs_bucket_name" {
  description = "Nombre del bucket GCS creado"
  value       = google_storage_bucket.eurobank_geo.name
}

output "gcs_location_path" {
  description = "URI oficial de geolocalización en GCS para Databricks / Unity Catalog"
  value       = "gs://${google_storage_bucket.eurobank_geo.name}/location/"
}

output "s3_bucket_name" {
  description = "Nombre del bucket AWS S3 creado"
  value       = aws_s3_bucket.eurobank_raw.id
}

output "s3_transactions_path" {
  description = "URI oficial S3 para Transacciones de Tarjetas en Databricks / Unity Catalog"
  value       = "s3://${aws_s3_bucket.eurobank_raw.id}/transactions/"
}
