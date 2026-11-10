"""Pevný seznam kategorií z `config/categories.json`."""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path


@dataclass
class CategoryConfig:
    expense_types: list[dict]
    needs: list[dict]
    income_types: list[dict]
    excluded_types: list[str]


def load_categories(path: Path) -> CategoryConfig:
    raw = json.loads(path.read_text(encoding="utf-8"))
    return CategoryConfig(
        expense_types=raw["expenseTypes"],
        needs=raw["needs"],
        income_types=raw["incomeTypes"],
        excluded_types=[t["id"] for t in raw["expenseTypes"] if t.get("excludeFromModel")],
    )
