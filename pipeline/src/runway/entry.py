"""Normalizovaný záznam bankovního výpisu."""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from datetime import date


def normalize_account(raw: str | None) -> str | None:
    """Číslo účtu ve tvaru `prefix-číslo` bez kódu banky a úvodních nul."""
    if raw is None:
        return None
    value = re.sub(r"\s", "", raw).split("/")[0]
    if "-" in value:
        prefix, number = value.split("-", 1)
    elif len(value) > 10:
        prefix, number = value[:-10], value[-10:]
    else:
        prefix, number = "", value
    prefix = prefix.lstrip("0")
    number = number.lstrip("0")
    if not number:
        return None
    return f"{prefix}-{number}" if prefix else number


@dataclass
class Entry:
    date: date
    amount_cents: int
    currency: str
    own_account: str | None
    counter_account: str | None
    counter_bank_code: str | None
    message: str
    note: str
    type: str
    variable_symbol: str | None
    constant_symbol: str | None
    specific_symbol: str | None
    bank_transaction_id: str | None
    source: dict = field(default_factory=dict)
    id: str = ""
    category: dict | None = None

    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "date": self.date.isoformat(),
            "amount": self.amount_cents / 100,
            "currency": self.currency,
            "ownAccount": self.own_account,
            "counterAccount": self.counter_account,
            "counterBankCode": self.counter_bank_code,
            "message": self.message,
            "note": self.note,
            "type": self.type,
            "variableSymbol": self.variable_symbol,
            "constantSymbol": self.constant_symbol,
            "specificSymbol": self.specific_symbol,
            "bankTransactionId": self.bank_transaction_id,
            "source": self.source,
            "category": self.category,
        }

    @classmethod
    def from_dict(cls, d: dict) -> Entry:
        return cls(
            id=d.get("id", ""),
            date=date.fromisoformat(d["date"]),
            amount_cents=round(d["amount"] * 100),
            currency=d.get("currency", "CZK"),
            own_account=d.get("ownAccount"),
            counter_account=d.get("counterAccount"),
            counter_bank_code=d.get("counterBankCode"),
            message=d.get("message", ""),
            note=d.get("note", ""),
            type=d.get("type", ""),
            variable_symbol=d.get("variableSymbol"),
            constant_symbol=d.get("constantSymbol"),
            specific_symbol=d.get("specificSymbol"),
            bank_transaction_id=d.get("bankTransactionId"),
            source=d.get("source") or {},
            category=d.get("category"),
        )
