"""
Direct-memory port of the "Foods" code-injection hook from
research/MGS3-Delta-Trainer-ref/mgsd_ce_table_v9.ct (community CE table,
author RMLSNK), replicated via raw pymem/ctypes instead of loading it in
the actual Cheat Engine GUI.

Unlike WeaponsTable/ItemsTable (passive AOB scan over static exe-baked
data -- pure reads/writes, no crash risk), this hooks a live instruction
inside the game's own compiled code (the function that resolves which
food type occupies a given equip-swap slot) to capture a transient RAX
register value that only exists during that function's execution. This
is categorically riskier than every other technique in this project so
far: get an offset/length wrong and it corrupts the instruction stream,
not just misreads a value.

Original instructions being hooked (from the .ct's own disassembly,
MGSDelta-Win64-Shipping.exe.text+7A9BD33, patch version 1.1.3):
    4C 63 00                 movsxd  r8, dword ptr [rax]
    41 81 F8 82 00 00 00     cmp     r8d, 0x82

AOB pattern (includes one trailing byte of the preceding instruction for
uniqueness, same convention as the WeaponsTable/ItemsTable patterns):
    D3 4C 63 00 41 81 F8 82 00 00 00
Patch point is aob_address + 1 (skip the anchor byte), exactly 10 bytes
(movsxd + cmp) get replaced with a 5-byte jmp + 5 nops, matching the .ct
file's own "Foods+01: jmp newmem \\n nop 5" -- our own stub re-executes
those same 10 bytes before jumping back, so this is functionally
identical to the original code path, just with rax siphoned off first.

Run enable_hook() first, then have the food/swap UI actually triggered
in-game at least once (same "Populated Only (requires an animal to
swap)" caveat the .ct file itself notes -- the pointer is nil until that
code path runs), then read_slots() to see what's captured. Call
disable_hook() to cleanly restore the original bytes and free the
allocated memory when done -- always do this before ending the session,
this is live code patching and shouldn't be left in place.

Slot layout, confirmed 2026-07-29 against a real live food menu screen
(see research/game-hooks.md's "Live carried food/animal inventory"
section for the full writeup) -- this corrects/extends the .ct file's
own offsets, which only covered 12 of the real 16 extended slots:
  - Quick-select hotbar, 3 slots: [ptr]+0x00, +0x08, +0x10 (0 = empty)
  - Extended list, 16 slots, stride 8: [ptr]+0x98 through +0x110
    inclusive. One slot per physical carried item (not deduplicated by
    type) -- count of a given ID across these slots is the real count.
Don't trust single-byte matches at other offsets in this region (e.g.
+0x9C, +0xA4) -- confirmed false positives, incidental collisions with
adjacent struct fields, not real slots. Data past +0x110 is unrelated
memory.
"""

from __future__ import annotations

import ctypes
import re
import struct

import pymem
import pymem.ressources.kernel32 as kernel32

PROCESS_NAME = "MGSDelta-Win64-Shipping.exe"
MODULE_NAME = "MGSDelta-Win64-Shipping.exe"

AOB_PATTERN = bytes([0xD3, 0x4C, 0x63, 0x00, 0x41, 0x81, 0xF8, 0x82, 0x00, 0x00, 0x00])
ORIGINAL_BYTES = bytes([0x4C, 0x63, 0x00, 0x41, 0x81, 0xF8, 0x82, 0x00, 0x00, 0x00])

PAGE_EXECUTE_READWRITE = 0x40
MEM_COMMIT = 0x1000
MEM_RESERVE = 0x2000
MEM_RELEASE = 0x8000


