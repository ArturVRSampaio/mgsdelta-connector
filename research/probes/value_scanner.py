"""
Generic Cheat-Engine-style value scanner via pymem/ctypes -- no Cheat
Engine GUI needed, since we already have the low-level process handle
access this whole project is built on. Used to find the real (upstream)
source of equipped-camo state, now that CurrentInfo is confirmed to be a
downstream mirror rather than the authoritative value (see NOTES.md
2026-07-29).

Two-phase workflow, matching Cheat Engine's "unknown initial value" +
"changed value" pattern:
  1. first_scan(value) before changing anything in-game -- walks every
     committed, readable, private (heap-like) memory region and records
     every 4-byte-aligned int32 match. Deliberately excludes MEM_IMAGE
     (mapped module code/data, e.g. the exe/DLLs themselves) and
     MEM_MAPPED (memory-mapped files) -- dynamic UObject state lives on
     the private heap, not baked into a module image, so this scopes out
     a huge amount of irrelevant address space up front.
  2. next_scan(value) after changing camo in-game -- filters the
     candidate list down to addresses that now hold the new value.
Repeat step 2 (with a different camo each time) to narrow further.

Candidates are cached to disk (JSON) between runs so this can be split
across multiple short Python invocations if needed.

WARNING, learned the hard way 2026-07-29: the *_byte variants (unaligned
single-byte matching, needed to catch TEnumAsByte<T>-style fields the
aligned int32 scan can't see) produce an order of magnitude more
candidates (14M+ vs ~1M for int32) from the same memory. Running a full
first_scan_byte + next_scan_byte back to back, while the game itself is
running, crashed the game via resource exhaustion (frame rate collapse
then a full crash-and-relaunch, confirmed by a fresh crash dump and the
process PID changing) -- not a logic crash like every other crash this
project has hit, a genuinely new failure mode from competing with the
live game for RAM/CPU. Don't run the byte-width scan functions
unscoped/back-to-back again without deliberately narrowing the memory
region searched first (e.g. only scan near already-known-relevant
addresses, not the entire private address space).
"""

from __future__ import annotations

import ctypes
import json
import struct
from pathlib import Path

import pymem
import pymem.memory as pmem_mem
import pymem.ressources.kernel32 as kernel32

PROCESS_NAME = "MGSDelta-Win64-Shipping.exe"
CANDIDATES_PATH = Path(__file__).parent / "value_scan_candidates.json"

MEM_COMMIT = 0x1000
MEM_PRIVATE = 0x20000
PAGE_GUARD = 0x100
PAGE_NOACCESS = 0x01
MAX_USERMODE_ADDR = 0x7FFFFFFF0000


def _readable_private_regions(pm: pymem.Pymem):
    addr = 0
    while addr < MAX_USERMODE_ADDR:
        try:
            info = pmem_mem.virtual_query(pm.process_handle, addr)
        except Exception:
            break
        region_size = info.RegionSize
        if region_size <= 0:
            break
        if (
            info.State == MEM_COMMIT
            and info.Type == MEM_PRIVATE
            and not (info.Protect & PAGE_GUARD)
            and info.Protect != PAGE_NOACCESS
        ):
            yield info.BaseAddress, region_size
        addr = info.BaseAddress + region_size


def first_scan(value: int) -> int:
    pm = pymem.Pymem(PROCESS_NAME)
    target = struct.pack("<i", value)
    candidates = []
    regions_scanned = 0
    for base, size in _readable_private_regions(pm):
        if size > 500 * 1024 * 1024:  # skip pathologically huge single regions
            continue
        try:
            data = pm.read_bytes(base, size)
        except Exception:
            continue
        regions_scanned += 1
        start = 0
        while True:
            idx = data.find(target, start)
            if idx == -1:
                break
            if idx % 4 == 0:  # 4-byte aligned only, matches int32 field layout
                candidates.append(base + idx)
            start = idx + 1
    CANDIDATES_PATH.write_text(json.dumps(candidates))
    print(f"Scanned {regions_scanned} private regions. Found {len(candidates)} candidates for value={value}.")
    print(f"Saved to {CANDIDATES_PATH}")
    return len(candidates)


