"""Parsery bankovních výpisů. Nový formát = nový modul + záznam v `_PARSERS`."""

from __future__ import annotations

from pathlib import PurePosixPath

from runway.document import assign_ids
from runway.entry import Entry
from runway.parsers import fio_csv, gpc


class UnsupportedFormat(Exception):
    pass


_PARSERS = {
    ".csv": fio_csv.parse,
    ".gpc": gpc.parse,
}


def parse(data: bytes, filename: str, own_account: str | None) -> list[Entry]:
    suffix = PurePosixPath(filename).suffix.lower()
    parser = _PARSERS.get(suffix)
    if parser is None:
        raise UnsupportedFormat(f"Nepodporovaný formát souboru: {filename}")
    return assign_ids(parser(data, PurePosixPath(filename).name, own_account))
