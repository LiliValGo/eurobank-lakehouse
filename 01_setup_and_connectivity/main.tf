# Sufijo aleatorio para asegurar unicidad global en el nombre de la Storage Account (máximo 24 caracteres alfanuméricos)
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# 1. Grupo de Recursos en Azure
resource "azurerm_resource_group" "rg" {
  name     = var.azure_resource_group_name
  location = var.azure_location

  tags = {
    Environment = "Lakehouse"
    Project     = "EuroBank"
  }
}

# 2. Azure Data Lake Storage Gen2 (Storage Account con espacio de nombres jerárquico activo)
resource "azurerm_storage_account" "adls" {
  name                     = "stkeurobank${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"
  is_hns_enabled           = true # Activa ADLS Gen2 (Hierarchical Namespace)

  tags = {
    Environment = "Lakehouse"
    Workload    = "EuroBank-Logs"
  }
}

# 3. Filesystem / Contenedor: eurobank-logs
resource "azurerm_storage_data_lake_gen2_filesystem" "eurobank_logs" {
  name               = "eurobank-logs"
  storage_account_id = azurerm_storage_account.adls.id
}

# 4. Carpeta: mobile/ (donde residirán los JSON comprimidos: adls://eurobank-logs/mobile/)
resource "azurerm_storage_data_lake_gen2_path" "mobile_dir" {
  path               = "mobile"
  filesystem_name    = azurerm_storage_data_lake_gen2_filesystem.eurobank_logs.name
  storage_account_id = azurerm_storage_account.adls.id
  resource           = "directory"
}

# -------------------------------------------------------------
# 5. GOOGLE CLOUD STORAGE: Bucket eurobank-geo y carpeta location/
# -------------------------------------------------------------
resource "google_storage_bucket" "eurobank_geo" {
  name                        = "eurobank-geo-${random_string.suffix.result}"
  location                    = var.gcp_region
  force_destroy               = true
  uniform_bucket_level_access = true

  labels = {
    environment = "lakehouse"
    workload    = "eurobank-geo"
  }
}

# Directorio virtual: location/ (gs://eurobank-geo/location/)
resource "google_storage_bucket_object" "location_folder" {
  name    = "location/"
  content = " "
  bucket  = google_storage_bucket.eurobank_geo.name
}

# -------------------------------------------------------------
# 6. AWS S3: Bucket eurobank-raw y carpeta transactions/
# -------------------------------------------------------------
resource "aws_s3_bucket" "eurobank_raw" {
  bucket        = "eurobank-raw-${random_string.suffix.result}"
  force_destroy = true

  tags = {
    Environment = "Lakehouse"
    Workload    = "EuroBank-CardTransactions"
  }
}

# Bloquear acceso público por seguridad bancaria
resource "aws_s3_bucket_public_access_block" "eurobank_raw_block" {
  bucket = aws_s3_bucket.eurobank_raw.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Habilitar versionado recomendado para Data Lakehouses
resource "aws_s3_bucket_versioning" "eurobank_raw_versioning" {
  bucket = aws_s3_bucket.eurobank_raw.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Carpeta / Prefijo virtual: transactions/ (s3://eurobank-raw/transactions/)
resource "aws_s3_object" "transactions_folder" {
  bucket = aws_s3_bucket.eurobank_raw.id
  key    = "transactions/"
}
