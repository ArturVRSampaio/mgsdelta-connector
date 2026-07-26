"""
Network layer: subclasses Archipelago's CommonClient to handle server
session/auth and the incoming-item queue.

Kept deliberately thin per CONTRIBUTING.md's architecture split: all the
actual decision logic (which locations newly need checking, which received
items still need granting) lives in game_state.py/item_effects.py as pure
functions tested without any network involved. This module only wires
those functions to the real, unavoidably-untestable-without-a-live-server
network calls inherited from CommonContext -- verified manually against a
real game+server session at each build-plan milestone (see
research/NOTES.md), not by automated coverage.
"""

from __future__ import annotations

import asyncio

from CommonClient import CommonContext

from .game_state import DuckCounts, locations_to_check, read_duck_counts
from .item_effects import grant_item, items_to_grant
from .memory import FileBridge

GAME_NAME = "Metal Gear Solid Delta: Snake Eater"


class MGSDeltaContext(CommonContext):
    game = GAME_NAME
    items_handling = 0b111  # receive all items, including our own/local

    def __init__(
        self, server_address: str | None, password: str | None, bridge: FileBridge
    ) -> None:
        super().__init__(server_address, password)
        self.bridge = bridge
        self.previous_counts: DuckCounts | None = None
        self.granted_item_indices: set[int] = set()

    async def server_auth(self, password_requested: bool = False) -> None:
        if password_requested and not self.password:
            # Blocks on console input with no server/UI attached -- not
            # exercised in tests, which always pre-set self.auth so the
            # password_requested branch below is what actually needs to
            # be True to reach this (real interactive use only).
            await super().server_auth(password_requested)  # pragma: no cover
        await self.get_username()
        await self.send_connect()

    async def poll_once(self) -> None:
        current = read_duck_counts(self.bridge)
        if current is not None:
            to_check = locations_to_check(self.previous_counts, current)
            if to_check:
                # No-ops safely with no live connection: check_locations()
                # intersects with self.missing_locations, which is empty
                # until a real server reports otherwise.
                await self.check_locations(to_check)
            self.previous_counts = current

        for index, item_id in items_to_grant(self.items_received, self.granted_item_indices):
            # A local datapackage lookup, not a network call -- tests seed
            # it via self.item_names.update_game(...).
            item_name = self.item_names.lookup_in_game(item_id)
            if grant_item(self.bridge, item_name):
                self.granted_item_indices.add(index)

    async def poll_forever(self, interval_seconds: float = 1.0) -> None:  # pragma: no cover
        while not self.exit_event.is_set():
            await self.poll_once()
            await asyncio.sleep(interval_seconds)
