"""CLI: `runway import` a `runway categorize`."""

from __future__ import annotations

import argparse
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

from dotenv import load_dotenv

from runway.importer import run_import
from runway.storage import AzureBlobStore, ConcurrencyError

PIPELINE_DIR = Path(__file__).resolve().parents[2]


def _store() -> AzureBlobStore:
    return AzureBlobStore(
        os.environ["AZURE_STORAGE_CONNECTION_STRING"],
        os.environ.get("RUNWAY_UPLOAD_CONTAINER", "upload"),
        os.environ.get("RUNWAY_APP_CONTAINER", "app"),
    )


def cmd_import(args: argparse.Namespace) -> int:
    report = run_import(_store(), os.environ.get("RUNWAY_OWN_ACCOUNT") or None, datetime.now(timezone.utc))
    print(f"Přidáno záznamů: {report.added}")
    for name in report.processed_files:
        print(f"  zpracováno: {name}")
    for name, error in report.failed_files.items():
        print(f"  CHYBA {name}: {error}", file=sys.stderr)
    if report.created_document:
        print("Vytvořen nový entries.json – doplňte ručně initialBalance.")
    return 1 if report.failed_files else 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="runway")
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("import", help="importuje výpisy z upload/inbox/").set_defaults(func=cmd_import)
    return parser


def main(argv: list[str] | None = None) -> int:
    for stream in (sys.stdout, sys.stderr):
        stream.reconfigure(encoding="utf-8")
    load_dotenv(PIPELINE_DIR / ".env")
    args = build_parser().parse_args(argv)
    try:
        return args.func(args)
    except ConcurrencyError as e:
        print(str(e), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
