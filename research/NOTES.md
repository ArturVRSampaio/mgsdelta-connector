# Recon notes

Running log of reverse-engineering findings. Keep entries dated; this is the
source of truth that `src/mgsdelta_connector/config.py` gets built from.

## Blocked: needs a machine with the game installed

As of 2026-07-26, recon hasn't started because the game isn't installed on
the dev machine used so far. Nothing below has been investigated yet — this
is a fresh checklist, not a "started and stuck" list. Whoever picks this up
next needs a PC with MGS Δ actually installed before any of the "Open
questions" below can be answered. Until then, work on `mgsdelta-apworld`'s
frog-only skeleton instead (doesn't need the game — see that repo's README
build plan).

## Open questions (see repo README)

- [ ] Does MGS Δ ship with Easy Anti-Cheat or another anti-cheat?
- [ ] Engine confirmation (assumed UE5 — verify build/version).
- [ ] Is UE4SS viable for this game specifically?
- [ ] Are save files readable/diffable as a fallback path?

## Log

<!-- 2026-xx-xx: entry template
### <topic>
- Finding:
- How found:
- Confidence:
- Follow-up:
-->
