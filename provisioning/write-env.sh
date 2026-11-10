#!/usr/bin/env bash
# Zapíše výstupy Terraformu do pipeline/.env a app/.dart-defines.json.
# Nejdřív načte všechny hodnoty; když cokoliv selže, nic nezapíše.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(dirname "$here")"

out() { terraform -chdir="$here" output -raw "$1"; }

conn="$(out storage_connection_string)"
upload="$(out upload_container)"
app="$(out app_container)"
endpoint="$(out openai_endpoint)"
key="$(out openai_api_key)"
deployment="$(out openai_deployment)"
sas_url="$(out app_sas_url)"

for v in "$conn" "$upload" "$app" "$endpoint" "$key" "$deployment" "$sas_url"; do
  if [[ -z "$v" ]]; then
    echo "Prázdný výstup Terraformu – proběhl terraform apply?" >&2
    exit 1
  fi
done

cat > "$root/pipeline/.env" <<ENV
AZURE_STORAGE_CONNECTION_STRING=$conn
RUNWAY_UPLOAD_CONTAINER=$upload
RUNWAY_APP_CONTAINER=$app
AZURE_OPENAI_ENDPOINT=$endpoint
AZURE_OPENAI_API_KEY=$key
AZURE_OPENAI_DEPLOYMENT=$deployment
ENV

mkdir -p "$root/app"
RUNWAY_SAS_URL="$sas_url" python -I -c '
import json, os, sys
path = sys.argv[1]
try:
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
except FileNotFoundError:
    data = {}
data["RUNWAY_SAS_URL"] = os.environ["RUNWAY_SAS_URL"]
with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
' "$root/app/.dart-defines.json"

echo "Zapsáno: pipeline/.env, app/.dart-defines.json"
