from datetime import datetime, timezone
from pathlib import Path

import pytest

from fakes import InMemoryStore
from runway.document import Document
from runway.importer import run_import
from runway.storage import ConcurrencyError

FIXTURES = Path(__file__).parent / "fixtures"
NOW = datetime(2026, 11, 9, 10, 0, tzinfo=timezone.utc)
CSV = (FIXTURES / "pohyby.csv").read_bytes()
GPC = (FIXTURES / "pohyby.gpc").read_bytes()


def test_import_sample_files():
    store = InMemoryStore(upload={"inbox/pohyby.csv": CSV, "inbox/pohyby.gpc": GPC})
    report = run_import(store, None, NOW)
    assert report.added == 7
    assert report.created_document
    assert sorted(report.processed_files) == ["inbox/pohyby.csv", "inbox/pohyby.gpc"]
    assert store.list_inbox() == []
    assert {"processed/pohyby.csv", "processed/pohyby.gpc"} <= set(store.upload)
    doc, _ = store.load_document()
    assert len(doc.entries) == 7
    assert doc.updated_at == "2026-11-09T10:00:00Z"


def test_reimport_adds_nothing():
    store = InMemoryStore(upload={"inbox/pohyby.csv": CSV})
    run_import(store, None, NOW)
    store.upload["inbox/pohyby.csv"] = CSV
    report = run_import(store, None, NOW)
    assert report.added == 0
    assert not report.created_document
    assert store.list_inbox() == []


def test_bad_file_does_not_block():
    store = InMemoryStore(
        upload={"inbox/pohyby.csv": CSV, "inbox/junk.txt": b"x", "inbox/broken.gpc": b"075\xff\x00garbage"}
    )
    report = run_import(store, None, NOW)
    assert report.added == 4
    assert set(report.failed_files) == {"inbox/junk.txt", "inbox/broken.gpc"}
    assert store.list_inbox() == ["inbox/broken.gpc", "inbox/junk.txt"]


def test_initial_balance_preserved():
    doc = Document.new()
    doc.initial_balance = 420000
    store = InMemoryStore(upload={"inbox/pohyby.csv": CSV}, document=doc.to_json())
    run_import(store, None, NOW)
    saved, _ = store.load_document()
    assert saved.initial_balance == 420000


def test_concurrency_error_moves_nothing():
    class Conflicting(InMemoryStore):
        def save_document(self, doc, etag):
            raise ConcurrencyError("conflict")

    store = Conflicting(upload={"inbox/pohyby.csv": CSV})
    with pytest.raises(ConcurrencyError):
        run_import(store, None, NOW)
    assert store.list_inbox() == ["inbox/pohyby.csv"]
