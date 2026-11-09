from datetime import date
from pathlib import Path

import pytest

from runway.parsers import UnsupportedFormat, parse

FIXTURES = Path(__file__).parent / "fixtures"
CSV_HEADER = '\ufeff"Datum";"Objem";"Měna";"Protiúčet";"Kód banky";"Zpráva pro příjemce";"Poznámka";"Typ"\r\n'


def gpc_line(code: str, amount: str = "000000010000", note: str = "Test") -> str:
    return (
        "075"
        + "0000001234567890"
        + "0000000000000000"
        + "0000000000001"
        + amount
        + code
        + "0" * 30
        + "040124"
        + note.ljust(20)[:20]
        + "00203"
        + "040124"
    )


GPC_HEADER = "0740000001234567890" + "Test".ljust(20) + "010124" + "0" * 14 + "+" + "0" * 14 + "+" + "0" * 14 + "0" + "0" * 14 + "0" + "000" + "091126" + "FIO".ljust(14)


def test_fio_csv_sample():
    entries = parse((FIXTURES / "pohyby.csv").read_bytes(), "pohyby.csv", None)
    assert len(entries) == 4
    first, _, third, _ = entries
    assert first.amount_cents == -33219
    assert first.counter_account is None
    assert first.counter_bank_code is None
    assert third.date == date(2024, 1, 4)
    assert third.amount_cents == -153500
    assert third.counter_account == "107-2000145399"
    assert third.counter_bank_code == "0100"
    assert third.note.startswith("Elektřina doplatek")
    assert third.type == "Okamžitá odchozí platba"
    assert third.source == {"format": "fio-csv", "file": "pohyby.csv"}


def test_fio_csv_own_account_from_parameter():
    entries = parse((FIXTURES / "pohyby.csv").read_bytes(), "pohyby.csv", "1234567890/2010")
    assert {e.own_account for e in entries} == {"1234567890"}


def test_fio_csv_header_only():
    assert parse(CSV_HEADER.encode("utf-8"), "x.csv", None) == []


def test_fio_csv_thousands_separator():
    rows = (
        '"01.02.2024";"-12 345,50";"CZK";"";"";"";"a";"Platba"\r\n'
        '"02.02.2024";"1\xa0000";"CZK";"";"";"";"b";"Platba"\r\n'
    )
    entries = parse((CSV_HEADER + rows).encode("utf-8"), "x.csv", None)
    assert [e.amount_cents for e in entries] == [-1234550, 100000]


def test_gpc_sample():
    entries = parse((FIXTURES / "pohyby.gpc").read_bytes(), "pohyby.gpc", None)
    assert len(entries) == 3
    assert {e.own_account for e in entries} == {"1234567890"}
    third = entries[2]
    assert third.amount_cents == -153500
    assert third.counter_account == "107-2000145399"
    assert third.counter_bank_code == "0100"
    assert third.bank_transaction_id == "10000000003"
    assert third.variable_symbol == "1234512345"
    assert third.constant_symbol is None
    assert third.currency == "CZK"
    assert third.date == date(2024, 1, 4)
    assert entries[0].counter_account is None
    assert entries[0].counter_bank_code is None
    assert third.source == {"format": "gpc", "file": "pohyby.gpc"}


def test_gpc_credit_and_storno():
    text = "\r\n".join([GPC_HEADER, gpc_line("2"), gpc_line("4"), gpc_line("5"), gpc_line("1")])
    entries = parse(text.encode("cp1250"), "x.GPC", None)
    assert [e.amount_cents for e in entries] == [10000, 10000, -10000, -10000]


def test_gpc_cp1250():
    text = (FIXTURES / "pohyby.gpc").read_text(encoding="utf-8")
    text = text.replace("N\ufffdkup", "Nákup").replace("Elekt\ufffdina", "Elektřina").replace("Ond\ufffdej", "Ondřej")
    entries = parse(text.encode("cp1250"), "pohyby.gpc", None)
    assert entries[0].note.startswith("Nákup")
    assert entries[2].note.startswith("Elektřina")


def test_unknown_extension():
    with pytest.raises(UnsupportedFormat):
        parse(b"whatever", "vypis.pdf", None)
