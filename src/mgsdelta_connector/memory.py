"""
Process attach + read/write primitives.

TODO: implementation depends on the recon findings (README "Open questions"):
  - If no anti-cheat + UE4SS viable: this becomes a thin bridge to a UE4SS Lua
    script (e.g. over a local socket/pipe) rather than raw memory access.
  - If raw memory access is the path: pymem-based read/write against offsets
    from config.py.
  - If save-diffing is the fallback: this module instead becomes a save-file
    watcher/differ (no live process access at all).
"""
