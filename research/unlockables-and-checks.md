# Unlockables and checks — design catalog

Ground-truth catalog for `mgsdelta-apworld`'s item/location pools (README
"Item pool"/"Location pool" sections), backed by what's actually confirmed
technically feasible in this repo — not draft guesses. Each entry is marked
with its confidence status. Nothing here should move into `Items.py`/
`Locations.py` until it's at least "confirmed feasible" (per that repo's own
rule: "no location goes in until the connector can actually check it, no
item goes in until the connector can actually grant it").

## Status legend

- ✅ **Confirmed live** — actually tested against the running game this session/project.
- 🔧 **Confirmed feasible** — the underlying mechanism (offset/pattern/hook) is known and validated in principle, just not exercised for this specific entry yet.
- ❓ **Speculative** — plausible based on known data, needs research before relying on it.

## Items (unlockables)

Granting an item/weapon means writing to the `WeaponsTable`/`ItemsTable`
via the native-memory technique in `research/game-hooks.md`. Ammo refill
uses the same mechanism on an already-owned weapon.

### Weapons — ✅ confirmed feasible as a class (Mosin grant tested live), 🔧 for the rest by the same mechanism

All 30 entries in `research/game-hooks.md`'s weapon index table. Candidate
progression-vs-filler split for apworld's item pool:

- **Progression candidates**: weapons needed for specific fights/areas per
  the README's draft plan (needs a real playthrough cross-reference to
  confirm which, if any, are truly required vs. just convenient).
- **Useful/filler**: the rest — most weapons in a stealth game are optional.
- **Ammo refill**: not a discrete unlock, but a good repeatable filler item
  type ("+X ammo for current weapon" or a specific weapon) — ✅ confirmed
  live (MK22 test).

### Items — 🔧 confirmed feasible as a class, same mechanism as weapons

Full index table in `research/game-hooks.md`. Rough categorization for
apworld's pool design:

- **Key items** (story-critical/progression candidates): `KEY A/B/C`,
  `CROC CAP`, `CROC CAP (ONE EYED)`, `BANDANA`, `MONKEY MASK`, `AT CAMO`,
  `COMPASS`, `GAKO MASK`, `KEROTAN MASK`, gold cap items — needs
  cross-referencing against a real playthrough to know which actually gate
  progression vs. are just collectibles.
- **Tools/gadgets** (progression or useful, TBD): `BINOCULARS`, `THERMAL
  GOGGLES`, `NIGHT VISION GOGGLES`, `CAMERA`, `MOTION DETECTOR`, `ACTIVE
  SONAR`, `MINE DETECTOR`, `ANTI PERSONNEL SENSOR`, `DIRECTIONAL
  MICROPHONE` (weapon table).
- **Medicine/consumables** (good filler — capacity-based, same mechanism
  as ammo): `LIFE MEDICINE`, `PENTAZEMIN`, `SERUM`, `ANTIDOTE`, `COLD
  MEDICINE`, `DIGESTIVE MEDICINE`, `OINTMENT`, `SPLINT`, `DISINFECTANT`,
  `STYPTIC`, `BANDAGE`, `SUTURE KIT`, `FAKE DEATH PILL`, `BUG JUICE`.
- **Camouflage uniforms** (54 entries, indices 50–103) and **face paint**
  (23 entries, indices 116–138): classic "useful, non-required" filler —
  matches README's draft plan exactly, now with real indices instead of a
  guess. `CBOX A–D` are destructible-crate-adjacent items, not camo, listed
  separately in the item table.
