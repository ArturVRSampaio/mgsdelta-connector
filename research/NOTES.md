# Recon notes

Running log of reverse-engineering findings. Keep entries dated; this is the
source of truth that `src/mgsdelta_connector/config.py` gets built from.

## Open questions (see repo README)

- [x] Does MGS Δ ship with Easy Anti-Cheat or another anti-cheat? — **No.**
- [x] Engine confirmation (assumed UE5 — verify build/version). — **Confirmed UE5.**
- [ ] Is UE4SS viable for this game specifically?
- [ ] Are save files readable/diffable as a fallback path?

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
