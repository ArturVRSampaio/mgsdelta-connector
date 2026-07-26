import json
from pathlib import Path

from mgsdelta_connector.memory import FileBridge


def test_read_state_returns_empty_dict_when_file_missing(tmp_path: Path) -> None:
    bridge = FileBridge(tmp_path / "state.json", tmp_path / "commands.json")
    assert bridge.read_state() == {}


def test_read_state_returns_parsed_json_when_file_exists(tmp_path: Path) -> None:
    state_path = tmp_path / "state.json"
    state_path.write_text(json.dumps({"duck_unlock_count": 34, "duck_total_count": 64}))
    bridge = FileBridge(state_path, tmp_path / "commands.json")

    assert bridge.read_state() == {"duck_unlock_count": 34, "duck_total_count": 64}


def test_write_commands_writes_json_to_commands_path(tmp_path: Path) -> None:
    commands_path = tmp_path / "commands.json"
    bridge = FileBridge(tmp_path / "state.json", commands_path)

    bridge.write_commands([{"action": "unlock_duck"}])

    assert json.loads(commands_path.read_text()) == [{"action": "unlock_duck"}]
