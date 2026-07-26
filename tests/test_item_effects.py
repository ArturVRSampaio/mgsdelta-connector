from typing import Any

from NetUtils import NetworkItem

from mgsdelta_connector.item_effects import UNLOCK_DUCK_ITEM_NAME, grant_item, items_to_grant


class FakeWriter:
    def __init__(self) -> None:
        self.written: list[list[dict[str, Any]]] = []

    def write_commands(self, commands: list[dict[str, Any]]) -> None:
        self.written.append(commands)


def test_grant_item_writes_unlock_command_for_known_item() -> None:
    writer = FakeWriter()

    result = grant_item(writer, UNLOCK_DUCK_ITEM_NAME)

    assert result is True
    assert writer.written == [[{"action": "unlock_duck"}]]


def test_grant_item_returns_false_for_unknown_item() -> None:
    writer = FakeWriter()

    result = grant_item(writer, "Something Else")

    assert result is False
    assert writer.written == []


def test_items_to_grant_returns_all_items_when_none_granted_yet() -> None:
    items = [
        NetworkItem(item=100, location=1, player=1),
        NetworkItem(item=200, location=2, player=1),
    ]

    assert items_to_grant(items, already_granted=[]) == [(0, 100), (1, 200)]


def test_items_to_grant_skips_already_granted_indices() -> None:
    items = [
        NetworkItem(item=100, location=1, player=1),
        NetworkItem(item=200, location=2, player=1),
    ]

    assert items_to_grant(items, already_granted=[0]) == [(1, 200)]


def test_items_to_grant_empty_when_all_granted() -> None:
    items = [NetworkItem(item=100, location=1, player=1)]

    assert items_to_grant(items, already_granted=[0]) == []
