from typing import Any

from mgsdelta_connector.game_state import (
    FROG_LOCATION_BASE_ID,
    FROG_LOCATION_COUNT,
    CollectibleCounts,
    frog_location_ids_for_count,
    frog_locations_to_check,
    newly_unlocked_count,
    read_frog_counts,
)


class FakeReader:
    def __init__(self, state: dict[str, Any]) -> None:
        self._state = state

    def read_state(self) -> dict[str, Any]:
        return self._state


def test_read_frog_counts_returns_none_when_state_missing_keys() -> None:
    assert read_frog_counts(FakeReader({})) is None


def test_read_frog_counts_parses_present_keys() -> None:
    reader = FakeReader({"frog_unlock_count": 41, "frog_total_count": 64})

    assert read_frog_counts(reader) == CollectibleCounts(unlocked=41, total=64)


def test_newly_unlocked_count_is_zero_with_no_previous_state() -> None:
    current = CollectibleCounts(unlocked=34, total=64)

    assert newly_unlocked_count(None, current) == 0


def test_newly_unlocked_count_reports_the_increase() -> None:
    previous = CollectibleCounts(unlocked=33, total=64)
    current = CollectibleCounts(unlocked=35, total=64)

    assert newly_unlocked_count(previous, current) == 2


def test_newly_unlocked_count_never_negative() -> None:
    previous = CollectibleCounts(unlocked=40, total=64)
    current = CollectibleCounts(unlocked=34, total=64)  # e.g. an earlier save was reloaded

    assert newly_unlocked_count(previous, current) == 0


def test_frog_location_ids_for_count_returns_ids_from_base() -> None:
    expected = [FROG_LOCATION_BASE_ID, FROG_LOCATION_BASE_ID + 1, FROG_LOCATION_BASE_ID + 2]

    assert frog_location_ids_for_count(3) == expected


def test_frog_location_ids_for_count_caps_at_location_count() -> None:
    ids = frog_location_ids_for_count(FROG_LOCATION_COUNT + 10)

    assert len(ids) == FROG_LOCATION_COUNT
    assert ids[-1] == FROG_LOCATION_BASE_ID + FROG_LOCATION_COUNT - 1


def test_frog_locations_to_check_is_empty_with_no_previous_state() -> None:
    current = CollectibleCounts(unlocked=41, total=64)

    assert frog_locations_to_check(None, current) == []


def test_frog_locations_to_check_is_empty_when_count_did_not_grow() -> None:
    previous = CollectibleCounts(unlocked=41, total=64)
    current = CollectibleCounts(unlocked=41, total=64)

    assert frog_locations_to_check(previous, current) == []


def test_frog_locations_to_check_returns_ids_up_to_new_count() -> None:
    previous = CollectibleCounts(unlocked=1, total=64)
    current = CollectibleCounts(unlocked=3, total=64)

    assert frog_locations_to_check(previous, current) == [
        FROG_LOCATION_BASE_ID,
        FROG_LOCATION_BASE_ID + 1,
        FROG_LOCATION_BASE_ID + 2,
    ]
