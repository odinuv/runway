import json
from dataclasses import replace
from datetime import date
from pathlib import Path

from runway.document import Document, assign_ids, merge
from runway.parsers import parse
from test_entry import make_entry

FIXTURES = Path(__file__).parent / "fixtures"


def test_identical_rows_get_distinct_ids():
    a, b = assign_ids([make_entry(), make_entry()])
    assert a.id and b.id and a.id != b.id


def test_ids_stable_across_parses():
    data = (FIXTURES / "pohyby.csv").read_bytes()
    first = [e.id for e in parse(data, "pohyby.csv", None)]
    second = [e.id for e in parse(data, "jiny-nazev.csv", None)]
    assert first == second
    assert len(set(first)) == 4


def test_merge_overlap():
    a, b, c = assign_ids([make_entry(note="a"), make_entry(note="b"), make_entry(note="c")])
    doc = Document.new()
    assert merge(doc, [a, b], "2026-11-09T10:00:00Z") == 2
    assert merge(doc, [replace(b), replace(c)], "2026-11-09T11:00:00Z") == 1
    assert len(doc.entries) == 3
    assert doc.entries[-1].source["importedAt"] == "2026-11-09T11:00:00Z"


def test_merge_keeps_category():
    (a,) = assign_ids([make_entry()])
    doc = Document.new()
    merge(doc, [replace(a, category={"kind": "expense", "type": "energie", "need": "nezbytné"})], "t")
    assert merge(doc, [replace(a)], "t2") == 0
    assert doc.entries[0].category["type"] == "energie"


def test_json_roundtrip_preserves_initial_balance_and_unknown_keys():
    (a,) = assign_ids([make_entry()])
    raw = {
        "version": 1,
        "initialBalance": 420000,
        "initialBalanceCurrency": "CZK",
        "updatedAt": "2026-11-09T10:00:00Z",
        "modelConfig": {"excludedTypes": ["spoření a investice"]},
        "poznamka": "ručně přidáno",
        "entries": [a.to_dict()],
    }
    doc = Document.from_json(json.dumps(raw).encode())
    out = json.loads(doc.to_json())
    assert out["initialBalance"] == 420000
    assert out["poznamka"] == "ručně přidáno"
    assert out["modelConfig"] == {"excludedTypes": ["spoření a investice"]}
    assert out["entries"] == [a.to_dict()]
    assert "Elektřina" in doc.to_json().decode("utf-8")


def test_entries_sorted_by_date():
    early, late = assign_ids([make_entry(date=date(2024, 1, 1)), make_entry(date=date(2024, 2, 1))])
    doc = Document.new()
    merge(doc, [late, early], "t")
    dates = [e["date"] for e in json.loads(doc.to_json())["entries"]]
    assert dates == ["2024-01-01", "2024-02-01"]
