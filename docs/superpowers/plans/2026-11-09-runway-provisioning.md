# Runway – Azure provisioning Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Terraform v `provisioning/`, který založí storage se dvěma kontejnery (`upload`, `app`), Azure OpenAI s jedním model deploymentem a vydá read-only SAS URL pro appku.

**Architecture:** Jeden Terraform root modul s lokálním state. Výstupy se přes skript `write-env.sh` přepíšou do `pipeline/.env` a do `app/.dart-defines.json`.

**Tech Stack:** Terraform 1.16, provider `hashicorp/azurerm` (>= 4.0), `hashicorp/random`, `hashicorp/time`, Azure CLI pro přihlášení.

**Spec:** `docs/superpowers/specs/2026-11-09-runway-design.md` (sekce „Provisioning“, „Bezpečnost appky“)

## Global Constraints

- Kontejnery: `upload` a `app`, oba privátní, bez anonymního přístupu.
- SAS pro appku: jen čtení (`read`), jen kontejner `app`, platnost je proměnná s výchozí hodnotou 2 roky.
- Výchozí region `swedencentral`. Název a verze modelu jsou proměnné.
- Všechny citlivé výstupy `sensitive = true`. `*.tfstate*`, `.terraform/`, `pipeline/.env` a `app/.dart-defines.json` patří do `.gitignore`.
- `terraform apply` vytváří placené zdroje. Spouští ho uživatel, ne agent.

## Review Focus

1. Opakovaný `terraform plan` po `apply` nesmí měnit SAS (žádné `timestamp()` ve vstupech SAS) → `plan` po apply hlásí „No changes“.
2. Název storage accountu musí splnit limit 3–24 znaků `[a-z0-9]` i s náhodným suffixem → validace proměnné `name_prefix`.
3. Model nebo verze nedostupné v regionu → `apply` selže až na deploymentu. Proto Task 1 krok 1 ověří dostupnost a výchozí hodnotu nastaví podle výsledku.
4. SAS URL musí mít tvar `https://<acc>.blob.core.windows.net/app?<sas>`, bez lomítka navíc a bez zdvojeného `?` → ověřit v Task 2.
5. `write-env.sh` při nepřihlášeném Terraformu / chybějícím state musí skončit nenulovým kódem, ne zapsat prázdný `.env`.

---

### Task 0: Repozitář

**Files:**
- Create: `.gitignore`, `README.md`

- [ ] **Step 1:** `git init` v `D:\OneDrive\Work\runway`. Vytvořit `.gitignore` s řádky: `.superpowers/`, `**/.terraform/`, `*.tfstate`, `*.tfstate.*`, `.terraform.lock.hcl` není ignorovaný (commitovat), `pipeline/.env`, `pipeline/.venv/`, `__pycache__/`, `app/.dart-defines.json`, `app/build/`, `app/.dart_tool/`.
- [ ] **Step 2:** `README.md` – tři odstavce: co je projekt, pořadí (provisioning → pipeline → app), odkaz na spec.
- [ ] **Step 3: Commit** – `git add -A && git commit -m "chore: init repo"` (bez co-author trailerů).

### Task 1: Terraform zdroje

**Files:**
- Create: `provisioning/versions.tf`, `provisioning/variables.tf`, `provisioning/main.tf`, `provisioning/outputs.tf`

**Interfaces:**
- Produces outputs: `storage_connection_string` (sensitive), `upload_container` (= `"upload"`), `app_container` (= `"app"`), `openai_endpoint`, `openai_api_key` (sensitive), `openai_deployment`, `app_sas_url` (sensitive).

