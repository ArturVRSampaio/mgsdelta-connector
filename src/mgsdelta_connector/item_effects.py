"""
Maps an incoming Archipelago item to the write command(s) that grant it
in-game, via memory.py's MemoryWriter. Grows in lockstep with
mgsdelta-apworld's Items.py.
"""

from __future__ import annotations

from .memory import MemoryWriter

UNLOCK_DUCK_ITEM_NAME = "Unlock Duck"


def grant_item(writer: MemoryWriter, item_name: str) -> bool:
    """Writes the command(s) that grant the given item in-game.

    Returns whether the item was recognized. An unrecognized item name
    reaching here means mgsdelta-apworld's Items.py and this module have
    drifted out of sync — the caller decides how to log/handle that, this
    function just reports it rather than raising.
    """
    if item_name != UNLOCK_DUCK_ITEM_NAME:
        return False

    writer.write_commands([{"action": "unlock_duck"}])
    return True
