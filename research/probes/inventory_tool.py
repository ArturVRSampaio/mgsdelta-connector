"""
CLI for the systematic strip-then-grant-one-by-one verification pass
described in the conversation: start a fresh save, strip everything, then
grant each weapon/item in turn and confirm it actually matches what
appears in-game before moving to the next one.

Usage:
    python inventory_tool.py strip              # zero out every weapon/item
    python inventory_tool.py next                # grant the next untested entry
    python inventory_tool.py record pass|fail [note...]  # log the result of the last `next`
    python inventory_tool.py status              # show progress so far
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

from mgs_memory import ItemEntry, MGSMemory, WeaponEntry, load_index

STATE_PATH = Path(__file__).parent / "grant_progress.json"


def _load_state() -> dict:
    if STATE_PATH.exists():
        return json.loads(STATE_PATH.read_text())
    return {"position": 0, "results": {}}


def _save_state(state: dict) -> None:
    STATE_PATH.write_text(json.dumps(state, indent=2))


def _sequence() -> list[tuple[str, int, str]]:
    """(kind, index, name) for every weapon then every item, in index order."""
    weapons, items = load_index()
    seq = [("weapon", w.index, w.name) for w in weapons]
    seq += [("item", i.index, i.name) for i in items]
    return seq


def cmd_strip() -> None:
    mem = MGSMemory()
    weapons, items = load_index()
    print(f"WeaponsTable at 0x{mem.weapons_table:X}, ItemsTable at 0x{mem.items_table:X}")
    for w in weapons:
        mem.strip_weapon(w)
    for i in items:
        mem.strip_item(i)
    print(f"Stripped {len(weapons)} weapons and {len(items)} items to not-owned.")
    print("Check the game's weapon/item menus - they should now be empty.")


def cmd_next() -> None:
    state = _load_state()
    seq = _sequence()
    pos = state["position"]
    if pos >= len(seq):
        print("All entries already granted. Run `status` to see the results log.")
        return

    kind, index, name = seq[pos]
    weapons, items = load_index()
    mem = MGSMemory()

    if kind == "weapon":
        weapon = next(w for w in weapons if w.index == index)
        mem.grant_weapon(weapon)
    else:
        item = next(i for i in items if i.index == index)
        mem.grant_item(item)

    print(f"[{pos + 1}/{len(seq)}] Granted {kind} index {index}: '{name}'")
    print("Check in-game now. Then run: python inventory_tool.py record pass|fail [note]")

    state["position"] = pos  # don't advance until recorded
    state["pending"] = {"kind": kind, "index": index, "name": name}
    _save_state(state)


def cmd_record(result: str, note: str = "") -> None:
    state = _load_state()
    pending = state.get("pending")
    if not pending:
        print("Nothing pending - run `next` first.")
        return

    key = f"{pending['kind']}:{pending['index']}"
    state["results"][key] = {"name": pending["name"], "result": result, "note": note}
    state["position"] += 1
    state["pending"] = None
    _save_state(state)

    seq = _sequence()
    print(f"Recorded {result} for {pending['name']}. ({state['position']}/{len(seq)} done)")
    if state["position"] < len(seq):
        print("Run `next` again for the following entry.")
    else:
        print("That was the last entry. Run `status` for the full results log.")


def cmd_status() -> None:
    state = _load_state()
    seq = _sequence()
    results = state["results"]
    print(f"Progress: {state['position']}/{len(seq)}")
    fails = {k: v for k, v in results.items() if v["result"] != "pass"}
    if fails:
        print(f"\n{len(fails)} mismatch(es)/fail(s):")
        for key, v in fails.items():
            print(f"  {key} '{v['name']}': {v['note'] or '(no note)'}")
    else:
        print("No failures recorded so far.")


def main() -> None:
    if len(sys.argv) < 2:
        print(__doc__)
        return
    cmd = sys.argv[1]
    if cmd == "strip":
        cmd_strip()
    elif cmd == "next":
        cmd_next()
    elif cmd == "record":
        result = sys.argv[2] if len(sys.argv) > 2 else ""
        note = " ".join(sys.argv[3:])
        if result not in ("pass", "fail"):
            print("Usage: record pass|fail [note...]")
            return
        cmd_record(result, note)
    elif cmd == "status":
        cmd_status()
    else:
        print(__doc__)


if __name__ == "__main__":
    main()
