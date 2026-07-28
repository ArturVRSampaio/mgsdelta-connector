"""
PoC: grant (unlock) a weapon the player doesn't currently have, via the
same WeaponsTable AOB technique proven in test_ammo_write.py.

Ported from WeaponItemManager.cs's ToggleWeapon(weapon, enable=true):
writes short(1) at the weapon entry's base address (offset 0 - the same
slot used for CurrentAmmo on weapons that track ammo).

Run this while MGS Delta is running, WITHOUT the Mosin equipped/owned,
then check the weapon select menu for it appearing.
"""

import re

import pymem

PROCESS_NAME = "MGSDelta-Win64-Shipping.exe"
MODULE_NAME = "MGSDelta-Win64-Shipping.exe"

WEAPONS_TABLE_PATTERN = bytes([0x00, 0x00, 0xAA, 0x77, 0x63, 0x00])
WEAPON_ENTRY_SIZE = 88
TABLE_HEADER_SIZE = len(WEAPONS_TABLE_PATTERN) + 16

RVA_RANGE_START = 0x135A0000
RVA_RANGE_END = 0x135F0000

# static readonly Weapon Mosin = new("Mosin", 15, "WeaponsTable", true, true, false);
MOSIN_INDEX = 15
MOSIN_NAME = "Mosin"

TOGGLE_ON = 1


def find_weapons_table(pm: pymem.Pymem) -> int | None:
    module_base = pm.base_address
    matches = pm.pattern_scan_module(
        re.escape(WEAPONS_TABLE_PATTERN), MODULE_NAME, return_multiple=True
    )
    if not matches:
        return None
    return next(
        (m for m in matches if RVA_RANGE_START <= (m - module_base) <= RVA_RANGE_END),
        None,
    )


def main() -> None:
    pm = pymem.Pymem(PROCESS_NAME)
    print(f"Attached to {PROCESS_NAME}")

    aob = find_weapons_table(pm)
    if aob is None:
        print("WeaponsTable not found in expected RVA range.")
        return
    print(f"WeaponsTable at 0x{aob:X}")

    weapon_base = aob + TABLE_HEADER_SIZE + (WEAPON_ENTRY_SIZE * MOSIN_INDEX)

    before = pm.read_short(weapon_base)
    print(f"{MOSIN_NAME} BEFORE (possession slot) = {before}")

    pm.write_short(weapon_base, TOGGLE_ON)

    after = pm.read_short(weapon_base)
    print(f"{MOSIN_NAME} AFTER = {after}")
    print("Check the weapon select menu in-game - did the Mosin appear?")


if __name__ == "__main__":
    main()
