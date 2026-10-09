#!/usr/bin/env python3
"""Сверяет строки интерфейса из последней сборки с каталогами .xcstrings.

Запуск после сборки (make ios-build или Xcode): python3 ios/scripts/check_strings.py
Печатает строки без английского перевода и строки, которых больше нет в коде.
"""

import glob
import json
import sys
from pathlib import Path

IOS = Path(__file__).resolve().parent.parent
TARGETS = {
    "LevelUp": IOS / "LevelUp/Resources/Localizable.xcstrings",
    "LevelUpWidgets": IOS / "LevelUpWidgets/Localizable.xcstrings",
}


def used_keys(target: str) -> set[str]:
    pattern = str(IOS / f"build/DerivedData/Build/Intermediates.noindex/*/*/{target}.build/**/*.stringsdata")
    keys: set[str] = set()
    for path in glob.glob(pattern, recursive=True):
        data = json.loads(Path(path).read_text())
        for entry in data.get("tables", {}).get("Localizable", []):
            keys.add(entry["key"])
    return keys


def main() -> int:
    problems = 0
    for target, catalog_path in TARGETS.items():
        keys = used_keys(target)
        if not keys:
            print(f"{target}: нет данных сборки — сначала собери проект")
            problems += 1
            continue
        strings = json.loads(catalog_path.read_text())["strings"]
        translated = {k for k, v in strings.items() if v.get("localizations", {}).get("en")}
        missing, stale = sorted(keys - translated), sorted(set(strings) - keys)
        print(f"{target}: {len(keys)} строк, без перевода: {len(missing)}, лишних: {len(stale)}")
        for key in missing:
            print(f"  + {key}")
        for key in stale:
            print(f"  - {key}")
        problems += len(missing)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
