# Runway domácnosti

Modelování „runway“ domácnosti: jak dlouho vydrží úspory, když vypadne pravidelný příjem a nahradí ho jiný. Bankovní výpisy (Fio CSV, ABO/GPC) se importují z Azure Blob Storage do jednoho JSONu, LLM (Azure OpenAI) k nim doplní kategorie a Android appka ve Flutteru z nich počítá runway ve třech scénářích škrtání.

Pořadí nasazení: `provisioning/` (Terraform, Azure zdroje) → `pipeline/` (Python CLI `runway import` a `runway categorize`) → `app/` (Flutter appka).

Návrh: [docs/superpowers/specs/2026-11-09-runway-design.md](docs/superpowers/specs/2026-11-09-runway-design.md).
