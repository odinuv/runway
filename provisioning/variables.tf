variable "subscription_id" {
  description = "Azure subscription, do které se zdroje založí."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
  default     = "swedencentral"
}

variable "name_prefix" {
  description = "Prefix názvů zdrojů (3-12 znaků a-z0-9)."
  type        = string
  default     = "runway"

  validation {
    condition     = can(regex("^[a-z0-9]{3,12}$", var.name_prefix))
    error_message = "name_prefix musí mít 3-12 znaků a-z0-9."
  }
}

variable "openai_model_name" {
  description = "Model pro kategorizaci."
  type        = string
  default     = "gpt-5.4-mini"
}

variable "openai_model_version" {
  description = "Verze modelu."
  type        = string
  default     = "2026-03-17"
}

variable "openai_deployment_sku" {
  description = "SKU deploymentu. DataZoneStandard drží zpracování dat v EU."
  type        = string
  default     = "DataZoneStandard"
}

variable "openai_capacity" {
  description = "Kapacita deploymentu (v tisících tokenů za minutu)."
  type        = number
  default     = 10
}

variable "app_sas_validity_hours" {
  description = "Platnost read-only SAS pro appku v hodinách (výchozí 2 roky)."
  type        = number
  default     = 17520
}
