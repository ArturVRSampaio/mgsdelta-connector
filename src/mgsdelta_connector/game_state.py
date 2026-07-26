"""
Maps raw state reads (via memory.py's MemoryReader) to semantic game
events. Currently just the duck ("Gako") unlock counter confirmed working
in research/NOTES.md milestone 2 — grows in lockstep with
mgsdelta-apworld's Locations.py as more locations are confirmed readable.
"""

from __future__ import annotations

from dataclasses import dataclass

from .memory import MemoryReader


@dataclass(frozen=True)
class DuckCounts:
    unlocked: int
    total: int


def read_duck_counts(reader: MemoryReader) -> DuckCounts | None:
    """Reads the current duck unlock counts.

    Returns None if the game hasn't written a state file yet (not
    launched, or still on the main menu before the subsystem is live).
    """
    raw = reader.read_state()
    if "duck_unlock_count" not in raw or "duck_total_count" not in raw:
        return None
    return DuckCounts(unlocked=raw["duck_unlock_count"], total=raw["duck_total_count"])


def newly_unlocked_count(previous: DuckCounts | None, current: DuckCounts) -> int:
    """How many additional ducks were unlocked between two reads.

    Zero if this is the first read (no previous state to compare against)
    or the count didn't grow (e.g. an earlier save was reloaded) — a
    check count must never go negative.
    """
    if previous is None:
        return 0
    return max(0, current.unlocked - previous.unlocked)


# Location IDs must match mgsdelta-apworld's Locations.py exactly. This
# reuses the existing "Kerotan Frog N" ID scheme (BASE_ID + index) as
# placeholder location identities for duck-unlock-count thresholds, since
# apworld's location tables don't have real duck-specific entries yet --
# location N is checked once the live duck-unlock count reaches N. See
# research/NOTES.md milestone 4 for why.
LOCATION_BASE_ID = 3_901_000
LOCATION_COUNT = 64


def location_ids_for_count(count: int) -> list[int]:
    """Location IDs that should be checked once `count` ducks are unlocked."""
    capped = min(count, LOCATION_COUNT)
    return [LOCATION_BASE_ID + i for i in range(capped)]


def locations_to_check(previous: DuckCounts | None, current: DuckCounts) -> list[int]:
    """Which location IDs newly need checking, given the previous and current duck counts."""
    if newly_unlocked_count(previous, current) <= 0:
        return []
    return location_ids_for_count(current.unlocked)
