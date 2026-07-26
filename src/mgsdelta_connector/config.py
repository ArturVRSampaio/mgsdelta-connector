"""
Per-game-version offset/mapping tables.

Deliberately isolated from the rest of the code (see README "Patch churn") so
a game update only ever requires editing this file, not memory.py/game_state.py.

TODO: populate once recon (research/NOTES.md) has confirmed real offsets.
Keyed by game version/build so multiple patches can be supported at once.
"""

OFFSETS = {
    # "1.0.0": {...},
}
