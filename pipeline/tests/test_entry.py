from datetime import date

from runway.entry import Entry, normalize_account


def make_entry(**kw):
    base = dict(
        date=date(2024, 1, 4),
        amount_cents=-153500,
        currency="CZK",
        own_account=None,
        counter_account="107-2000145399",
        counter_bank_code="0100",
        message="",
        note="Elektřina doplatek",
        type="Okamžitá odchozí platba",
        variable_symbol=None,
        constant_symbol=None,
        specific_symbol=None,
        bank_transaction_id=None,
        source={"format": "fio-csv", "file": "pohyby.csv"},
    )
    base.update(kw)
    return Entry(**base)


def test_roundtrip():
    e = make_entry(id="abc", category={"kind": "expense", "type": "energie", "need": "nezbytné"})
    assert Entry.from_dict(e.to_dict()) == e


def test_to_dict_uses_spec_keys_and_amount():
    d = make_entry().to_dict()
    assert d["amount"] == -1535.0
    assert d["date"] == "2024-01-04"
    assert d["counterAccount"] == "107-2000145399"
    assert d["counterBankCode"] == "0100"
    assert d["ownAccount"] is None
    assert d["category"] is None


def test_normalize_account():
    assert normalize_account("000107-2000145399") == "107-2000145399"
    assert normalize_account("0000001234567890") == "1234567890"
    assert normalize_account("0001072000145399") == "107-2000145399"
    assert normalize_account("1234567890/2010") == "1234567890"
    assert normalize_account(" 107-2000145399 ") == "107-2000145399"
    assert normalize_account("") is None
    assert normalize_account("0") is None
    assert normalize_account(None) is None
