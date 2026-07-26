from typing import Any

from mgsdelta_connector.item_effects import UNLOCK_DUCK_ITEM_NAME, grant_item


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
