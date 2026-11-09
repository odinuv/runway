# Runway domácnosti

Modelování „runway“ domácnosti: jak dlouho vydrží úspory, když vypadne pravidelný příjem a nahradí ho jiný. Bankovní výpisy (Fio CSV, ABO/GPC) se importují z Azure Blob Storage do jednoho JSONu, LLM (Azure OpenAI) k nim doplní kategorie a Android appka ve Flutteru z nich počítá runway ve třech scénářích škrtání.

Pořadí nasazení: `provisioning/` (Terraform, Azure zdroje) → `pipeline/` (Python CLI `runway import` a `runway categorize`) → `app/` (Flutter appka).

Návrh: [docs/superpowers/specs/2026-11-09-runway-design.md](docs/superpowers/specs/2026-11-09-runway-design.md).

## Provisioning

Předpoklad: `az login` do subscription, kam patří domácí zdroje.

```bash
cd provisioning
cp terraform.tfvars.example terraform.tfvars   # doplnit subscription_id
terraform init
terraform apply
bash write-env.sh                               # zapíše pipeline/.env a app/.dart-defines.json
```

Model pro kategorizaci je ve výchozím stavu `gpt-5.4-mini` se SKU `DataZoneStandard` (data se zpracují v EU). Změníte ho proměnnými `openai_model_name`, `openai_model_version` a `openai_deployment_sku`.

## Pipeline

Předpoklad: provisioning je aplikovaný a `pipeline/.env` existuje (`provisioning/write-env.sh`).

1. Nahrajte výpis do kontejneru `upload` pod `inbox/`, např.:
   `az storage blob upload --connection-string "$AZURE_STORAGE_CONNECTION_STRING" -c upload -n inbox/vypis.csv -f vypis.csv`
2. `cd pipeline && uv run runway import` – přidá nové záznamy do `app/entries.json` a přesune výpis do `processed/`.
3. Při prvním importu doplňte do `entries.json` ručně `initialBalance` (stáhnout, upravit, nahrát zpět).
4. `uv run runway categorize` – doplní kategorie záznamům, které je ještě nemají. `--all` překategorizuje vše (např. po změně `config/categories.json`).

Stejné období nahrávejte jen v jednom formátu (CSV, nebo GPC). Mezi formáty se duplicity nepoznají.
Číslo vlastního účtu pro CSV lze nastavit v `.env` jako `RUNWAY_OWN_ACCOUNT`.
