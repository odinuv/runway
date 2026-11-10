"""Import výpisů z `upload/inbox/` do `app/entries.json`."""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, timezone

from runway.document import merge
from runway.entry import Entry
from runway.parsers import parse
from runway.storage import Store


@dataclass
class ImportReport:
    added: int = 0
    processed_files: list[str] = field(default_factory=list)
    failed_files: dict[str, str] = field(default_factory=dict)
    created_document: bool = False


def iso_utc(moment: datetime) -> str:
    return moment.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def run_import(store: Store, own_account: str | None, now: datetime) -> ImportReport:
    report = ImportReport()
    doc, etag = store.load_document()
    report.created_document = etag is None

    parsed: list[Entry] = []
    for name in store.list_inbox():
        try:
            parsed.extend(parse(store.read_upload(name), name, own_account))
        except Exception as e:  # jeden vadný soubor nesmí zablokovat ostatní
            report.failed_files[name] = f"{type(e).__name__}: {e}"
            continue
        report.processed_files.append(name)

    stamp = iso_utc(now)
    report.added = merge(doc, parsed, stamp)
    if report.added or report.created_document:
        doc.updated_at = stamp
        store.save_document(doc, etag)

    # Přesun až po úspěšném uložení, aby se při chybě nic neztratilo.
    for name in report.processed_files:
        store.move_to_processed(name)
    return report
