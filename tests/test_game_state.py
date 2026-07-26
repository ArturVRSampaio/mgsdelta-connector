from typing import Any

from mgsdelta_connector.game_state import DuckCounts, newly_unlocked_count, read_duck_counts


class FakeReader:
    def __init__(self, state: dict[str, Any]) -> None:
        self._state = state

    def read_state(self) -> dict[str, Any]:
        return self._state


def test_read_duck_counts_returns_none_when_state_missing_keys() -> None:
    assert read_duck_counts(FakeReader({})) is None


def test_read_duck_counts_parses_present_keys() -> None:
    reader = FakeReader({"duck_unlock_count": 34, "duck_total_count": 64})

    assert read_duck_counts(reader) == DuckCounts(unlocked=34, total=64)


def test_newly_unlocked_count_is_zero_with_no_previous_state() -> None:
    current = DuckCounts(unlocked=34, total=64)

    assert newly_unlocked_count(None, current) == 0


def test_newly_unlocked_count_reports_the_increase() -> None:
    previous = DuckCounts(unlocked=33, total=64)
    current = DuckCounts(unlocked=35, total=64)

    assert newly_unlocked_count(previous, current) == 2


def test_newly_unlocked_count_never_negative() -> None:
    previous = DuckCounts(unlocked=40, total=64)
    current = DuckCounts(unlocked=34, total=64)  # e.g. an earlier save was reloaded

    assert newly_unlocked_count(previous, current) == 0
