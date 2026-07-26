# mgsdelta-connector

[![CI](https://github.com/arturvrsampaio/mgsdelta-connector/actions/workflows/ci.yml/badge.svg)](https://github.com/arturvrsampaio/mgsdelta-connector/actions/workflows/ci.yml)
[![codecov](https://codecov.io/gh/arturvrsampaio/mgsdelta-connector/graph/badge.svg)](https://codecov.io/gh/arturvrsampaio/mgsdelta-connector)

The runtime bridge between a running copy of **Metal Gear Solid Δ: Snake Eater**
and an Archipelago multiworld server. This is the piece that turns
[`mgsdelta-apworld`](../mgsdelta-apworld)'s abstract items/locations into real
effects in the actual game, and reports real in-game events back as checks.

Concretely, it needs to do two things, continuously, while the game runs:

1. **Detect checks**: notice when the player picks up a frog, an item, or beats
   a boss, and tell the Archipelago server "this location's check has happened."
2. **Grant items**: when the server says "you received item X," make that item
   actually appear/apply in the player's game.

The game has **no mod API or scripting support today**, so this repo starts from
a reverse-engineering standing start, not from a plugin SDK.

## Install

```bash
git clone https://github.com/ArturVRSampaio/mgsdelta-connector.git
cd mgsdelta-connector

python3 -m venv .venv
.venv/bin/pip install -e ".[dev]"
```

`requirements.txt` is still a placeholder (see below) — every module is a
stub, so there's nothing runtime-installable yet beyond the dev tooling.
Once recon picks an approach (`pymem`, UE4SS, or save-diffing) and
`client.py` starts subclassing Archipelago's `CommonClient`, this section
will grow real runtime dependencies, likely including a pinned Archipelago
core checkout the same way `mgsdelta-apworld` vendors one — see that repo's
README for the pattern. `.venv/bin/pytest --cov` should pass as-is. See
[`CONTRIBUTING.md`](./CONTRIBUTING.md) for the full check suite.

## Open questions to resolve before committing to an architecture

- **Anti-cheat**: does MGS Δ ship with Easy Anti-Cheat or similar? **Resolved
  2026-07-26: no.** Confirmed both by inspecting the install tree (no
  EasyAntiCheat/BattlEye files anywhere) and by launching the game live and
  checking the process list — only the launcher stub and the shipping exe
  run, no AC process spawns. Module enumeration against the live process
  also succeeded cleanly (156 modules, no access-denied), meaning it isn't
  running as a protected process either. See `research/NOTES.md` for detail.
- **Engine**: the game is Unreal Engine (5) — **confirmed** from the install
  layout (`Engine/` folder, `MGSDelta-Win64-Shipping.exe` naming).
  [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS) **does inject and hook this
  game's core functions** (`GMalloc`, `FName`, `StaticConstructObject_Internal`
  all resolve automatically), but its `GUObjectArray` pattern — the piece
  it needs for almost everything past basic hooking — doesn't match this
  build under any of engine versions 5.1–5.6 tried so far. This game isn't
  in UE4SS's community config database yet. **Open decision, not yet made**:
  invest in a custom `GUObjectArray` AOB signature (keeps the UE4SS path,
  needs a disassembler and real reverse-engineering work) vs. switch to raw
  memory access via `pymem` (the process allows free `OpenProcess`/module
  access, confirmed above, so this path is viable too — just a different
  offset-hunting effort). See `research/NOTES.md` for the full log.
- **Save-game feasibility as a fallback**: now low-priority given how clean
  the anti-cheat/access results are — only revisit if UE4SS or raw memory
  access hits an unexpected wall.
- **Patch churn**: every game update can move memory offsets. The design should
  isolate all raw offsets behind a small, versioned mapping file, not scatter
  them through the code.

## Planned architecture (default path, pending the answers above)

```
mgsdelta_connector/
  client.py        # subclasses Archipelago's CommonClient (network layer:
                    #   talks to the AP server, session/auth, item receive queue)
  memory.py         # process attach + read/write primitives (pymem or UE4SS
                    #   bridge, depending on the anti-cheat finding above)
  game_state.py      # maps raw memory reads -> semantic game events
                     #   (frog N collected, boss N defeated, item slot changed)
  item_effects.py     # maps an incoming AP item -> the memory write / game
                      #   call that actually grants it in-game
  config.py            # per-game-version offset tables (kept out of code)
```

Communication with the AP server reuses Archipelago's existing Python
`CommonClient` base (same approach as most PC-game AP clients) rather than
reimplementing the network protocol.

## Build plan / milestones

1. **Recon**: confirm anti-cheat status; pick UE4SS vs. raw memory vs.
   save-diffing based on that answer. Get the game process attachable/inspectable
   at all with the chosen tool.
2. **Read one flag**: find and reliably read a single stable value — e.g. player
   HP or one frog-collected bit — proving the read path works across a game
   session (menu, load, etc. don't break it).
3. **Write one effect**: find and reliably trigger one item grant — e.g. give
   the player a ration — proving the write path works.
4. **Vertical slice with the apworld**: wire steps 2+3 into `client.py`'s AP
   session — collecting the one real frog sends a real check to a real
   Archipelago server; the server sending one real item back actually grants
   it in-game. This is the project's proof-of-concept milestone, matched to the
   apworld repo's milestone 3.
5. **Expand the memory map**: grow `game_state.py`/`item_effects.py` to cover
   the full item/location set as the apworld repo's tables grow — one
   location/item is added to the apworld only once it's confirmed working here.
6. **Resilience**: handle disconnects/reconnects, resyncing already-received
   items after a relaunch, and (optionally) death link.
7. **Packaging**: ship as an installable UE4SS mod + small launcher, or a
   standalone executable, depending on what step 1 lands on.

## Status

As of 2026-07-26: tooling/CI fully wired and green on GitHub (lint, types,
tests+coverage, mutation testing, Codecov upload all confirmed working —
see [`CONTRIBUTING.md`](./CONTRIBUTING.md)). No connector logic yet — every
`.py` file is still a stub. **Recon (milestone 1) is mostly done**: no
anti-cheat, UE5 confirmed, and UE4SS injects/hooks this game's core
functions — but its `GUObjectArray` signature doesn't match this build
under any engine version tried (5.1–5.6), so it's not fully usable yet
without a custom AOB signature. See `research/NOTES.md` for the full log.
**Blocked on a decision**: build a custom UE4SS signature for this game vs.
switch to raw memory access (`pymem`) instead — both are real work, not a
quick fix, and picking one determines the rest of this repo's architecture.

## Development

Clean code/architecture rules (including the ports-and-adapters split that
keeps I/O out of the testable logic), the 100%-logic-tested policy, and how
to run the full check suite locally are in [`CONTRIBUTING.md`](./CONTRIBUTING.md).

CI and Codecov are already fully configured and working — no setup needed
before starting recon work.

## Readiness checklist (once the connector is functional)

Not relevant yet — revisit once the vertical-slice milestone above is done.
Unlike the apworld, the client isn't submitted/merged into Archipelago's
core repo — clients are distributed as their own repo/executable, same
pattern as every other PC-game AP client. Before calling it done, it needs
to actually satisfy the client hard requirements: secure and insecure
websocket handling, auto-reconnect, port-change support on saved connection
info, status updates on goal completion, location-check detection/reporting,
on-demand item receipt (including duplicate items), and a received-items
index for resync after reconnect. Subclassing `CommonClient` (per the
planned architecture above) covers most of this for free.

If MGS Δ ends up with a world merged into Archipelago's core repo, note
that the ongoing **world maintainer** obligations (Discord presence, PR
review, testing against `main`) land on whoever maintains
`mgsdelta-apworld`, not on this repo.

## Legal / scope note

This connector is for personal, offline, single-player randomizer use only —
the same spirit as every other Archipelago PC-game client. It must not be used
to interact with any online/leaderboard component of the game, and development
should stop and reassess if recon turns up active anti-cheat protecting those
online features.

## License

[MIT](./LICENSE) — matches Archipelago core's own license, since this
client is meant to plug into an Archipelago server/session.
