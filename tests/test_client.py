"""
Tests for MGSDeltaContext. Each test wraps its whole body (construct, act,
assert) in a single `asyncio.run(...)` call, since CommonContext.__init__
schedules a background asyncio task and needs a running event loop.

Every path exercised here is genuinely safe without a live server:
check_locations() no-ops when self.missing_locations is empty (the default
with no connection), lookup_in_game() is a local datapackage lookup seeded
via update_game(), and server_auth()/get_username()/send_connect() no-op
when self.auth is pre-set and self.server is None. See client.py's own
comments for why each of these doesn't need a live connection.

CommonContext.__init__ also assumes self.game is already a registered
world in the local Archipelago checkout's data package (true in a real
deployment, where mgsdelta-apworld would actually be installed alongside
core) -- not true in this repo's own vendored, bare Archipelago submodule.
The autouse fixture below patches a minimal fake entry in for the
duration of each test, restored automatically by monkeypatch afterward.
"""

from __future__ import annotations

import asyncio
import json
from pathlib import Path

import pytest
from NetUtils import NetworkItem
from worlds import network_data_package

from mgsdelta_connector.client import GAME_NAME, MGSDeltaContext
from mgsdelta_connector.game_state import DuckCounts
from mgsdelta_connector.item_effects import UNLOCK_DUCK_ITEM_NAME
from mgsdelta_connector.memory import FileBridge


@pytest.fixture(autouse=True)
def _register_game_in_data_package(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setitem(
        network_data_package["games"],
        GAME_NAME,
        {"checksum": "test-checksum", "item_name_to_id": {}, "location_name_to_id": {}},
    )


def _make_context(tmp_path: Path) -> MGSDeltaContext:
    bridge = FileBridge(tmp_path / "state.json", tmp_path / "commands.json")
    ctx = MGSDeltaContext(None, None, bridge)
    ctx.auth = "TestSlot"  # skip get_username()'s console_input path
    return ctx


def test_init_sets_up_bridge_and_empty_tracking_state(tmp_path: Path) -> None:
    async def scenario() -> None:
        ctx = _make_context(tmp_path)
        assert ctx.game == GAME_NAME
        assert ctx.previous_counts is None
        assert ctx.granted_item_indices == set()
        ctx.keep_alive_task.cancel()

    asyncio.run(scenario())


def test_server_auth_completes_without_a_live_connection(tmp_path: Path) -> None:
    async def scenario() -> None:
        ctx = _make_context(tmp_path)
        await ctx.server_auth(password_requested=False)
        ctx.keep_alive_task.cancel()

    asyncio.run(scenario())


def test_poll_once_does_nothing_when_no_state_file_exists(tmp_path: Path) -> None:
    async def scenario() -> None:
        ctx = _make_context(tmp_path)
        await ctx.poll_once()
        assert ctx.previous_counts is None
        ctx.keep_alive_task.cancel()

    asyncio.run(scenario())


def test_poll_once_tracks_duck_counts_across_two_reads(tmp_path: Path) -> None:
    state_path = tmp_path / "state.json"

    async def scenario() -> None:
        ctx = _make_context(tmp_path)

        state_path.write_text(json.dumps({"duck_unlock_count": 33, "duck_total_count": 64}))
        await ctx.poll_once()

        state_path.write_text(json.dumps({"duck_unlock_count": 35, "duck_total_count": 64}))
        await ctx.poll_once()

        assert ctx.previous_counts == DuckCounts(unlocked=35, total=64)
        ctx.keep_alive_task.cancel()

    asyncio.run(scenario())


def test_poll_once_grants_new_items_and_marks_them_granted(tmp_path: Path) -> None:
    commands_path = tmp_path / "commands.json"

    async def scenario() -> None:
        ctx = _make_context(tmp_path)
        ctx.item_names.update_game(GAME_NAME, {UNLOCK_DUCK_ITEM_NAME: 12345})
        ctx.items_received = [NetworkItem(item=12345, location=1, player=1)]

        await ctx.poll_once()

        assert ctx.granted_item_indices == {0}
        assert json.loads(commands_path.read_text()) == [{"action": "unlock_duck"}]
        ctx.keep_alive_task.cancel()

    asyncio.run(scenario())


def test_poll_once_does_not_re_grant_already_granted_items(tmp_path: Path) -> None:
    commands_path = tmp_path / "commands.json"

    async def scenario() -> None:
        ctx = _make_context(tmp_path)
        ctx.item_names.update_game(GAME_NAME, {UNLOCK_DUCK_ITEM_NAME: 12345})
        ctx.items_received = [NetworkItem(item=12345, location=1, player=1)]

        await ctx.poll_once()
        commands_path.unlink()  # prove the second poll_once doesn't write again
        await ctx.poll_once()

        assert ctx.granted_item_indices == {0}
        assert not commands_path.exists()
        ctx.keep_alive_task.cancel()

    asyncio.run(scenario())
