"""Fio CSV export (UTF-8 s BOM, `;`, desetinná čárka)."""

from __future__ import annotations

import csv
import io
import re
from datetime import datetime
from decimal import Decimal

from runway.entry import Entry, normalize_account

FORMAT = "fio-csv"


def parse_amount_cents(raw: str) -> int:
    value = re.sub(r"[\s\xa0]", "", raw).replace(",", ".")
    return int(Decimal(value) * 100)


def parse(data: bytes, filename: str, own_account: str | None) -> list[Entry]:
    reader = csv.DictReader(io.StringIO(data.decode("utf-8-sig")), delimiter=";")
    own = normalize_account(own_account)
    entries = []
    for row in reader:
        entries.append(
            Entry(
                date=datetime.strptime(row["Datum"].strip(), "%d.%m.%Y").date(),
                amount_cents=parse_amount_cents(row["Objem"]),
                currency=row["Měna"].strip(),
                own_account=own,
                counter_account=normalize_account(row["Protiúčet"]),
                counter_bank_code=row["Kód banky"].strip() or None,
                message=row["Zpráva pro příjemce"].strip(),
                note=row["Poznámka"].strip(),
                type=row["Typ"].strip(),
                variable_symbol=None,
                constant_symbol=None,
                specific_symbol=None,
                bank_transaction_id=None,
                source={"format": FORMAT, "file": filename},
            )
        )
    return entries
