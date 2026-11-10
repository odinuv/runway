"""ABO/GPC výpis (pevná délka řádků). Pozice polí jsou 0-based řezy."""

from __future__ import annotations

from datetime import datetime

from runway.entry import Entry, normalize_account

FORMAT = "gpc"

_CURRENCIES = {"203": "CZK", "978": "EUR", "840": "USD"}
_NEGATIVE_CODES = {"1", "5"}  # debet a storno kreditu
_POSITIVE_CODES = {"2", "4"}  # kredit a storno debetu


def _decode(data: bytes) -> str:
    # Striktní UTF-8 napřed: cp1250 dekóduje téměř cokoliv a rozbil by pevné šířky.
    try:
        return data.decode("utf-8")
    except UnicodeDecodeError:
        return data.decode("cp1250", errors="replace")


def _symbol(raw: str) -> str | None:
    return raw.strip().lstrip("0") or None


def _parse_line(line: str, own_account: str | None, filename: str) -> Entry:
    code = line[60]
    amount = int(line[48:60])
    if code in _NEGATIVE_CODES:
        amount = -amount
    elif code not in _POSITIVE_CODES:
        raise ValueError(f"Neznámý kód účtování {code!r}")
    bank_code = line[73:77]
    currency = line[117:122].lstrip("0")
    return Entry(
        date=datetime.strptime(line[122:128], "%d%m%y").date(),
        amount_cents=amount,
        currency=_CURRENCIES.get(currency, currency),
        own_account=own_account,
        counter_account=normalize_account(line[19:35]),
        counter_bank_code=None if bank_code.strip("0") == "" else bank_code,
        message="",
        note=line[97:117].rstrip(),
        type="",
        variable_symbol=_symbol(line[61:71]),
        constant_symbol=_symbol(line[77:81]),
        specific_symbol=_symbol(line[81:91]),
        bank_transaction_id=_symbol(line[35:48]),
        source={"format": FORMAT, "file": filename},
    )


def parse(data: bytes, filename: str, own_account: str | None) -> list[Entry]:
    own = normalize_account(own_account)
    entries = []
    for line in _decode(data).splitlines():
        if line.startswith("074"):
            own = normalize_account(line[3:19]) or own
        elif line.startswith("075"):
            entries.append(_parse_line(line, own, filename))
    return entries
