"""
Reusable native process-memory access for MGS Delta, built on top of the
confirmed AOB technique in test_ammo_write.py/test_weapon_grant.py.

Not yet promoted into mgsdelta_connector/ - this is still the exploration
tool used to systematically strip and re-grant the weapon/item tables one
entry at a time against a real save, per research/unlockables-and-checks.md.
"""

from __future__ import annotations

import json
import re
from dataclasses import dataclass
from pathlib import Path

import pymem

PROCESS_NAME = "MGSDelta-Win64-Shipping.exe"
MODULE_NAME = "MGSDelta-Win64-Shipping.exe"

WEAPONS_TABLE_PATTERN = bytes([0x00, 0x00, 0xAA, 0x77, 0x63, 0x00])
WEAPONS_RVA_RANGE = (0x135A0000, 0x135F0000)
WEAPON_ENTRY_SIZE = 88
WEAPON_HEADER_SIZE = len(WEAPONS_TABLE_PATTERN) + 16

ITEMS_TABLE_PATTERN = bytes([0x00, 0x00, 0xDA, 0x5A, 0x2B, 0x00])
ITEMS_RVA_RANGE = (0x13400000, 0x135FEEEE)
ITEM_ENTRY_SIZE = 80
ITEM_HEADER_SIZE = len(ITEMS_TABLE_PATTERN) + 12

# Weapons without ammo use offset 0 as a plain owned(1)/not-owned(-1) flag;
# weapons with ammo still use offset 0 for CurrentAmmo, and "owning" one
# means writing a positive ammo count there (0 reads as unowned in-game).
NOT_OWNED = -1
OWNED_FLAG = 1

INDEX_PATH = Path(__file__).parent / "weapon_item_index.json"


@dataclass(frozen=True)
class WeaponEntry:
    index: int
    name: str
    has_ammo: bool
    has_clip: bool
    has_suppressor: bool


@dataclass(frozen=True)
class ItemEntry:
    index: int
    name: str
    has_capacity: bool


def load_index() -> tuple[list[WeaponEntry], list[ItemEntry]]:
    data = json.loads(INDEX_PATH.read_text())
    weapons = [WeaponEntry(**w) for w in data["weapons"]]
    items = [ItemEntry(**i) for i in data["items"]]
    return weapons, items


class MGSMemory:
    def __init__(self) -> None:
        self.pm = pymem.Pymem(PROCESS_NAME)
        self._weapons_table: int | None = None
        self._items_table: int | None = None

    def _find_table(self, pattern: bytes, rva_range: tuple[int, int]) -> int:
        module_base = self.pm.base_address
        matches = self.pm.pattern_scan_module(re.escape(pattern), MODULE_NAME, return_multiple=True)
        if not matches:
            raise RuntimeError("Pattern not found at all - game version may have changed.")
        start, end = rva_range
        match = next((m for m in matches if start <= (m - module_base) <= end), None)
        if match is None:
            raise RuntimeError(
                f"No match in expected RVA range 0x{start:X}-0x{end:X} "
                f"({len(matches)} match(es) elsewhere in the module)."
            )
        return match

    @property
    def weapons_table(self) -> int:
        if self._weapons_table is None:
            self._weapons_table = self._find_table(WEAPONS_TABLE_PATTERN, WEAPONS_RVA_RANGE)
        return self._weapons_table

    @property
    def items_table(self) -> int:
        if self._items_table is None:
            self._items_table = self._find_table(ITEMS_TABLE_PATTERN, ITEMS_RVA_RANGE)
        return self._items_table

    def weapon_base(self, index: int) -> int:
        return self.weapons_table + WEAPON_HEADER_SIZE + (WEAPON_ENTRY_SIZE * index)

    def item_base(self, index: int) -> int:
        return self.items_table + ITEM_HEADER_SIZE + (ITEM_ENTRY_SIZE * index)

    def read_weapon_possession(self, index: int) -> int:
        return self.pm.read_short(self.weapon_base(index))

    def read_item_possession(self, index: int) -> int:
        return self.pm.read_short(self.item_base(index))

    def strip_weapon(self, weapon: WeaponEntry) -> None:
        base = self.weapon_base(weapon.index)
        self.pm.write_short(base, NOT_OWNED)  # CurrentAmmo / possession flag
        if weapon.has_ammo:
            self.pm.write_short(base + 2, 0)  # MaxAmmo
        if weapon.has_clip:
            self.pm.write_short(base + 4, 0)  # Clip
            self.pm.write_short(base + 6, 0)  # MaxClip

    def strip_item(self, item: ItemEntry) -> None:
        base = self.item_base(item.index)
        self.pm.write_short(base, NOT_OWNED if not item.has_capacity else 0)
        if item.has_capacity:
            self.pm.write_short(base + 2, 0)  # Max

    def grant_weapon(self, weapon: WeaponEntry, ammo: int = 1) -> None:
        base = self.weapon_base(weapon.index)
        self.pm.write_short(base, ammo if weapon.has_ammo else OWNED_FLAG)
        if weapon.has_ammo:
            self.pm.write_short(base + 2, max(ammo, 1))  # MaxAmmo
        if weapon.has_clip:
            self.pm.write_short(base + 4, max(ammo, 1))
            self.pm.write_short(base + 6, max(ammo, 1))

    def grant_item(self, item: ItemEntry, capacity: int = 1) -> None:
        base = self.item_base(item.index)
        self.pm.write_short(base, capacity if item.has_capacity else OWNED_FLAG)
        if item.has_capacity:
            self.pm.write_short(base + 2, max(capacity, 1))

    # --- Equipped state (separate mechanism from the AOB tables above) ---
    # Constants.cs' MainPointerAddresses: a static pointer at
    # module_base + MAIN_POINTER_REGION_OFFSET, dereferenced once, then
    # offset by a fixed byte for each "equipped" slot. Untested for Delta
    # specifically (unlike the AOB tables) - confirm empirically before
    # trusting these values.
    MAIN_POINTER_REGION_OFFSET = 0xC532038
    EQUIPPED_WEAPON_OFFSET = 1144
    EQUIPPED_ITEM_OFFSET = 1142
    EQUIPPED_CAMO_OFFSET = 974
    EQUIPPED_FACEPAINT_OFFSET = 973

    def _deref_main_pointer(self) -> int:
        return self.pm.read_ulonglong(self.pm.base_address + self.MAIN_POINTER_REGION_OFFSET)

    def read_equipped_camo(self) -> int:
        return self.pm.read_uchar(self._deref_main_pointer() + self.EQUIPPED_CAMO_OFFSET)

    def read_equipped_facepaint(self) -> int:
        return self.pm.read_uchar(self._deref_main_pointer() + self.EQUIPPED_FACEPAINT_OFFSET)

    def read_equipped_weapon(self) -> int:
        return self.pm.read_uchar(self._deref_main_pointer() + self.EQUIPPED_WEAPON_OFFSET)

    def read_equipped_item(self) -> int:
        return self.pm.read_uchar(self._deref_main_pointer() + self.EQUIPPED_ITEM_OFFSET)

    def write_equipped_camo(self, value: int) -> None:
        self.pm.write_uchar(self._deref_main_pointer() + self.EQUIPPED_CAMO_OFFSET, value)

    def write_equipped_facepaint(self, value: int) -> None:
        self.pm.write_uchar(self._deref_main_pointer() + self.EQUIPPED_FACEPAINT_OFFSET, value)
