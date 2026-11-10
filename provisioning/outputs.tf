output "storage_connection_string" {
  value     = azurerm_storage_account.this.primary_connection_string
  sensitive = true
}

output "upload_container" {
  value = azurerm_storage_container.upload.name
}

output "app_container" {
  value = azurerm_storage_container.app.name
}

output "openai_endpoint" {
  value = azurerm_cognitive_account.openai.endpoint
}

output "openai_api_key" {
  value     = azurerm_cognitive_account.openai.primary_access_key
  sensitive = true
}

output "openai_deployment" {
  value = azurerm_cognitive_deployment.model.name
}

output "app_sas_url" {
  # primary_blob_endpoint končí "/", sas začíná "?"
  value     = "${azurerm_storage_account.this.primary_blob_endpoint}${azurerm_storage_container.app.name}${data.azurerm_storage_account_blob_container_sas.app.sas}"
  sensitive = true
}