BYTE_CANDIDATES_PATH = Path(__file__).parent / "value_scan_candidates_byte.json"


def first_scan_byte(value: int) -> int:
    """
    Unaligned single-byte scan -- catches TEnumAsByte<T>-style fields a
    4-byte-aligned int32 scan can't see. Noisier (single-byte matches are
    far more common), so expect a much larger initial candidate set than
    first_scan()'s int32 equivalent.
    """
    pm = pymem.Pymem(PROCESS_NAME)
    target = bytes([value & 0xFF])
    candidates = []
    regions_scanned = 0
    for base, size in _readable_private_regions(pm):
        if size > 500 * 1024 * 1024:
            continue
        try:
            data = pm.read_bytes(base, size)
        except Exception:
            continue
        regions_scanned += 1
        start = 0
        while True:
            idx = data.find(target, start)
            if idx == -1:
                break
            candidates.append(base + idx)
            start = idx + 1
    BYTE_CANDIDATES_PATH.write_text(json.dumps(candidates))
    print(f"Scanned {regions_scanned} private regions. Found {len(candidates)} byte candidates for value={value}.")
    print(f"Saved to {BYTE_CANDIDATES_PATH}")
    return len(candidates)


def next_scan_byte(value: int) -> int:
    """
    With millions of byte-granularity candidates, checking each address
    individually (millions of separate ReadProcessMemory calls) is far
    too slow. Instead, redo a full bulk region scan for the new value
    (same cost as first_scan_byte -- tens of thousands of bulk reads, not
    millions of tiny ones) and intersect with the previous candidate set.
    """
    if not BYTE_CANDIDATES_PATH.exists():
        raise RuntimeError("No byte candidates file -- run first_scan_byte() first.")
    previous = set(json.loads(BYTE_CANDIDATES_PATH.read_text()))
    pm = pymem.Pymem(PROCESS_NAME)
    target = bytes([value & 0xFF])
    new_matches = set()
    for base, size in _readable_private_regions(pm):
        if size > 500 * 1024 * 1024:
            continue
        try:
            data = pm.read_bytes(base, size)
        except Exception:
            continue
        start = 0
        while True:
            idx = data.find(target, start)
            if idx == -1:
                break
            new_matches.add(base + idx)
            start = idx + 1
    survivors = sorted(previous & new_matches)
    BYTE_CANDIDATES_PATH.write_text(json.dumps(survivors))
    print(f"{len(previous)} previous candidates -> {len(survivors)} survivors for value={value}.")
    print(f"Saved to {BYTE_CANDIDATES_PATH}")
    return len(survivors)


def next_scan(value: int) -> int:
    if not CANDIDATES_PATH.exists():
        raise RuntimeError("No candidates file -- run first_scan() first.")
    candidates = json.loads(CANDIDATES_PATH.read_text())
    pm = pymem.Pymem(PROCESS_NAME)
    survivors = []
    for addr in candidates:
        try:
            v = pm.read_int(addr)
        except Exception:
            continue
        if v == value:
            survivors.append(addr)
    CANDIDATES_PATH.write_text(json.dumps(survivors))
    print(f"{len(candidates)} candidates -> {len(survivors)} survivors for value={value}.")
    print(f"Saved to {CANDIDATES_PATH}")
    return len(survivors)


def show_candidates(limit: int = 50) -> None:
    candidates = json.loads(CANDIDATES_PATH.read_text())
    for addr in candidates[:limit]:
        print(hex(addr))
    if len(candidates) > limit:
        print(f"... and {len(candidates) - limit} more")


if __name__ == "__main__":
    import sys
    if len(sys.argv) < 3:
        print("Usage: value_scanner.py first|next|first_byte|next_byte <value>")
        sys.exit(1)
    cmd, value = sys.argv[1], int(sys.argv[2])
    if cmd == "first":
        first_scan(value)
    elif cmd == "next":
        next_scan(value)
    elif cmd == "first_byte":
        first_scan_byte(value)
    elif cmd == "next_byte":
        next_scan_byte(value)
    else:
        print("Unknown command:", cmd)