- **Suppressors** (`M1911A1`/`MK22`/`XM16E1 SURPRESSOR`): useful, non-required.
- **Exclude from the real pool**: indices 104–115 (DLC/placeholder table
  padding — confirmed by the reference trainer's own comments, not real
  grantable content) and `BATTERY` (index 46 — trainer's own notes flag its
  purpose as unclear; don't rely on it without more research).

### Not yet a candidate item type

- **Health/stamina/stats** (`research/game-hooks.md`'s "other confirmed
  hooks" section) — these are trainer conveniences (cheat-style), not
  Archipelago-shaped unlocks. Could inform *traps* (README's draft trap
  list: hunger-drain, stamina-drain) more than items, if pursued later.

## Locations (checks)

### Frogs (Kerotan) — ✅ confirmed live

Aggregate counter (`GetKerotanUnlockStatus`), 64 locations, threshold-based
(location N checked once the live count reaches N). Currently the only
location set actually wired into `game_state.py`/`client.py`.

### Ducks (Gako) — mixed status, worth re-examining

- ✅ **Confirmed live**: the *write* side (`unlock_duck` command via
  `FindUncollectedGako`/`GakoSetCollected`) still works and is kept in the
  bridge mod.
- **Aggregate counter removed from this project** (per the recent
  decision) — not being used as a check source anymore.
- 🔧 **Worth reconsidering**: milestone 4's investigation (`research/NOTES.md`)
  found that a `RegisterHook` on `GakoComponent:GakoSetCollected` fires
  reliably on a real, different object each time a duck is actually
  collected in normal play — this is a genuine per-event detection
  mechanism, independent of the aggregate counter, and was never wired into
  the bridge mod as a location-check source. If ducks come back into scope
  later, this hook (not the counter) is the right mechanism — it tells you
  *which* duck was collected, not just that the total went up.

### Boss defeats — ❓ speculative

`research/game-hooks.md` lists confirmed HP/stamina *offsets* for Ocelot,
The Fear, The Pain (Volgin), The End, The Fury, Shagohod, Volgin-on-
Shagohod, and The Boss (via the trainer's `MainPointerAddresses`/
`BossOffsets`) — but "defeated" isn't the same as "HP reached 0" in a
cutscene-driven boss fight; no research has gone into what actually flags
a fight as complete (a cutscene trigger, a save flag, a level-transition
event). Matches the README's draft "Cobra Unit boss defeats" location
group — needs real research before it's more than a guess.

### Camo/item pickups (natural acquisition) — ❓ speculative, has a real design trap

The README's draft plan lists "weapon/item pickup spots" as a location
group. **Important gotcha for whoever picks this up**: the natural pickup
event and our own item-grant mechanism likely touch the *same*
`WeaponsTable`/`ItemsTable` memory. A naive "diff the table, anything that
changed is a check" approach would misfire on our own grants (an AP item
we just gave the player would look identical to the player finding it
naturally). This needs either:
- a distinct pickup-event hook (e.g. `UGsrPlayerGetItemAction`, seen in the
  earlier `CXXHeaderDump` exploration, never followed up on) instead of
  table-diffing, or
- some way to distinguish "we just wrote this" from "the game just wrote
  this" (e.g. a short suppression window around our own writes).
Don't attempt table-diffing for this without solving that first.

### Area/map transitions — ❓ speculative

`Constants.cs`' `MapStringSub`/`Offsets.Strings.CurrentMap` (see
`research/MGS3-Delta-Trainer-ref/Constants.cs`) reads the current map as a
string. Could plausibly detect "reached area X" as a location, but nobody
has actually read this live yet — unconfirmed.

### Game stat milestones — ❓ speculative, low priority

Kills, alerts triggered, continues, saves, meals eaten, playtime
(`Constants.cs`' `MainPointerAddresses`) are all readable in principle, but
"kill N guards" / "eat N meals" is a very different flavor of check than
the rest of this pool and doesn't match README's draft direction. Noted
for completeness, not recommended as a near-term target.

## Immediate next research steps, in priority order

1. Confirm whether `UGsrPlayerGetItemAction` (or similar) is a real,
   hookable pickup-event distinct from writing the tables directly — this
   unblocks the camo/item-pickup location group and resolves the
   grant/detect collision above.
2. Read `MapStringSub` live once, to see if area-transition detection is
   actually viable as a cheap early win.
3. Cross-reference a real playthrough against the item lists above to
   split progression vs. useful vs. filler for real, instead of guessing.
4. Boss-defeat detection needs its own investigation session — not a quick
   follow-up.
