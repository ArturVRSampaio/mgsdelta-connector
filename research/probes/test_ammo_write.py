"""
Standalone PoC: prove ammo can be written via direct process-memory AOB scan,
ported from ANTIBigBoss/MGS3-Delta-Trainer (C#) to Python/pymem.

This bypasses UE4SS/Blueprint reflection entirely. The Blueprint setters we
tried all night (SetStockedAmmoCount, SetLoadedAmmoCount, etc.) are no-ops
because the real, HUD-authoritative ammo state lives in a flat native
WeaponsTable baked into the exe image, found only by byte-pattern scan -
it's not a UObject and has no reflection metadata UE4SS could ever see.

Run this while MGS Delta is running with the MK22 pistol equipped.
"""

import re

import pymem

PROCESS_NAME = "MGSDelta-Win64-Shipping.exe"
MODULE_NAME = "MGSDelta-Win64-Shipping.exe"

# From AobManager.cs "WeaponsTable" entry
WEAPONS_TABLE_PATTERN = bytes([0x00, 0x00, 0xAA, 0x77, 0x63, 0x00])
WEAPON_ENTRY_SIZE = 88  # WeaponAddresses.WeaponOffset
CURRENT_AMMO_OFFSET = 0
MAX_AMMO_OFFSET = 2
CLIP_OFFSET = 4
MAX_CLIP_OFFSET = 6

# static readonly Weapon MK22 = new("MK22", 4, "WeaponsTable", true, true, true);
MK22_INDEX = 4

# Constants.cs: Pattern.Length (6) + 16 fixed header bytes, then WeaponOffset * index
TABLE_HEADER_SIZE = len(WEAPONS_TABLE_PATTERN) + 16


# AobManager.cs restricted the "WeaponsTable" scan to this RVA range - the
# pattern apparently repeats elsewhere in the module, so an unrestricted
# full-module scan can return a false-positive match.
RVA_RANGE_START = 0x135A0000
RVA_RANGE_END = 0x135F0000


def main() -> None:
    pm = pymem.Pymem(PROCESS_NAME)
    print(f"Attached to {PROCESS_NAME}, base module {MODULE_NAME}")

    module_base = pm.base_address
    print(f"Module base: 0x{module_base:X}")

    matches = pm.pattern_scan_module(
        re.escape(WEAPONS_TABLE_PATTERN), MODULE_NAME, return_multiple=True
    )
    if not matches:
        print("WeaponsTable pattern NOT found at all. Game version may differ from trainer's.")
        return
    print(f"Found {len(matches)} match(es) for the pattern:")
    for m in matches:
        rva = m - module_base
        in_range = RVA_RANGE_START <= rva <= RVA_RANGE_END
        print(f"  0x{m:X} (RVA 0x{rva:X}) {'<-- in expected range' if in_range else ''}")

    aob = next((m for m in matches if RVA_RANGE_START <= (m - module_base) <= RVA_RANGE_END), None)
    if aob is None:
        print("None of the matches fall in the expected RVA range - can't proceed safely.")
        return
    print(f"Using WeaponsTable at 0x{aob:X}")

    mk22_base = aob + TABLE_HEADER_SIZE + (WEAPON_ENTRY_SIZE * MK22_INDEX)
    current_addr = mk22_base + CURRENT_AMMO_OFFSET
    clip_addr = mk22_base + CLIP_OFFSET

    current_ammo = pm.read_short(current_addr)
    clip = pm.read_short(clip_addr)
    print(f"MK22 BEFORE: current_ammo={current_ammo} clip={clip}")

    pm.write_short(current_addr, 999)
    pm.write_short(clip_addr, 12)

    current_ammo_after = pm.read_short(current_addr)
    clip_after = pm.read_short(clip_addr)
    print(f"MK22 AFTER:  current_ammo={current_ammo_after} clip={clip_after}")
    print("Now check in-game HUD/inventory for the MK22 - did the ammo actually change?")


if __name__ == "__main__":
    main()
