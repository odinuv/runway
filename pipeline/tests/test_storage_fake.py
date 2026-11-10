import pytest

from fakes import InMemoryStore
from runway.storage import ConcurrencyError


def test_empty_store_returns_new_document():
    doc, etag = InMemoryStore().load_document()
    assert etag is None
    assert doc.initial_balance == 0
    assert doc.entries == []


def test_save_with_stale_etag_fails():
    store = InMemoryStore()
    doc, etag = store.load_document()
    first = store.save_document(doc, etag)
    store.save_document(doc, first)
    with pytest.raises(ConcurrencyError):
        store.save_document(doc, first)


def test_create_fails_when_document_appeared():
    store = InMemoryStore()
    doc, _ = store.load_document()
    store.save_document(doc, None)
    with pytest.raises(ConcurrencyError):
        store.save_document(doc, None)


def test_inbox_listing_and_move():
    store = InMemoryStore(upload={"inbox/a.csv": b"1", "processed/old.csv": b"0", "inbox/": b""})
    assert store.list_inbox() == ["inbox/a.csv"]
    assert store.read_upload("inbox/a.csv") == b"1"
    store.move_to_processed("inbox/a.csv")
    store.upload["inbox/a.csv"] = b"2"
    store.move_to_processed("inbox/a.csv")
    assert store.list_inbox() == []
    processed = sorted(k for k in store.upload if k.startswith("processed/a"))
    assert len(processed) == 2
    assert {store.upload[k] for k in processed} == {b"1", b"2"}
