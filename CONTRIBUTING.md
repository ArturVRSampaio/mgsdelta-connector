# Development rules

This repo enforces its rules with tooling, not just convention. Everything in
this document is checked by CI on every push — see `.github/workflows/ci.yml`.

## Clean code

- Small, single-responsibility functions. A function does one thing; if you
  need "and" to describe it, split it.
- Descriptive names over comments. Comments explain *why*, never *what* —
  if a comment just restates the code, delete the comment and rename instead.
- Guard clauses over nested conditionals.
- No dead code, no commented-out code, no speculative
  parameters/branches for cases that can't currently happen.
- Cyclomatic complexity is capped at 8 per function, enforced by
  `ruff` (`C90` rule set). If you hit the cap, the function is telling you to
  split it.

## Clean architecture: ports and adapters

This repo touches two real I/O boundaries — process memory and a network
socket — that can't be exercised by a unit test without a real running game
and a real Archipelago server. The whole point of the layering below is to
keep that unavoidable, untestable surface as small as physically possible,
and push everything else into pure, 100%-tested logic.

| Module | Responsibility | Testability |
|---|---|---|
| `memory.py` | Raw process attach + read/write (or the UE4SS bridge, depending on what recon lands on) | **The only place raw I/O calls are allowed to live.** Kept to thin wrappers around a typed interface (e.g. a `MemoryReader`/`MemoryWriter` `Protocol`) — no decision logic. |
| `client.py` | Network session with the AP server (subclasses `CommonClient`) | Same rule — network calls only, no game-logic decisions. |
| `game_state.py` | Maps raw reads → semantic events (frog N collected, boss N defeated) | **Pure logic. Must be 100% unit tested** against a fake `MemoryReader`, never a real process. |
| `item_effects.py` | Maps an incoming AP item → the write/call that grants it | **Pure logic. Must be 100% unit tested** against a fake `MemoryWriter`, never a real process. |
| `config.py` | Per-version offset tables | Data. Any accessor logic around it (version lookup, fallback behavior) counts as logic and needs tests. |

Concretely: `game_state.py` and `item_effects.py` must depend on an
interface (`Protocol`), not a concrete `memory.py` class, so tests can inject
a fake and never touch a real process. If you find game-logic decisions
creeping into `memory.py` or `client.py`, that's the signal to pull them out
into `game_state.py`/`item_effects.py` instead.

## Testing policy: every line of logic is tested

- **100% line coverage is a CI gate** — `pytest --cov --cov-fail-under=100`
  (see `pyproject.toml`). A PR that drops coverage fails CI.
- Coverage alone proves a line *executed*, not that it's *correct*.
  **mutmut** rewrites your logic and every mutant must be killed by an
  existing test; a survivor means the test runs the line but never actually
  checks its behavior. Fix survivors by strengthening assertions, not by
  adding a no-op call to bump coverage.
- The one narrow exception: a literal I/O call in `memory.py`/`client.py`
  (the actual `ReadProcessMemory`/socket-connect line itself) may carry
  `# pragma: no cover` if it genuinely cannot be exercised without a real
  game/server. Scope it to that single line, never a whole function — and if
  you're reaching for more than one `pragma` per function, the real fix is
  moving logic out of that module, not excluding more lines.
- Because CI can't run the actual game, there is no automated end-to-end
  test of the full pipeline. That gets verified manually against a real
  game session at each milestone in the README's build plan — log the
  result in `research/NOTES.md` when a milestone is confirmed working.

### Bootstrapping note

`mutmut` needs at least one real function in the codebase to hook its
self-check into — on a tree of pure stub/docstring files (like this repo
today) it fails with a misleading error. `scripts/run_mutation_tests.py`
detects that state and skips cleanly instead of red-X'ing every commit. The
moment the first real function lands, that exemption disappears and mutation
testing becomes a real, enforced gate — this is intentional, not a
loophole to rely on.

## Running the checks locally

```bash
python3 -m venv .venv
.venv/bin/pip install -e ".[dev]"

.venv/bin/ruff check .
.venv/bin/ruff format --check .
.venv/bin/mypy
.venv/bin/pytest --cov --cov-report=term-missing
.venv/bin/python scripts/run_mutation_tests.py
```

All five must pass before opening a PR — CI runs the exact same commands.
