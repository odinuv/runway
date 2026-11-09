import json
from datetime import date
from pathlib import Path

from runway.categories import CategoryConfig, load_categories
from runway.categorizer import categorize
from test_entry import make_entry

CONFIG_PATH = Path(__file__).parents[1] / "config" / "categories.json"

CFG = CategoryConfig(
    expense_types=[{"id": "energie", "description": "elektřina"}, {"id": "živobytí", "description": "jídlo"}],
    needs=[{"id": n, "description": n} for n in ["nezbytné", "vhodné", "zbytné", "nečekané"]],
    income_types=[{"id": "pravidelný", "description": "výplata"}, {"id": "nepravidelný", "description": "vratky"}],
    excluded_types=[],
)


class FakeLlm:
    def __init__(self, responses):
        self.responses = list(responses)
        self.calls = []

    def complete_json(self, system, user, schema):
        self.calls.append({"system": system, "items": json.loads(user), "schema": schema})
        response = self.responses.pop(0)
        return response(self.calls[-1]["items"]) if callable(response) else response


def all_expenses(items):
    return {"items": [{"i": it["i"], "type": "energie", "need": "nezbytné"} for it in items]}


def run(entries, llm, batch_size=30):
    batches = []
    left = categorize(entries, CFG, llm, batch_size, "2026-11-09T10:00:00Z", "gpt-x", lambda: batches.append(1))
    return left, batches


def test_expenses_and_income_split():
    entries = [make_entry(), make_entry(note="x"), make_entry(amount_cents=6000000, note="Výplata")]
    llm = FakeLlm([all_expenses, lambda items: {"items": [{"i": 0, "incomeType": "pravidelný"}]}])
    left, _ = run(entries, llm)
    assert left == []
    assert len(llm.calls) == 2
    assert entries[0].category == {
        "kind": "expense", "type": "energie", "need": "nezbytné", "model": "gpt-x", "categorizedAt": "2026-11-09T10:00:00Z"
    }
    assert entries[2].category["kind"] == "income"
    assert entries[2].category["incomeType"] == "pravidelný"
    assert llm.calls[1]["items"][0]["amount"] == 60000.0


def test_invalid_values_retried_once():
    a, b = make_entry(note="a"), make_entry(note="b")
    llm = FakeLlm([
        {"items": [{"i": 0, "type": "energie", "need": "luxus"}]},
        {"items": [{"i": 1, "type": "energie", "need": "zbytné"}]},
    ])
    left, _ = run([a, b], llm)
    assert len(llm.calls) == 2
    assert [it["note"] for it in llm.calls[1]["items"]] == ["a", "b"]
    assert a.category is None
    assert b.category["need"] == "zbytné"
    assert left == [a]


def test_foreign_index_ignored():
    a = make_entry()
    llm = FakeLlm([{"items": [{"i": 99, "type": "energie", "need": "nezbytné"}, {"i": 0, "type": "energie", "need": "vhodné"}]}])
    left, _ = run([a], llm)
    assert left == []
    assert a.category["need"] == "vhodné"


def test_schema_enums_from_config():
    llm = FakeLlm([all_expenses])
    run([make_entry()], llm)
    item = llm.calls[0]["schema"]["properties"]["items"]["items"]["properties"]
    assert item["type"]["enum"] == ["energie", "živobytí"]
    assert item["need"]["enum"] == ["nezbytné", "vhodné", "zbytné", "nečekané"]
    assert "energie" in llm.calls[0]["system"] and "elektřina" in llm.calls[0]["system"]


def test_batching():
    entries = [make_entry(note=str(i)) for i in range(65)]
    llm = FakeLlm([all_expenses] * 3)
    left, batches = run(entries, llm)
    assert [len(c["items"]) for c in llm.calls] == [30, 30, 5]
    assert len(batches) == 3
    assert left == []


def test_llm_exception_leaves_batch_uncategorized():
    def boom(items):
        raise RuntimeError("rate limit")

    entries = [make_entry(note="a"), make_entry(note="b", date=date(2024, 2, 1))]
    llm = FakeLlm([boom] * 4)
    left, _ = run(entries, llm, batch_size=1)
    assert left == entries


def test_categories_json_valid():
    cfg = load_categories(CONFIG_PATH)
    assert cfg.excluded_types == ["spoření a investice"]
    assert [n["id"] for n in cfg.needs] == ["nezbytné", "vhodné", "zbytné", "nečekané"]
    assert [t["id"] for t in cfg.income_types] == ["pravidelný", "nepravidelný"]
    assert [t["id"] for t in cfg.expense_types] == [
        "bydlení", "energie", "živobytí", "doprava", "zdraví", "děti", "pojištění", "poplatky a předplatné",
        "komunikace", "oblečení", "volný čas", "dovolená", "dary", "spoření a investice", "ostatní",
    ]


def test_run_categorize_saves_and_skips_done():
    from datetime import datetime, timezone

    from fakes import InMemoryStore
    from runway.cli import run_categorize
    from runway.document import Document, assign_ids

    doc = Document.new()
    doc.entries = assign_ids([make_entry(note="a"), make_entry(note="b", category={"kind": "expense"})])
    store = InMemoryStore(document=doc.to_json())
    cfg = load_categories(CONFIG_PATH)
    llm = FakeLlm([lambda items: {"items": [{"i": 0, "type": "energie", "need": "nezbytné"}]}])
    now = datetime(2026, 11, 9, tzinfo=timezone.utc)

    done, left = run_categorize(store, cfg, llm, "gpt-x", 30, False, now)
    assert (done, left) == (1, 0)
    assert len(llm.calls) == 1 and [it["note"] for it in llm.calls[0]["items"]] == ["a"]
    saved, _ = store.load_document()
    assert saved.model_config == {"excludedTypes": ["spoření a investice"]}
    assert all(e.category for e in saved.entries)

    assert run_categorize(store, cfg, FakeLlm([]), "gpt-x", 30, False, now) == (0, 0)
