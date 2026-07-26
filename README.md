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
Recon confirmed the approach is UE4SS (see below); once `memory.py` starts
bridging to it and `client.py` starts subclassing Archipelago's
`CommonClient`, this section will grow real runtime dependencies, likely
including a pinned Archipelago core checkout the same way `mgsdelta-apworld`
vendors one — see that repo's README for the pattern. `.venv/bin/pytest --cov`
should pass as-is. See [`CONTRIBUTING.md`](./CONTRIBUTING.md) for the full
check suite.

## Recon findings (architecture now committed)

- **Anti-cheat**: does MGS Δ ship with Easy Anti-Cheat or similar? **Resolved
  2026-07-26: no.** Confirmed both by inspecting the install tree (no
  EasyAntiCheat/BattlEye files anywhere) and by launching the game live and
  checking the process list — only the launcher stub and the shipping exe
  run, no AC process spawns. Module enumeration against the live process
  also succeeded cleanly (156 modules, no access-denied), meaning it isn't
  running as a protected process either. See `research/NOTES.md` for detail.
- **Engine**: the game is Unreal Engine 5, specifically **UE 5.3** —
  **confirmed**. [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS) **fully
  works against this game**: using the `experimental` dev build
  (`zDEV-UE4SS_v3.0.1-464-gc343a32.zip`) plus a community-contributed
  `GUObjectArray.lua` signature
  ([mattdavida/MGS-Delta-UE4SS-Fix](https://github.com/mattdavida/MGS-Delta-UE4SS-Fix))
  plus `EngineVersionOverride = 5.3`, UE4SS resolves every core signature,
  constructs all core UObject classes, dumps full member offsets, hooks
  native functions, and runs its bundled Lua mods — confirmed live against
  a real game session. See `research/NOTES.md` for the full recipe and log.
- **Save-game feasibility as a fallback**: no longer needed given how clean
  the anti-cheat/access results are — only revisit if UE4SS or raw memory
  access hits an unexpected wall.
- **Patch churn**: every game update can move memory offsets. The design should
  isolate all raw offsets behind a small, versioned mapping file, not scatter
  them through the code.

## Planned architecture (confirmed by recon above)

```
mgsdelta_connector/
  client.py        # subclasses Archipelago's CommonClient (network layer:
                    #   talks to the AP server, session/auth, item receive queue)
  memory.py         # bridge to UE4SS via file polling (confirmed viable --
                    #   plain io.open/write works fine from UE4SS Lua, no
                    #   sockets/HTTP available or needed): a state file the
                    #   in-game Lua script writes on a timer, and a commands
                    #   file this process writes for the Lua side to poll
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

1. ~~**Recon**: confirm anti-cheat status; pick UE4SS vs. raw memory vs.
   save-diffing based on that answer. Get the game process attachable/inspectable
   at all with the chosen tool.~~ **Done** — no anti-cheat, UE4SS confirmed
   working. See `research/NOTES.md`.
2. ~~**Read one flag**: find and reliably read a single stable value — e.g.
   player HP or one frog-collected bit — proving the read path works across
   a game session (menu, load, etc. don't break it).~~ **Done** — reads the
   duck ("Gako") collectible counter live via `BP_KerotanSubsystem_C`'s
   `GetGakoUnlockStatus()`, confirmed matching the HUD. See
   `research/NOTES.md`. (Frogs/"Kerotan" share the same subsystem but their
   aggregate-count function isn't found yet — ducks are the first real
   target for that reason, see below.)
3. ~~**Write one effect**: find and reliably trigger one item grant — e.g.
   give the player a ration — proving the write path works.~~ **Done** —
   read/wrote/read-back/restored `Gako_Life` on a live `BP_Gako_C` actor via
   `UObject:SetPropertyValue`, a full reversible round-trip proof. See
   `research/NOTES.md`. (The more obviously "grant an item" -shaped
   `GakoSetCollected()` call also works, but only provably so on a duck
   that isn't already collected — worth revisiting once milestone 4 needs
   a real collect-style write.)
4. **Vertical slice with the apworld**: wire steps 2+3 into `client.py`'s AP
   session — collecting one real duck sends a real check to a real
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
`.py` file is still a stub, but **milestones 1, 2, and 3 are all done**: no
anti-cheat, engine confirmed UE 5.3, UE4SS fully working (see
`research/NOTES.md` for the exact recipe), a real live value — the duck
("Gako") collectible counter — successfully read through it via a Lua mod
(confirmed matching the in-game HUD), and a real write confirmed via a full
read/write/read-back/restore round trip on a live actor's property.
**Scope note**: the duck collectible is the first real target (not frogs)
— same subsystem, but the frog aggregate-count function isn't found yet and
ducks already work end to end for both read and write. Next: milestone 4,
the vertical slice (wire both into `client.py`'s real AP session).

## Development

Clean code/architecture rules (including the ports-and-adapters split that
keeps I/O out of the testable logic), the 100%-logic-tested policy, and how
to run the full check suite locally are in [`CONTRIBUTING.md`](./CONTRIBUTING.md).

CI and Codecov are already fully configured and working — no setup needed
before starting milestone 2 work.

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
