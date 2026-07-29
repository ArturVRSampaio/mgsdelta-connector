# Game hooks reference — native process memory

Concrete, lookup-friendly reference for reading/writing MGS Δ's live game
state via direct process memory (AOB scan + fixed offsets), as opposed to
the UE4SS/Blueprint reflection path documented in `NOTES.md`. See the
2026-07-28 `NOTES.md` entry for how this was found and why the reflection
path is a dead end for ammo/items specifically.

Source of truth for all of this: [ANTIBigBoss/MGS3-Delta-Trainer](https://github.com/ANTIBigBoss/MGS3-Delta-Trainer)
(C#, MIT-style community trainer, ~75% ported from an older MGS3 trainer).
Full original source vendored for reference at `research/MGS3-Delta-Trainer-ref/`.
Confirmed PoC: `research/probes/test_ammo_write.py` (Python/`pymem`).

Process name: `MGSDelta-Win64-Shipping.exe`.

## Gotcha: AOB patterns are not unique module-wide

Every pattern below can match multiple locations in the module. Confirmed
live: the `WeaponsTable` pattern had **5 matches** module-wide, only **3**
inside the documented RVA range. Always filter candidate matches by
`(match_address - module_base)` falling inside the given RVA range before
trusting one — an out-of-range match reads/writes plausible-looking but
wrong data (e.g. `current_ammo=19640` from a false match vs. the real `65`).

## Weapons table

- Pattern: `00 00 AA 77 63 00` (6 bytes, no wildcards)
- Expected RVA range (offset from module base): `0x135A0000`–`0x135F0000`
- Entry base address: `aob_address + len(pattern) + 16 + (88 * index)`
- Entry size: 88 bytes
- Per-entry offsets (all `short`, 2 bytes):
  - `CurrentAmmo` = 0
  - `MaxAmmo` = 2 (only meaningful if the weapon has ammo)
  - `Clip` = 4 (only if the weapon has a clip)
  - `MaxClip` = 6
  - `SuppressorToggle` = 16 (`16` = on, `0` = off; only if the weapon can take a suppressor)
- Weapon toggle on/off (possession): write `short` `1` (own it) or `-1`
  (don't) directly at the entry base address (offset 0 is reused for this
  when the weapon has no ammo, e.g. Survival Knife).

### Weapon index table

| Index | Name | Ammo | Clip | Suppressor |
|---|---|---|---|---|
| 0 | Survival Knife | | | |
| 1 | Fork | | | |
| 2 | Cigspray | ✓ | | |
| 3 | Handkerchief | ✓ | | |
| 4 | MK22 | ✓ | ✓ | ✓ |
| 5 | M1911A1 | ✓ | ✓ | ✓ |
| 6 | Ez Gun | | | |
| 7 | SAA | ✓ | ✓ | |
| 8 | Patriot | | | |
| 9 | Scorpion | ✓ | ✓ | |
| 10 | XM16E1 | ✓ | ✓ | ✓ |
| 11 | AK47 | ✓ | ✓ | |
| 12 | M63 | ✓ | ✓ | |
| 13 | M37 | ✓ | ✓ | |
| 14 | SVD | ✓ | ✓ | |
| 15 | Mosin | ✓ | ✓ | |
| 16 | RPG7 | ✓ | ✓ | |
| 17 | Torch | | | |
| 18 | Grenade | ✓ | | |
| 19 | Wp Grenade | ✓ | | |
| 20 | Stun Grenade | ✓ | | |
| 21 | Chaff Grenade | ✓ | | |
| 22 | Smoke Grenade | ✓ | | |
| 23 | Empty Magazine | ✓ | | |
| 24 | TNT | ✓ | | |
| 25 | C3 | ✓ | | |
| 26 | Claymore | ✓ | | |
| 27 | Book | ✓ | | |
| 28 | Mousetrap | ✓ | | |
| 29 | Directional Microphone | | | |

## Items table

- Pattern: `00 00 DA 5A 2B 00` (6 bytes, no wildcards)
- Expected RVA range: `0x13400000`–`0x135FEEEE`
- Entry base address: `aob_address + len(pattern) + 12 + (80 * index)`
- Entry size: 80 bytes
- Per-entry offsets (`short`, 2 bytes):
  - `CurrentCapacity` = 0
  - `Max` = 2 (only for items that have a max capacity)
- **Item grant/unlock** (the direct analog of an Archipelago item grant):
  write `short` `1` at the entry base offset to give the player an item
  they don't have (`-1` to remove). This is the mechanism to use for
  granting arbitrary items, not just refilling ammo on already-owned
  weapons.
- Items with a capacity (medicine, ammo-like consumables) instead get their
  `CurrentCapacity`/`Max` written directly, same pattern as weapon ammo.

### Item index table

| Index | Name | Has capacity |
|---|---|---|
| 0 | LIFE MEDICINE | ✓ |
| 1 | PENTAZEMIN | ✓ |
| 2 | FAKE DEATH PILL | ✓ |
| 3 | REVIVAL PILL | |
| 4 | CIGAR | |
| 5 | BINOCULARS | |
| 6 | THERMAL GOGGLES | |
| 7 | NIGHT VISION GOGGLES | |
| 8 | CAMERA | |
| 9 | MOTION DETECTOR | |
| 10 | ACTIVE SONAR | |
| 11 | MINE DETECTOR | |
| 12 | ANTI PERSONNEL SENSOR | |
| 13 | CBOX A | |
| 14 | CBOX B | |
| 15 | CBOX C | |
| 16 | CBOX D | |
| 17 | CROC CAP | |
| 18 | KEY A | |
| 19 | KEY B | |
| 20 | KEY C | |
| 21 | BANDANA | |
| 22 | STEALTH CAMO | |
| 23 | BUG JUICE | ✓ |
| 24 | MONKEY MASK | |
| 25 | AT CAMO | |
| 26 | COMPASS | |
| 27 | ITM2 | |
| 28 | GAKO MASK | |
| 29 | KEROTAN MASK | |
| 30 | BANANA CAP (GOLD) | |
| 31 | BOMB CAP (GOLD) | |
| 32 | BOMB CAP | |
| 33 | CROC CAP (ONE EYED) | |
| 34 | ITM9 | |
| 35 | SERUM | ✓ |
| 36 | ANTIDOTE | ✓ |
| 37 | COLD MEDICINE | ✓ |
| 38 | DIGESTIVE MEDICINE | ✓ |
| 39 | OINTMENT | ✓ |
| 40 | SPLINT | ✓ |
| 41 | DISINFECTANT | ✓ |
| 42 | STYPTIC | ✓ |
| 43 | BANDAGE | ✓ |
| 44 | SUTURE KIT | ✓ |
| 45 | KNIFE | |
| 46 | BATTERY | (unclear, needs investigation) |
| 47 | M1911A1 SURPRESSOR | |
| 48 | MK22 SURPRESSOR | |
| 49 | XM16E1 SURPRESSOR | |
| 50–103 | Camouflage uniforms (see `WeaponItemManager.cs` for the full list — Olive Drab, Tiger Stripe, ... White Tuxedo) | |
| 104–115 | DLC/placeholder outfits — table padding only, don't use as real grants | |
| 116–138 | Face paint options (see `WeaponItemManager.cs`) | |

For the full authoritative enumeration (including every camo/face-paint
name), read `research/MGS3-Delta-Trainer-ref/WeaponItemManager.cs` directly
rather than trusting a re-transcription.

## Other confirmed hooks (not yet used by this project, but validated by the trainer)

These use a different mechanism — a single main pointer
(`MainPointerRegionOffset = 0xC532038` from module base) plus fixed
sub-offsets — not AOB scanning. Useful if health/stats/injury features are
ever wanted:

- Current health: main pointer − 968 (`short`)
- Max health: main pointer − 966 (`short`)
- Current stamina: main pointer − 2 (`short`)
- Difficulty, continues, saves, alerts triggered, kills, playtime, etc.:
  see `Constants.cs` `MainPointerAddresses` enum.
- 68 serious-injury slots, 14 bytes apart, byte patterns per injury type in
  `Constants.cs` `InjuryData.GetInjuryBytes`.
- Several boss HP/stamina offsets (Ocelot, The Fear, The Pain, The End,
  Volgin, The Fury, Shagohod, The Boss) in `Constants.cs` `BossOffsets`.

None of these have been read/written from this project yet — listed here so
future work doesn't have to re-derive them from the trainer source again.

## Food/animal collection log — ✅ confirmed live (read-only), via UE4SS reflection, not AOB

Food/animal data is **not** part of the flat `ItemsTable` above — it's a
`TMap<int32, FFoodMemoryData>` on the live `UUserProfileSaveGame` object
(confirmed via `CXXHeaderDump`'s `MGS3.hpp`), a completely different shape
(hash map + a 12-byte struct: `bCaptured` bool, `EatNum` int32, `Type`
byte enum, `bHeard` bool, `bNewBadge` bool). A raw-memory test on the
`ItemsTable` region right after the mapped 139 items (indices 152-160)
produced plausible-looking but **wrong** numbers — always use reflection
for this, not AOB, since it's a real map, not a flat array.

### How to read it (Lua/UE4SS)

```lua
local SaveGame = FindFirstOf("UserProfileSaveGame")
local FoodMap = SaveGame.SnakeFoodsMemoryData -- or EvaFoodsMemoryData
FoodMap:ForEach(function(Key, Value)
    -- Key and Value come through as RemoteUnrealParam wrappers here,
    -- same as a RegisterHook's `self` -- :get() unwraps to the real
    -- int32 key / real struct, confirmed live.
    local realKey = Key:get()
    local realVal = Value:get()
    -- realVal.bCaptured, realVal.EatNum, realVal.Type now read correctly
end)
```

Confirmed live: `Food[86] bCaptured=true EatNum=7 Type=3` matched a
real, independently-known value (player had eaten Mushroom E exactly 7
times). **This map is a lifetime history/achievement log only** —
`bCaptured`/`EatNum` never reset and there is no "currently carried count"
field on it at all. The live carried-food inventory (what actually shows
in the in-game food menu right now) is a **different, still-unfound**
piece of state — this only answers "have I ever caught/eaten this," not
"how many am I carrying right now."

### Food/animal ID table (`EWeaponName` enum, `MGS3_enums.hpp`)

Despite the enum's name, IDs 31-130 are food/animal, not weapons (0-30 and
131+ are real weapons, including enemy-only ones). `Type` in
`FFoodMemoryData` is a separate, coarser `EAnimalType` enum (`Snakes=0`,
`LandAnimals=1`, `WaterfrontAnimals=2`, `Mushrooms=3`, `Others=4`) — not
the same value space as the ID below.

| ID | Name | | ID | Name |
|---|---|---|---|---|
| 31-46 | `FD_FoodSlot0`-`FD_FoodSlot15` (generic bait/throw slots) | | 89 | Fruit A |
| 47-49 | `FD_AnimalSlot0`-`FD_AnimalSlot2` (generic slots) | | 90 | Fruit B |
| 50-60 | Hebi (snake) A-K, as food | | 91 | Fruit C |
| 61 | Crocodile, as food | | 92 | Vegetable A |
| 62-64 | Frog A-C, as food | | 93 | Noodle |
| 65 | Rat, as food | | 94 | Ration |
| 66 | Rabbit, as food | | 95 | Potato |
| 67 | Squirrel, as food | | 96 | Beehive (pain variant) |
| 68 | Mutton, as food | | 97 | Tutinoko |
| 69 | Bat, as food | | 98-108 | Hebi (snake) A-K, as live animal |
| 70 | Beehive, as food | | 109 | Crocodile, as live animal |
| 71 | Scorpion, as food | | 110-112 | Frog A-C, as live animal |
| 72 | Spider, as food | | 113 | Rat, as live animal |
| 73-77 | Bird A-E, as food | | 114 | Rabbit, as live animal |
| 78-80 | Fish A-C, as food | | 115 | Squirrel, as live animal |
| 81 | Crab, as food | | 116 | Mutton, as live animal |
| 82-88 | Mushroom A-G, as food | | 117 | Bat, as live animal |
| | | | 118 | Beehive, as live animal |
| | | | 119 | Scorpion, as live animal |
| | | | 120 | Spider, as live animal |
| | | | 121-125 | Bird A-E, as live animal |
| | | | 126-128 | Fish A-C, as live animal |
| | | | 129 | Crab, as live animal |
| | | | 130 | Tutinoko, as live animal |

The "as food" (50-97) vs. "as live animal" (98-130) split matches MGS3's
real mechanic: the same creature can be caught alive (to release/throw/use
as bait) or consumed as food — two different inventory concepts, both
tracked in the same `SnakeFoodsMemoryData`/`EvaFoodsMemoryData` maps.

### Still unknown

Where the **live carried count** (e.g. "you currently have 2 Mushroom E")
actually lives — not this map, not the `ItemsTable`. Needs its own
investigation, likely another live UObject/component (possibly on
`UGsrItemController` or a dedicated food/survival component), read via the
same reflection technique once found.
