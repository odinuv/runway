resource "random_string" "suffix" {
  length  = 6
  lower   = true
  upper   = false
  numeric = true
  special = false
}

resource "azurerm_resource_group" "this" {
  name     = "${var.name_prefix}-rg"
  location = var.location
}

resource "azurerm_storage_account" "this" {
  name                            = "${var.name_prefix}${random_string.suffix.result}"
  resource_group_name             = azurerm_resource_group.this.name
  location                        = azurerm_resource_group.this.location
  account_kind                    = "StorageV2"
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
}

resource "azurerm_storage_container" "upload" {
  name                  = "upload"
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
}

resource "azurerm_storage_container" "app" {
  name                  = "app"
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
}

resource "azurerm_cognitive_account" "openai" {
  name                  = "${var.name_prefix}-openai-${random_string.suffix.result}"
  resource_group_name   = azurerm_resource_group.this.name
  location              = azurerm_resource_group.this.location
  kind                  = "OpenAI"
  sku_name              = "S0"
  custom_subdomain_name = "${var.name_prefix}-${random_string.suffix.result}"
}

resource "azurerm_cognitive_deployment" "model" {
  name                 = var.openai_model_name
  cognitive_account_id = azurerm_cognitive_account.openai.id

  model {
    format  = "OpenAI"
    name    = var.openai_model_name
    version = var.openai_model_version
  }

  sku {
    name     = var.openai_deployment_sku
    capacity = var.openai_capacity
  }
}

# Pevný začátek platnosti, aby se SAS při dalším plánu neměnil.
resource "time_static" "sas_start" {}

data "azurerm_storage_account_blob_container_sas" "app" {
  connection_string = azurerm_storage_account.this.primary_connection_string
  container_name    = azurerm_storage_container.app.name
  https_only        = true
  start             = time_static.sas_start.rfc3339
  expiry            = timeadd(time_static.sas_start.rfc3339, "${var.app_sas_validity_hours}h")

  permissions {
    read   = true
    add    = false
    create = false
    write  = false
    delete = false
    list   = false
  }
}
