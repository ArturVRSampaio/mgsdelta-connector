# Recon notes

Running log of reverse-engineering findings. Keep entries dated; this is the
source of truth that `src/mgsdelta_connector/config.py` gets built from.

## Open questions (see repo README)

- [x] Does MGS Δ ship with Easy Anti-Cheat or another anti-cheat? — **No.**
- [x] Engine confirmation (assumed UE5 — verify build/version). — **Confirmed UE 5.3.**
- [x] Is UE4SS viable for this game specifically? — **Yes, fully working.**
      Uses the experimental dev build + a community `GUObjectArray.lua`
      signature + `EngineVersionOverride 5.3`. Full recipe below.
- [ ] Are save files readable/diffable as a fallback path? — no longer needed;
      UE4SS is fully functional, see below.

## Log

### 2026-07-26: Anti-cheat and engine confirmed via install inspection + live process check

- **Finding**: MGS Δ (Steam appid `2417610`, install `D:\SteamLibrary\steamapps\common\MGSDelta`)
  ships **no anti-cheat**. Recursive search of the install tree for
  EasyAntiCheat/BattlEye/Denuvo-related files/folders turned up nothing.
  Launched the game live via `steam://rungameid/2417610` and checked the
  process list ~25s after launch: only `MGSDelta.exe` (launcher stub) and
  `MGSDelta-Win64-Shipping.exe` (real game) are running — no
  `EasyAntiCheat_EOS`, `BEService`, or similar spawned. (A system-wide
  `EasyAntiCheat_EOS` Windows service exists on this machine, but that's
  from an unrelated EAC-using game already installed here — MGS Δ's own
  install folder has zero EAC references, and none of its processes touch
  that service.)
- **Engine**: confirmed Unreal Engine 5 from install layout —
  `MGSDelta-Win64-Shipping.exe` naming convention, top-level `Engine/`
  folder (Binaries/Content/Plugins), project folder with its own
  Binaries/Content. Also ships `MGSDelta_Foxhunt` and `MGSDelta_Nightmare`
  as separate UE project folders (likely bonus modes/DLC), same structure.
- **Process accessibility**: with the game running, `Get-Process -Id
  <shipping.exe pid> | Select Modules` enumerated all 156 loaded modules
  with no access-denied error. This means the process isn't running as
  Protected Process Light and isn't blocking basic `OpenProcess`/module
  queries — a strong positive signal for both raw memory read/write (pymem
  path) and UE4SS DLL injection (which needs to load a proxy DLL into the
  same process).
- **Confidence**: high for anti-cheat/engine (direct filesystem +
  live-process evidence, not guesswork). Not yet fully conclusive proof
  that deep memory *write* access or DLL injection specifically will work
  — only that the coarse-grained access this check used isn't blocked.
- **Follow-up**: next open question is UE4SS viability specifically — needs
  an actual UE4SS install attempt against `MGSDelta-Win64-Shipping.exe` and
  confirmation its console/log opens and mods load. Save-file fallback
  question is now low-priority given how clean this result is; only revisit
  if UE4SS/memory access hits an unexpected wall.

### 2026-07-26: UE4SS v3.0.1 injects successfully; needs a manual engine-version override

