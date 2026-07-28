"""
Maps raw state reads (via memory.py's MemoryReader) to semantic game
events. Currently just the frog ("Kerotan") unlock counter confirmed
working in research/NOTES.md milestone 5 — grows in lockstep with
mgsdelta-apworld's Locations.py as more locations are confirmed readable.
"""

from __future__ import annotations

from dataclasses import dataclass

from .memory import MemoryReader


@dataclass(frozen=True)
class CollectibleCounts:
    unlocked: int
    total: int


def read_frog_counts(reader: MemoryReader) -> CollectibleCounts | None:
    """Reads the current frog (Kerotan) unlock counts.

    Returns None if the game hasn't written a state file yet (not
    launched, or still on the main menu before the subsystem is live).
    """
    raw = reader.read_state()
    if "frog_unlock_count" not in raw or "frog_total_count" not in raw:
        return None
    return CollectibleCounts(unlocked=raw["frog_unlock_count"], total=raw["frog_total_count"])


def newly_unlocked_count(previous: CollectibleCounts | None, current: CollectibleCounts) -> int:
    """How many additional collectibles were unlocked between two reads.

    Zero if this is the first read (no previous state to compare against)
    or the count didn't grow (e.g. an earlier save was reloaded) — a
    check count must never go negative.
    """
    if previous is None:
        return 0
    return max(0, current.unlocked - previous.unlocked)


# Location IDs must match mgsdelta-apworld's Locations.py exactly -- these
# are the 64 real "Kerotan Frog N" locations (BASE_ID there). Location N is
# checked once the live frog-unlock count reaches N -- see
# research/NOTES.md milestone 5.
FROG_LOCATION_BASE_ID = 3_901_000
FROG_LOCATION_COUNT = 64


def frog_location_ids_for_count(count: int) -> list[int]:
    """Location IDs that should be checked once `count` frogs are unlocked."""
    capped = min(count, FROG_LOCATION_COUNT)
    return [FROG_LOCATION_BASE_ID + i for i in range(capped)]


def frog_locations_to_check(
    previous: CollectibleCounts | None, current: CollectibleCounts
) -> list[int]:
    """Which frog location IDs newly need checking, given the previous and current counts."""
    if newly_unlocked_count(previous, current) <= 0:
        return []
    return frog_location_ids_for_count(current.unlocked)
