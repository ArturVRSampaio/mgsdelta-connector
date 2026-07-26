"""
File-based bridge to the in-game UE4SS Lua script.

Communication happens via two JSON files on disk: a state file the Lua
script writes on a timer (that this process polls) and a commands file
this process writes (that the Lua script polls and clears once handled).
Plain `io.open`/`write` is confirmed to work from UE4SS's Lua environment,
which has no socket/HTTP client available — see research/NOTES.md for why
file polling is the chosen bridge mechanism.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Protocol


class MemoryReader(Protocol):
    def read_state(self) -> dict[str, Any]: ...


class MemoryWriter(Protocol):
    def write_commands(self, commands: list[dict[str, Any]]) -> None: ...


class FileBridge:
    """Reads game state from, and writes commands to, files a UE4SS Lua script polls."""

    def __init__(self, state_path: Path, commands_path: Path) -> None:
        self._state_path = state_path
        self._commands_path = commands_path

    def read_state(self) -> dict[str, Any]:
        if not self._state_path.exists():
            return {}
        state: dict[str, Any] = json.loads(self._state_path.read_text())
        return state

    def write_commands(self, commands: list[dict[str, Any]]) -> None:
        self._commands_path.write_text(json.dumps(commands))
