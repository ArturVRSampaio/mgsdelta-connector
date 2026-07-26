#!/usr/bin/env python3
"""
CI-friendly wrapper around mutmut.

Two things mutmut's own CLI doesn't do out of the box, both handled here:

1. `mutmut run` needs at least one real function/class in the mutated paths
   to hook its internal self-check into. On a tree with no logic yet (pure
   stub/docstring files) it always exits 1 with no useful message. We detect
   that case up front and skip cleanly instead of red-X'ing every commit
   before there's anything to mutate.
2. `mutmut run` itself always exits 0 no matter how many mutants survived —
   the actual pass/fail signal is whether `mutmut results` prints anything.
   We treat any output there (survived mutants OR mutants with no covering
   test at all) as a CI failure.
"""

from __future__ import annotations

import ast
import fnmatch
import subprocess
import sys
import tomllib
from pathlib import Path


def _has_any_logic(paths_to_mutate: list[str], do_not_mutate: list[str]) -> bool:
    for pattern in paths_to_mutate:
        for path in Path().glob(f"{pattern.rstrip('/')}/**/*.py"):
            posix = path.as_posix()
            if any(fnmatch.fnmatch(posix, p) for p in do_not_mutate):
                continue
            tree = ast.parse(path.read_text())
            if any(isinstance(n, ast.FunctionDef | ast.AsyncFunctionDef) for n in ast.walk(tree)):
                return True
    return False


def main() -> int:
    config = tomllib.loads(Path("pyproject.toml").read_text())["tool"]["mutmut"]
    paths_to_mutate = config.get("paths_to_mutate", [])
    do_not_mutate = config.get("do_not_mutate", [])

    if not _has_any_logic(paths_to_mutate, do_not_mutate):
        print("No functions in the mutated paths yet — skipping mutation testing.")
        return 0

    subprocess.run([sys.executable, "-m", "mutmut", "run"], check=False)
    results = subprocess.run(
        [sys.executable, "-m", "mutmut", "results"], check=False, capture_output=True, text=True
    )
    print(results.stdout, end="")

    if results.stdout.strip():
        print(
            "Mutation testing found survived and/or untested mutants (see above).",
            file=sys.stderr,
        )
        return 1

    print("All mutants killed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
