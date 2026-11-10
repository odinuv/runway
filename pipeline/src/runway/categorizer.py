"""Kategorizace záznamů přes LLM s výběrem výhradně z pevného seznamu."""

from __future__ import annotations

import json
import sys
from typing import Callable, Protocol

from openai import AzureOpenAI

from runway.categories import CategoryConfig
from runway.entry import Entry

DEFAULT_API_VERSION = "2025-04-01-preview"


class LlmClient(Protocol):
    def complete_json(self, system: str, user: str, schema: dict) -> dict: ...


class AzureLlmClient:
    def __init__(
        self,
        endpoint: str,
        api_key: str,
        deployment: str,
        api_version: str = DEFAULT_API_VERSION,
        client: AzureOpenAI | None = None,
    ):
        # Víc pokusů: nízká kapacita deploymentu vede při prvním běhu k 429.
        self._client = client or AzureOpenAI(
            azure_endpoint=endpoint, api_key=api_key, api_version=api_version, max_retries=6
        )
        self._deployment = deployment

    def complete_json(self, system: str, user: str, schema: dict) -> dict:
        # Bez temperature: reasoning modely (gpt-5.x) podporují jen výchozí hodnotu.
        # Nízké reasoning_effort stačí na výběr z výčtu a šetří tokeny i limit TPM.
        response = self._client.chat.completions.create(
            model=self._deployment,
            reasoning_effort="low",
            messages=[{"role": "system", "content": system}, {"role": "user", "content": user}],
            response_format={"type": "json_schema", "json_schema": {"name": "result", "strict": True, "schema": schema}},
        )
        return json.loads(response.choices[0].message.content)


def _ids(items: list[dict]) -> list[str]:
    return [it["id"] for it in items]


def _listing(items: list[dict]) -> str:
    return "\n".join(f"- {it['id']}: {it['description']}" for it in items)


def _schema(fields: dict[str, list[str]]) -> dict:
    item = {
        "type": "object",
        "properties": {"i": {"type": "integer"}, **{k: {"type": "string", "enum": v} for k, v in fields.items()}},
        "required": ["i", *fields],
        "additionalProperties": False,
    }
    return {
        "type": "object",
        "properties": {"items": {"type": "array", "items": item}},
        "required": ["items"],
        "additionalProperties": False,
    }


def _expense_task(cfg: CategoryConfig) -> tuple[str, dict[str, list[str]]]:
    system = (
        "Kategorizuješ výdaje z bankovního výpisu české domácnosti. Ke každé položce urči typ výdaje "
        "a míru potřeby. Vybírej výhradně z uvedených hodnot, nic nového nevymýšlej. "
        "Odpověz položkou pro každé `i` ze vstupu.\n\n"
        f"Typy výdaje:\n{_listing(cfg.expense_types)}\n\nPotřeba:\n{_listing(cfg.needs)}"
    )
    return system, {"type": _ids(cfg.expense_types), "need": _ids(cfg.needs)}


def _income_task(cfg: CategoryConfig) -> tuple[str, dict[str, list[str]]]:
    system = (
        "Určuješ, zda je příjem z bankovního výpisu české domácnosti pravidelný, nebo nepravidelný. "
        "Vybírej výhradně z uvedených hodnot. Odpověz položkou pro každé `i` ze vstupu.\n\n"
        f"Typy příjmu:\n{_listing(cfg.income_types)}"
    )
    return system, {"incomeType": _ids(cfg.income_types)}


def _payload(batch: list[Entry]) -> str:
    return json.dumps(
        [
            {
                "i": i,
                "date": e.date.isoformat(),
                "amount": e.amount_cents / 100,
                "counterAccount": e.counter_account,
                "message": e.message,
                "note": e.note,
                "type": e.type,
            }
            for i, e in enumerate(batch)
        ],
        ensure_ascii=False,
    )


def _run_batches(
    entries: list[Entry],
    kind: str,
    system: str,
    fields: dict[str, list[str]],
    llm: LlmClient,
    batch_size: int,
    stamp: dict,
    on_batch: Callable[[], None],
) -> list[Entry]:
    """Zpracuje záznamy po dávkách; vrátí ty, které nedostaly platnou odpověď."""
    schema = _schema(fields)
    missing: list[Entry] = []
    for start in range(0, len(entries), batch_size):
        batch = entries[start : start + batch_size]
        try:
            answers = llm.complete_json(system, _payload(batch), schema).get("items", [])
        except Exception as e:  # chybná dávka se zopakuje, běh pokračuje
            print(f"Volání LLM selhalo: {e}", file=sys.stderr)
            answers = []
        done: set[int] = set()
        for answer in answers:
            i = answer.get("i")
            if not isinstance(i, int) or not 0 <= i < len(batch) or i in done:
                continue
            if any(answer.get(k) not in allowed for k, allowed in fields.items()):
                continue
            batch[i].category = {"kind": kind, **{k: answer[k] for k in fields}, **stamp}
            done.add(i)
        missing.extend(e for i, e in enumerate(batch) if i not in done)
        on_batch()
    return missing


def categorize(
    entries: list[Entry],
    cfg: CategoryConfig,
    llm: LlmClient,
    batch_size: int,
    now: str,
    model: str,
    on_batch: Callable[[], None],
) -> list[Entry]:
    """Doplní `category`; vrátí záznamy, které zůstaly bez kategorie i po jednom opakování."""
    stamp = {"model": model, "categorizedAt": now}
    left: list[Entry] = []
    for kind, (system, fields), group in (
        ("expense", _expense_task(cfg), [e for e in entries if e.amount_cents < 0]),
        ("income", _income_task(cfg), [e for e in entries if e.amount_cents >= 0]),
    ):
        missing = _run_batches(group, kind, system, fields, llm, batch_size, stamp, on_batch)
        if missing:
            missing = _run_batches(missing, kind, system, fields, llm, batch_size, stamp, on_batch)
        left.extend(missing)
    return left
