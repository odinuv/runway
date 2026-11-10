"""Přístup k Azure Blob Storage: kontejner `upload` (výpisy) a `app` (entries.json)."""

from __future__ import annotations

import time
from datetime import datetime, timezone
from pathlib import PurePosixPath
from typing import Callable, Protocol

from azure.core import MatchConditions
from azure.core.exceptions import ResourceExistsError, ResourceModifiedError, ResourceNotFoundError
from azure.storage.blob import BlobServiceClient, ContentSettings

from runway.document import Document

INBOX = "inbox/"
PROCESSED = "processed/"
DOCUMENT_BLOB = "entries.json"


class ConcurrencyError(Exception):
    pass


class Store(Protocol):
    def list_inbox(self) -> list[str]: ...
    def read_upload(self, name: str) -> bytes: ...
    def move_to_processed(self, name: str) -> None: ...
    def load_document(self) -> tuple[Document, str | None]: ...
    def save_document(self, doc: Document, etag: str | None) -> str: ...


def processed_name(name: str, exists: Callable[[str], bool]) -> str:
    """`inbox/x.csv` → `processed/x.csv`, případně s časovým razítkem, pokud cíl existuje."""
    target = PROCESSED + name.removeprefix(INBOX)
    if not exists(target):
        return target
    path = PurePosixPath(target)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%f")
    return str(path.with_name(f"{path.stem}-{stamp}{path.suffix}"))


class AzureBlobStore:
    def __init__(self, connection_string: str, upload_container: str, app_container: str):
        service = BlobServiceClient.from_connection_string(connection_string)
        self._upload = service.get_container_client(upload_container)
        self._app = service.get_container_client(app_container)

    def list_inbox(self) -> list[str]:
        return sorted(b.name for b in self._upload.list_blobs(name_starts_with=INBOX) if not b.name.endswith("/"))

    def read_upload(self, name: str) -> bytes:
        return self._upload.download_blob(name).readall()

    def move_to_processed(self, name: str) -> None:
        source = self._upload.get_blob_client(name)
        target = self._upload.get_blob_client(processed_name(name, lambda n: self._upload.get_blob_client(n).exists()))
        # Asynchronní kopie v rámci účtu se autorizuje klíčem cíle, zdroj nepotřebuje SAS.
        target.start_copy_from_url(source.url)
        while target.get_blob_properties().copy.status == "pending":
            time.sleep(0.5)
        status = target.get_blob_properties().copy.status
        if status != "success":
            raise RuntimeError(f"Kopie {name} do processed/ skončila stavem {status}")
        source.delete_blob()

    def load_document(self) -> tuple[Document, str | None]:
        try:
            downloader = self._app.download_blob(DOCUMENT_BLOB)
        except ResourceNotFoundError:
            return Document.new(), None
        return Document.from_json(downloader.readall()), downloader.properties.etag

    def save_document(self, doc: Document, etag: str | None) -> str:
        blob = self._app.get_blob_client(DOCUMENT_BLOB)
        if etag is None:
            # IfMissing nastaví If-None-Match: * sám; etag navíc by SDK propustilo až do HTTP klienta.
            conditions = {"match_condition": MatchConditions.IfMissing}
        else:
            conditions = {"etag": etag, "match_condition": MatchConditions.IfNotModified}
        try:
            result = blob.upload_blob(
                doc.to_json(),
                overwrite=True,
                content_settings=ContentSettings(content_type="application/json; charset=utf-8"),
                **conditions,
            )
        except (ResourceModifiedError, ResourceExistsError) as e:
            raise ConcurrencyError("entries.json mezitím změnil jiný proces – spusťte znovu.") from e
        return result["etag"]
