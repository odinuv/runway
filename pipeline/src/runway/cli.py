"""CLI: `runway import` a `runway categorize`."""

from __future__ import annotations

import argparse
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

from dotenv import load_dotenv

from runway.categories import CategoryConfig, load_categories
from runway.categorizer import AzureLlmClient, LlmClient, categorize
from runway.importer import iso_utc, run_import
from runway.storage import AzureBlobStore, ConcurrencyError, Store

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


def run_categorize(
    store: Store, cfg: CategoryConfig, llm: LlmClient, model: str, batch_size: int, all_entries: bool, now: datetime
) -> tuple[int, int]:
    """Kategorizuje záznamy bez kategorie (nebo všechny); po každé dávce ukládá. Vrací (hotovo, zbývá)."""
    doc, etag = store.load_document()
    if all_entries:
        for e in doc.entries:
            e.category = None
    todo = [e for e in doc.entries if e.category is None]
    doc.model_config = {**doc.model_config, "excludedTypes": cfg.excluded_types}
    if not todo and etag is not None:
        return 0, 0

    def save() -> None:
        nonlocal etag
        doc.updated_at = iso_utc(datetime.now(timezone.utc))
        etag = store.save_document(doc, etag)

    left = categorize(todo, cfg, llm, batch_size, iso_utc(now), model, save)
    save()
    return len(todo) - len(left), len(left)


def cmd_categorize(args: argparse.Namespace) -> int:
    deployment = os.environ["AZURE_OPENAI_DEPLOYMENT"]
    llm = AzureLlmClient(os.environ["AZURE_OPENAI_ENDPOINT"], os.environ["AZURE_OPENAI_API_KEY"], deployment)
    cfg = load_categories(PIPELINE_DIR / "config" / "categories.json")
    done, left = run_categorize(_store(), cfg, llm, deployment, args.batch_size, args.all, datetime.now(timezone.utc))
    print(f"Kategorizováno: {done}, bez kategorie: {left}")
    return 1 if left else 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="runway")
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("import", help="importuje výpisy z upload/inbox/").set_defaults(func=cmd_import)
    cat = sub.add_parser("categorize", help="doplní kategorie přes Azure OpenAI")
    cat.add_argument("--all", action="store_true", help="překategorizuje i už kategorizované záznamy")
    cat.add_argument("--batch-size", type=int, default=30)
    cat.set_defaults(func=cmd_categorize)
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
