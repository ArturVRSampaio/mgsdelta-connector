"""
One-shot parser: extracts the full weapon/item index tables from the
vendored reference trainer source (WeaponItemManager.cs) into a plain JSON
file, so mgs_memory.py doesn't need the C# source at runtime and nobody has
to hand-transcribe ~169 entries (error-prone).
"""

import json
import re
from pathlib import Path

SRC = Path(__file__).parent.parent / "MGS3-Delta-Trainer-ref" / "WeaponItemManager.cs"
OUT = Path(__file__).parent / "weapon_item_index.json"

WEAPON_RE = re.compile(
    r'static readonly Weapon \w+ = new\("([^"]+)",\s*(\d+),\s*"WeaponsTable",\s*'
    r"(true|false),\s*(true|false),\s*(true|false)\)"
)
ITEM_RE = re.compile(
    r'static readonly Item \w+ = new\s*\("([^"]+)",\s*(\d+),\s*"ItemsTable",\s*(true|false)\)'
)


def main() -> None:
    text = SRC.read_text()

    weapons = []
    for m in WEAPON_RE.finditer(text):
        name, index, has_ammo, has_clip, has_suppressor = m.groups()
        weapons.append(
            {
                "index": int(index),
                "name": name,
                "has_ammo": has_ammo == "true",
                "has_clip": has_clip == "true",
                "has_suppressor": has_suppressor == "true",
            }
        )

    items = []
    for m in ITEM_RE.finditer(text):
        name, index, has_capacity = m.groups()
        items.append(
            {
                "index": int(index),
                "name": name,
                "has_capacity": has_capacity == "true",
            }
        )

    weapons.sort(key=lambda w: w["index"])
    items.sort(key=lambda i: i["index"])

    print(f"Parsed {len(weapons)} weapons, {len(items)} items")

    # Sanity check: indices must be contiguous from 0, no gaps/dupes.
    for label, entries in (("weapon", weapons), ("item", items)):
        indices = [e["index"] for e in entries]
        expected = list(range(len(entries)))
        if indices != expected:
            missing = sorted(set(expected) - set(indices))
            dupes = sorted({i for i in indices if indices.count(i) > 1})
            raise SystemExit(
                f"{label} indices not contiguous from 0: missing={missing} dupes={dupes}"
            )

    OUT.write_text(json.dumps({"weapons": weapons, "items": items}, indent=2))
    print(f"Wrote {OUT}")


if __name__ == "__main__":
    main()
