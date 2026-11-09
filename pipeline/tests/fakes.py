"""In-memory náhrada `Store` se stejnou sémantikou ETagu jako Azure."""

from __future__ import annotations

import itertools

from runway.document import Document
from runway.storage import INBOX, ConcurrencyError, processed_name

_etags = itertools.count(1)


class InMemoryStore:
    def __init__(self, upload: dict[str, bytes] | None = None, document: bytes | None = None):
        self.upload = dict(upload or {})
        self.document = document
        self.etag = f"e{next(_etags)}" if document is not None else None

    def list_inbox(self) -> list[str]:
        return sorted(k for k in self.upload if k.startswith(INBOX) and not k.endswith("/"))

    def read_upload(self, name: str) -> bytes:
        return self.upload[name]

    def move_to_processed(self, name: str) -> None:
        self.upload[processed_name(name, lambda n: n in self.upload)] = self.upload.pop(name)

    def load_document(self) -> tuple[Document, str | None]:
        if self.document is None:
            return Document.new(), None
        return Document.from_json(self.document), self.etag

    def save_document(self, doc: Document, etag: str | None) -> str:
        if etag != self.etag:
            raise ConcurrencyError("conflict")
        self.document = doc.to_json()
        self.etag = f"e{next(_etags)}"
        return self.etag
