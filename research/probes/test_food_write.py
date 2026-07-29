"""
Confirms direct process-memory read/write against SnakeFoodsMemoryData
(the food/animal lifetime capture/eat log), the same AOB-free technique
as test_ammo_write.py/test_weapon_grant.py but for a heap-allocated
TMap instead of a flat exe-baked array.

Unlike WeaponsTable/ItemsTable, this data isn't baked into the exe at a
fixed module offset -- it lives on a per-save, heap-allocated
UUserProfileSaveGame object. The object's address is only discoverable
live (via UE4SS's FindFirstOf + :GetAddress(), see
FrogFlagReaderMod/main.lua's Ctrl+V keybind) -- everything after that is
pure pymem, no further UE4SS/Lua involvement.

Layout, from CXXHeaderDump's MGS3.hpp + live reverse-engineering this
session (confirmed against the known-good values already read via Lua
reflection, and cross-verified live via UE4SS's own reflection view
after a write -- see research/NOTES.md):

  UUserProfileSaveGame
    + 0x60: SnakeFoodsMemoryData (TMap<int32, FFoodMemoryData>, size 0x50)
      + 0x00: Data.Ptr (int64)   -- pointer to the TSetElement backing array
      + 0x08: Data.Count (int32)
      + 0x0C: Data.Max (int32)
      (bit array / hash table follow, not needed for element access)

  Backing array: contiguous TSetElement<TPair<int32, FFoodMemoryData>>,
  stride 24 bytes (0x18), in insertion order (confirmed 10/10 against a
  known 48-entry sequence, all captured/eaten food this session):
    +0x00: Key (int32)            -- food/animal ID, EWeaponName enum (31-130)
    +0x04: bCaptured (bool)
    +0x08: EatNum (int32)
    +0x0C: Type (byte)            -- EAnimalType
    +0x0D: bHeard (bool)
    +0x0E: bNewBadge (bool)
    +0x10: HashNextId (int32)     -- hash-chain bookkeeping, don't touch
    +0x14: HashIndex (int32)      -- hash-chain bookkeeping, don't touch

Only Key/bCaptured/EatNum/Type/bHeard/bNewBadge are safe to write --
they're plain value fields within an already-allocated slot, same risk
profile as any other confirmed-safe field write this project (ammo,
Gako_Life). Never touch Data.Ptr/Count/Max or the hash bookkeeping
fields directly; that's real TMap-internals corruption risk, unlike a
value field.

DATA_PTR/SLOT_INDEX below are only valid for the live game session they
were captured in -- Data.Ptr is a heap address that changes every
relaunch. Re-derive via the Ctrl+V probe each session; this script is a
worked example of the technique, not a reusable address.
"""

import pymem

PROCESS_NAME = "MGSDelta-Win64-Shipping.exe"
DATA_PTR = 0x1E0373A0510  # SnakeFoodsMemoryData.Data.Ptr, this session only
STRIDE = 24
SLOT_INDEX = 21  # id=91 (Fruit C), this session's insertion order

pm = pymem.Pymem(PROCESS_NAME)
slot_addr = DATA_PTR + SLOT_INDEX * STRIDE
eatnum_addr = slot_addr + 8

key = pm.read_int(slot_addr)
before = pm.read_int(eatnum_addr)
print(f"Slot {SLOT_INDEX}: key={key} EatNum BEFORE = {before}")

pm.write_int(eatnum_addr, before - 1)
print(f"EatNum AFTER write({before - 1}) = {pm.read_int(eatnum_addr)}")
# Cross-verified live via UE4SS's own reflection (Ctrl+F in FrogFlagReaderMod)
# during the real test run -- the game's own view matched this readback exactly.

pm.write_int(eatnum_addr, before)
print(f"EatNum RESTORED = {pm.read_int(eatnum_addr)}")
