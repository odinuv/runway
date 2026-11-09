"""Výsledný dokument `entries.json`, identita záznamů a deduplikace."""

from __future__ import annotations

import hashlib
import json
from collections import Counter
from dataclasses import dataclass, field

from runway.entry import Entry

VERSION = 1
_KNOWN_KEYS = {"version", "initialBalance", "initialBalanceCurrency", "updatedAt", "modelConfig", "entries"}


def _identity(e: Entry) -> str:
    parts = [
        e.date.isoformat(),
        str(e.amount_cents),
        e.currency,
        e.own_account,
        e.counter_account,
        e.counter_bank_code,
        e.message,
        e.note,
        e.type,
    ]
    return "|".join(p or "" for p in parts)


def assign_ids(entries: list[Entry]) -> list[Entry]:
    """Nastaví `id`; identické záznamy v jednom seznamu odliší pořadím výskytu."""
    seen: Counter[str] = Counter()
    for e in entries:
        base = _identity(e)
        e.id = hashlib.sha256(f"{base}|{seen[base]}".encode()).hexdigest()
        seen[base] += 1
    return entries


@dataclass
class Document:
    initial_balance: float
    initial_balance_currency: str
    updated_at: str | None
    entries: list[Entry]
    model_config: dict = field(default_factory=dict)
    extra: dict = field(default_factory=dict)

    @classmethod
    def new(cls) -> Document:
        return cls(initial_balance=0, initial_balance_currency="CZK", updated_at=None, entries=[])

    @classmethod
    def from_json(cls, data: bytes) -> Document:
        raw = json.loads(data.decode("utf-8"))
        return cls(
            initial_balance=raw.get("initialBalance", 0),
            initial_balance_currency=raw.get("initialBalanceCurrency", "CZK"),
            updated_at=raw.get("updatedAt"),
            entries=[Entry.from_dict(e) for e in raw.get("entries", [])],
            model_config=raw.get("modelConfig") or {},
            extra={k: v for k, v in raw.items() if k not in _KNOWN_KEYS},
        )

    def to_json(self) -> bytes:
        entries = sorted(self.entries, key=lambda e: (e.date, e.id))
        raw = {
            "version": VERSION,
            "initialBalance": self.initial_balance,
            "initialBalanceCurrency": self.initial_balance_currency,
            "updatedAt": self.updated_at,
            "modelConfig": self.model_config,
            **self.extra,
            "entries": [e.to_dict() for e in entries],
        }
        return json.dumps(raw, ensure_ascii=False, indent=2).encode("utf-8")


def merge(doc: Document, new: list[Entry], imported_at: str) -> int:
    """Přidá záznamy s dosud neznámým `id`; existující nemění. Vrací počet přidaných."""
    known = {e.id for e in doc.entries}
    added = 0
    for e in new:
        if e.id in known:
            continue
        e.source = {**e.source, "importedAt": imported_at}
        doc.entries.append(e)
        known.add(e.id)
        added += 1
    return added