- [ ] **Step 1: Ověřit model** – `az cognitiveservices model list --location swedencentral --query "[?model.format=='OpenAI' && contains(model.name,'mini')].{n:model.name,v:model.version,sku:model.skus[0].name}" -o table`. Vybrat nejnovější chat model „mini“ s podporou structured outputs a jeho sku. Tyto hodnoty jsou výchozí pro `openai_model_name`, `openai_model_version`, `openai_deployment_sku`.
- [ ] **Step 2: `variables.tf`** – `subscription_id` (string, bez defaultu), `location` = `"swedencentral"`, `name_prefix` = `"runway"` (validace `can(regex("^[a-z0-9]{3,12}$", var.name_prefix))`), `openai_model_name`, `openai_model_version`, `openai_deployment_sku`, `openai_capacity` = `10`, `app_sas_validity_hours` = `17520`.
- [ ] **Step 3: `main.tf`**
  - `random_string.suffix` (length 6, lower, no special, no upper)
  - `azurerm_resource_group` `"${var.name_prefix}-rg"`
  - `azurerm_storage_account` `"${var.name_prefix}${random_string.suffix.result}"`: Standard, LRS, StorageV2, `min_tls_version = "TLS1_2"`, `allow_nested_items_to_be_public = false`
  - `azurerm_storage_container` `upload` a `app` s `container_access_type = "private"`
  - `azurerm_cognitive_account`: kind `OpenAI`, sku `S0`, `custom_subdomain_name = "${var.name_prefix}-${random_string.suffix.result}"`
  - `azurerm_cognitive_deployment` `name = var.openai_model_name`
  - `time_static.sas_start`
  - `data.azurerm_storage_account_blob_container_sas.app`: `start = time_static.sas_start.rfc3339`, `expiry = timeadd(time_static.sas_start.rfc3339, "${var.app_sas_validity_hours}h")`, `https_only = true`, permissions jen `read = true`, ostatní `false`
- [ ] **Step 4: `outputs.tf`** – `app_sas_url = "${azurerm_storage_account.this.primary_blob_endpoint}app${data.azurerm_storage_account_blob_container_sas.app.sas}"` (endpoint končí `/`, `sas` začíná `?`).
- [ ] **Step 5: Ověřit** – `cd provisioning && terraform init && terraform fmt -check && terraform validate`. Očekávaný výstup: `Success! The configuration is valid.`
- [ ] **Step 6: Commit** – `git add provisioning && git commit -m "feat(provisioning): azure storage and openai"`

### Task 2: Export konfigurace a apply

**Files:**
- Create: `provisioning/write-env.sh`, `provisioning/terraform.tfvars.example`
- Modify: `README.md` (sekce Provisioning)

**Interfaces:**
- Produces: `pipeline/.env` s klíči `AZURE_STORAGE_CONNECTION_STRING`, `RUNWAY_UPLOAD_CONTAINER`, `RUNWAY_APP_CONTAINER`, `AZURE_OPENAI_ENDPOINT`, `AZURE_OPENAI_API_KEY`, `AZURE_OPENAI_DEPLOYMENT`. Dále `app/.dart-defines.json` s klíčem `RUNWAY_SAS_URL` (hash hesla doplní plán appky).

- [ ] **Step 1: `write-env.sh`** – `set -euo pipefail`. Každou hodnotu načte přes `terraform -chdir="$(dirname "$0")" output -raw <name>`. Hodnoty zapíše do `../pipeline/.env`. Do `../app/.dart-defines.json` sloučí klíč `RUNWAY_SAS_URL` a zachová ostatní existující klíče (pomocí `python -c` a `json`). Při chybě `terraform output` skončí dřív, než cokoliv zapíše: nejdřív načte všechny hodnoty do proměnných, teprve potom zapisuje.
- [ ] **Step 2: Ověřit bez state** – `bash provisioning/write-env.sh; echo $?`. Očekáváno: nenulový kód, `pipeline/.env` nevznikl.
- [ ] **Step 3: README** – postup: `az login`, zkopírovat `terraform.tfvars.example` → `terraform.tfvars` a doplnit `subscription_id`, `terraform apply`, `bash provisioning/write-env.sh`.
- [ ] **Step 4: Commit** – `git commit -am "feat(provisioning): env export script"` (+ `git add` nových souborů).
- [ ] **Step 5: Předat uživateli** – požádat uživatele, aby spustil `! cd provisioning && terraform apply` (placené zdroje). Pak spustit `write-env.sh` a ověřit:
  - `terraform -chdir=provisioning plan` → `No changes.`
  - `curl -s -o /dev/null -w "%{http_code}" "$(terraform -chdir=provisioning output -raw app_sas_url | sed 's|/app?|/app/missing.json?|')"` → `404` (SAS platí, blob neexistuje; 403 = špatný SAS)
