#!/usr/bin/env python3
"""
CI-friendly wrapper around mutmut.

Several things mutmut's own CLI doesn't do out of the box, all handled here:

1. `mutmut run` needs at least one real function/class in the mutated paths
   to hook its internal self-check into. On a tree with no logic yet (pure
   stub/docstring files) it always exits 1 with no useful message. We detect
   that case up front and skip cleanly instead of red-X'ing every commit
   before there's anything to mutate.
2. `mutmut run` itself always exits 0 no matter how many mutants survived —
   the actual pass/fail signal is whether `mutmut results` prints anything.
   We treat any output there (survived mutants OR mutants with no covering
   test at all) as a CI failure.
3. On failure, `mutmut results` only names the survivors — it doesn't show
   what changed. We follow up with `mutmut show <id>` per survivor so the
   CI log has the actual diff, not just an ID to look up separately.
4. Mutating the whole tree on every run gets slow as real logic accumulates.
   mutmut only reads `paths_to_mutate` from pyproject.toml, with no CLI/env
   override, so we temporarily narrow that list to just the .py files that
   changed since the best available base ref (PR base, origin/main, or the
   previous commit) and restore the original file afterward. If no base ref
   resolves at all (e.g. a single-commit shallow clone), we fall back to
   mutating everything, same as before.
"""

from __future__ import annotations

import ast
import fnmatch
import os
import re
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


def _diff_base() -> str | None:
    base_ref = os.environ.get("GITHUB_BASE_REF")
    candidates = ([f"origin/{base_ref}"] if base_ref else []) + ["origin/main", "HEAD~1"]

    for candidate in candidates:
        merge_base = subprocess.run(
            ["git", "merge-base", "HEAD", candidate], check=False, capture_output=True, text=True
        )
        if merge_base.returncode == 0:
            return merge_base.stdout.strip()
    return None


def _changed_files(paths_to_mutate: list[str], do_not_mutate: list[str]) -> list[str] | None:
    """Changed .py files under paths_to_mutate since the best available base ref.

    Returns None (meaning "couldn't tell, mutate everything") if no base ref
    resolves at all.
    """
    base = _diff_base()
    if base is None:
        return None

    diff = subprocess.run(
        ["git", "diff", "--name-only", base], check=True, capture_output=True, text=True
    )
    changed = []
    for line in diff.stdout.splitlines():
        if not line.endswith(".py"):
            continue
        if any(fnmatch.fnmatch(line, p) for p in do_not_mutate):
            continue
        if any(fnmatch.fnmatch(line, f"{p.rstrip('/')}/*") for p in paths_to_mutate):
            changed.append(line)
    return changed


def _scope_pyproject_to(paths: list[str]) -> str:
    original = Path("pyproject.toml").read_text()
    scoped_list = ", ".join(f'"{path}"' for path in paths)
    scoped = re.sub(
        r"(?m)^paths_to_mutate\s*=\s*\[[^\]]*\]",
        f"paths_to_mutate = [{scoped_list}]",
        original,
    )
    Path("pyproject.toml").write_text(scoped)
    return original


def main() -> int:
    config = tomllib.loads(Path("pyproject.toml").read_text())["tool"]["mutmut"]
    paths_to_mutate = config.get("paths_to_mutate", [])
    do_not_mutate = config.get("do_not_mutate", [])

    if not _has_any_logic(paths_to_mutate, do_not_mutate):
        print("No functions in the mutated paths yet — skipping mutation testing.")
        return 0

    changed_files = _changed_files(paths_to_mutate, do_not_mutate)
    original_pyproject = None
    if changed_files is not None:
        if not changed_files:
            print("No changed .py files under the mutated paths — skipping mutation testing.")
            return 0
        print(f"Scoping mutation testing to {len(changed_files)} changed file(s):")
        for path in changed_files:
            print(f"  {path}")
        original_pyproject = _scope_pyproject_to(changed_files)

    try:
        subprocess.run([sys.executable, "-m", "mutmut", "run"], check=False)
        results = subprocess.run(
            [sys.executable, "-m", "mutmut", "results"],
            check=False,
            capture_output=True,
            text=True,
        )
    finally:
        if original_pyproject is not None:
            Path("pyproject.toml").write_text(original_pyproject)

    print(results.stdout, end="")

    if results.stdout.strip():
        for mutant_id in re.findall(r"^\s*(\S+): survived\s*$", results.stdout, re.MULTILINE):
            diff = subprocess.run(
                [sys.executable, "-m", "mutmut", "show", mutant_id],
                check=False,
                capture_output=True,
                text=True,
            )
            print(f"\n--- {mutant_id} ---\n{diff.stdout}")
        print(
            "Mutation testing found survived and/or untested mutants (see above).",
            file=sys.stderr,
        )
        return 1

    print("All mutants killed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