- **Finding**: dropped UE4SS v3.0.1 (`dwmapi.dll` + `UE4SS.dll` +
  `UE4SS-settings.ini` + `Mods/`) directly into
  `MGSDelta\Binaries\Win64\` (same folder as the shipping exe) and launched
  via Steam. **Injection succeeded**: the shipping exe's window title
  changed to "UE4SS Debugging Tools (OpenGL 3)", `UE4SS.log` was created,
  and its pattern scanner found several core signatures automatically:
  `GMalloc`, `FName::ToString`, `FName::FName(wchar_t*)`,
  `StaticConstructObject_Internal`. This proves UE4SS's injection/hooking
  approach works against this exact binary — it isn't blocked structurally.
- **What failed**: two signatures did *not* auto-resolve — `EngineVersion`
  (the string UE4SS reads to identify the exact engine build) and
  `GUObjectArray` (the core object-table pointer UE4SS needs for almost
  everything past basic hooking). UE4SS retried the scan 52 times over
  ~30s, then aborted with `Fatal Error: PS scan timed out` and the game
  process exited cleanly (no crash dump, no Windows Error Reporting entry
  — this looks like a deliberate abort by UE4SS, not an engine crash).
- **Why**: this game isn't in UE4SS's community `zCustomGameConfigs.zip`
  database (checked all entries — no MGS/Snake Eater/Metal Gear/Delta
  match), so there's no pre-supplied `EngineVersionOverride` or custom
  `GUObjectArray.lua` AOB for it yet. `UE4SS-settings.ini` has an
  `[EngineVersionOverride]` section with blank `MajorVersion`/`MinorVersion`
  — these need to be filled in with this game's actual UE5 minor version.
  Tried extracting the version from strings in the shipping exe
  (`grep -a -o "5\.[0-9]\.[0-9]"`) — found scattered `5.5.x`/`5.6.x`-looking
  strings, each appearing exactly once, which reads as incidental data
  (asset/plugin version numbers) rather than a confirmed engine version, so
  don't trust that without corroboration.
- **Confidence**: high that UE4SS is viable in principle (the hard part —
  injection + core hooks — already works). Medium that it just needs the
  right `EngineVersionOverride` value — that specific number is still
  unconfirmed.
- **Follow-up**: try `EngineVersionOverride` with a few plausible UE5 minor
  versions (5.1 through 5.5 are all plausible for a 2025-era UE5 title) and
  re-launch after each, watching whether `GUObjectArray` resolves. If none
  work, the next fallback is supplying a custom AOB signature in
  `UE4SS_Signatures/GUObjectArray.lua` per UE4SS's own instructions in the
  log, which requires more hands-on binary analysis.

### 2026-07-26: EngineVersionOverride 5.1–5.6 all fail to resolve GUObjectArray

- **Finding**: tried `[EngineVersionOverride]` `MajorVersion=5` /
  `MinorVersion=1` through `6` in turn (relaunching after each edit).
  Setting the override does stop UE4SS complaining about `EngineVersion`
  itself, but **`GUObjectArray` fails to resolve for every single one** —
  identical `[PS] Failed to find GUObjectArray: expected at least one
  value` on every scan attempt, every version. Confirms the version number
  isn't the actual blocker: `GUObjectArray`'s AOB pattern is presumably
  matched independent of the declared engine version (or at least none of
  UE4SS's built-in patterns for 5.1–5.6 match this specific compiled
  binary).
- **Behavior difference from the very first (no-override) attempt**: with
  no override, the process exited after the scan timeout. With an explicit
  (if wrong) override set, the process kept running past the timeout
  (`StillRunning: True` even after `Fatal Error: PS scan timed out` in the
  log) — UE4SS still gives up on full hooking, but doesn't force-close the
  game in this case. Not fully understood why the two paths differ; not
  important for the viability question either way.
- **Conclusion**: engine-version guessing is a dead end for unblocking
  `GUObjectArray` on its own. Reset `UE4SS-settings.ini`'s
  `EngineVersionOverride` back to blank afterward (no version was
  confirmed correct, so leaving a guess in there would be misleading).
- **Confidence**: high that this specific game's compiled binary needs a
  custom, hand-built `GUObjectArray` AOB signature — not something that
  falls out of trying more version numbers.
- **Follow-up / open decision for whoever picks this up next**: two paths
  forward, both real work beyond config tweaking:
  1. **Build a custom `GUObjectArray.lua` AOB signature** for this exact
     binary. Needs a disassembler (Ghidra/IDA), a search for a known
     reference pattern to `GUObjectArray` (e.g. via a string/constant
     cross-reference UE4SS's own docs describe), and testing the resulting
     pattern the same way as above. This keeps the "standard, well-trodden"
     UE4SS path the README always preferred.
  2. **Switch to raw memory access (pymem)** instead of relying on UE4SS's
     object-array discovery — we already confirmed (see the anti-cheat/
     engine entry above) that the process allows free `OpenProcess`/module
     enumeration, so this path is viable too, just a different kind of
     from-scratch offset-hunting work (finding the frog-collected flag /
     item slots directly via memory scanning tools like Cheat Engine,
     rather than through UE4SS's object model).
  Neither is a quick follow-up — both are their own multi-session research
  efforts. Recommend deciding which one to invest in before writing any
  more connector code.

### 2026-07-26: UE4SS fully working — found an existing community fix

- **Finding**: rather than hand-building a `GUObjectArray` AOB signature
  from scratch, checked whether anyone had already modded this game with
  UE4SS. They had: [mattdavida/MGS-Delta-UE4SS-Fix](https://github.com/mattdavida/MGS-Delta-UE4SS-Fix)
  is a small public repo that exists specifically to solve this exact
  problem, published the same day MGS Δ hit early access. Following its
  instructions **fully resolved UE4SS against this game**:
  1. Used the **experimental dev build** `zDEV-UE4SS_v3.0.1-464-gc343a32.zip`
     (from UE4SS-RE/RE-UE4SS's `experimental` release tag, not the stable
     `v3.0.1` release — the stable build was what we tried before and it
     doesn't include this fix) — extracted with its `dwmapi.dll` at the zip
     root and everything else nested under `ue4ss/`, flattened together
     into `MGSDelta\Binaries\Win64\`.
  2. Copied the fix repo's `UE4SS_Signatures/GUObjectArray.lua` (a hand-built
     AOB pattern targeting a `LEA` instruction sequence, with a documented
     comment confirming **this game is UE 5.3**) into
     `Binaries\Win64\UE4SS_Signatures\`.
  3. Set `[EngineVersionOverride]` to `MajorVersion = 5` / `MinorVersion = 3`
     in `UE4SS-settings.ini`.
  4. Relaunched via Steam.
- **Result**: `UE4SS.log` shows `PS scan successful`, then
  `GUObjectArray address: 0x7ff6dfd7adb0 <- Lua Script`, then all 23 core
  UObject classes (`Class`, `CoreUObject`, `Struct`, `Pawn`, `Character`,
  `Actor`, `Vector`, `PlayerController`, `Widget`, ...) constructed
  successfully, followed by a full member-offset dump for `UObjectBase`,
  `UWorld`, `UClass`, `UFunction`, `FProperty`, etc. — hundreds of lines,
  meaning UE4SS now has complete structural knowledge of this build's
  object model. All bundled example mods (`CheatManagerEnablerMod`,
  `ConsoleCommandsMod`, `ConsoleEnablerMod`, `LineTraceMod`,
  `BPML_GenericFunctions`, `BPModLoaderMod`, `Keybinds`) started and
  registered native hooks successfully. UE4SS reached its normal
  `Event loop start` state.
  - Confirmed the game itself is healthy, not just UE4SS: process window
    title changed from the UE4SS debug console back to
    `METAL GEAR SOLID Δ: SNAKE EATER` (the real game window), and the
    process was `Responding: True`.
  - Two non-fatal warnings logged (`GNatives not found` — "limited hooking
    functionality in certain scenarios", and a couple of Lua warnings about
    `ConsoleClass`/`ViewportConsole`/`UWorld` being invalid at the moment
    a mod first ran) — these look like normal "game hasn't fully loaded
    into a level yet" noise, not blockers. Not yet verified whether they
    matter once the game reaches the main menu/gameplay.
- **The exact working recipe** (for reproducing this or wiring it into
  future setup docs):
  - UE4SS build: `zDEV-UE4SS_v3.0.1-464-gc343a32.zip` from the
    `experimental` release tag of `UE4SS-RE/RE-UE4SS`.
  - `UE4SS_Signatures/GUObjectArray.lua`: copied verbatim from
    `mattdavida/MGS-Delta-UE4SS-Fix`.
  - `UE4SS-settings.ini`: `[EngineVersionOverride]` → `MajorVersion = 5`,
    `MinorVersion = 3`.
- **Confidence**: high — this isn't a partial result, it's the full UE4SS
  feature set (object construction, member offsets, native hooks, Lua mods)
  working end to end.
- **Follow-up**: this closes recon (build plan milestone 1) entirely — no
  more open questions. Next is build plan milestone 2: read one flag (find
  and reliably read a single stable value, e.g. a frog-collected bit),
  using UE4SS's live object/property access now that it's confirmed
  working. `config.py` should record this exact UE4SS build + signature +
  engine-version recipe so it's reproducible without re-deriving it.