class FoodSlotHook:
    def __init__(self) -> None:
        self.pm = pymem.Pymem(PROCESS_NAME)
        self.patch_addr: int | None = None
        self.stub_addr: int | None = None
        self.old_protect: int | None = None

    def _find_patch_addr(self) -> int:
        matches = self.pm.pattern_scan_module(re.escape(AOB_PATTERN), MODULE_NAME, return_multiple=True)
        if not matches:
            raise RuntimeError("AOB pattern not found -- game patch version may not match the .ct file (1.1.3).")
        if len(matches) > 1:
            raise RuntimeError(f"Pattern not unique: {len(matches)} matches, need to add RVA filtering like weapons.")
        aob_addr = matches[0]
        patch_addr = aob_addr + 1
        actual = self.pm.read_bytes(patch_addr, len(ORIGINAL_BYTES))
        if actual != ORIGINAL_BYTES:
            raise RuntimeError(
                f"Bytes at patch_addr don't match expected original -- got {actual.hex()}, "
                f"expected {ORIGINAL_BYTES.hex()}. Aborting, do not patch."
            )
        return patch_addr

    def _alloc_near(self, target: int, size: int) -> int:
        """Allocate RWX memory within +/-2GB of target, so a 5-byte relative jmp reaches it."""
        step = 0x10000
        for i in range(1, 20000):
            for candidate in (target + i * step, target - i * step):
                addr = kernel32.VirtualAllocEx(
                    self.pm.process_handle,
                    ctypes.c_void_p(candidate),
                    size,
                    MEM_COMMIT | MEM_RESERVE,
                    PAGE_EXECUTE_READWRITE,
                )
                if addr:
                    return addr
        raise RuntimeError("Could not find free memory near target address.")

    def enable_hook(self) -> None:
        if self.patch_addr is not None:
            print("Hook already enabled.")
            return

        patch_addr = self._find_patch_addr()
        print(f"Found patch address: 0x{patch_addr:X} (verified original bytes match)")

        stub_addr = self._alloc_near(patch_addr, 64)
        print(f"Allocated code cave at: 0x{stub_addr:X} (distance {stub_addr - patch_addr:+d})")

        get_foods_addr = stub_addr + 24  # storage slot, after the stub code

        # mov [rip+disp32], rax  (7 bytes) -- disp32 relative to end of this instruction
        mov_disp = get_foods_addr - (stub_addr + 7)
        stub = bytes([0x48, 0x89, 0x05]) + struct.pack("<i", mov_disp)
        # original instructions, re-executed
        stub += ORIGINAL_BYTES
        # jmp rel32 back to right after the patched region
        return_addr = patch_addr + len(ORIGINAL_BYTES)
        jmp_back_disp = return_addr - (stub_addr + len(stub) + 5)
        stub += bytes([0xE9]) + struct.pack("<i", jmp_back_disp)

        assert len(stub) <= 24, f"stub too long: {len(stub)} bytes"
        self.pm.write_bytes(stub_addr, stub, len(stub))
        self.pm.write_longlong(get_foods_addr, 0)  # init storage to nil, like the .ct's "dq 0"

        # Patch the live instruction: jmp rel32 (5 bytes) + 5 nops, matching the .ct exactly
        jmp_fwd_disp = stub_addr - (patch_addr + 5)
        patch_bytes = bytes([0xE9]) + struct.pack("<i", jmp_fwd_disp) + bytes([0x90] * 5)
        assert len(patch_bytes) == len(ORIGINAL_BYTES)

        old_protect = ctypes.c_ulong()
        kernel32.VirtualProtectEx(
            self.pm.process_handle, ctypes.c_void_p(patch_addr), len(patch_bytes),
            PAGE_EXECUTE_READWRITE, ctypes.byref(old_protect),
        )
        self.pm.write_bytes(patch_addr, patch_bytes, len(patch_bytes))
        kernel32.VirtualProtectEx(
            self.pm.process_handle, ctypes.c_void_p(patch_addr), len(patch_bytes),
            old_protect.value, ctypes.byref(old_protect),
        )

        self.patch_addr = patch_addr
        self.stub_addr = stub_addr
        self.get_foods_addr = get_foods_addr
        print(f"Hook installed. getFoods storage at 0x{get_foods_addr:X}")
        print("Now trigger the equip-swap/food-cycle action in-game at least once.")

    def read_pointer(self) -> int:
        return self.pm.read_longlong(self.get_foods_addr)

    def read_slots(self) -> list[tuple[str, int]]:
        ptr = self.read_pointer()
        if ptr == 0:
            print("getFoods pointer is still nil -- trigger the swap/cycle action in-game first.")
            return []
        offsets = [0, 8, 0x10] + [0x98 + 8 * i for i in range(16)]
        slots = []
        for off in offsets:
            val = self.pm.read_uchar(ptr + off)
            slots.append((f"+0x{off:X}", val))
        return slots

    def disable_hook(self) -> None:
        if self.patch_addr is None:
            print("Hook not enabled.")
            return
        old_protect = ctypes.c_ulong()
        kernel32.VirtualProtectEx(
            self.pm.process_handle, ctypes.c_void_p(self.patch_addr), len(ORIGINAL_BYTES),
            PAGE_EXECUTE_READWRITE, ctypes.byref(old_protect),
        )
        self.pm.write_bytes(self.patch_addr, ORIGINAL_BYTES, len(ORIGINAL_BYTES))
        kernel32.VirtualProtectEx(
            self.pm.process_handle, ctypes.c_void_p(self.patch_addr), len(ORIGINAL_BYTES),
            old_protect.value, ctypes.byref(old_protect),
        )
        kernel32.VirtualFreeEx(self.pm.process_handle, ctypes.c_void_p(self.stub_addr), 0, MEM_RELEASE)
        print("Hook removed, original bytes restored, code cave freed.")
        self.patch_addr = None
        self.stub_addr = None


if __name__ == "__main__":
    hook = FoodSlotHook()
    hook.enable_hook()
