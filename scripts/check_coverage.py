#!/usr/bin/env python3
"""
Deterministic replacement for pytest-cov's --cov-fail-under.

pytest-cov's own fail-under check is flaky when the measured code has zero
statements: the exact same all-stub tree has been observed to report both
"100%" and "0%" across otherwise-identical runs (nedbat/coveragepy#1470,
pytest-dev/pytest-cov#641). We sidestep that by reading coverage's own JSON
totals directly and doing the percentage/threshold math ourselves.

Run after `pytest --cov` has produced a `.coverage` data file.
"""

from __future__ import annotations

import json
import subprocess
import sys

REQUIRED_PERCENT = 100.0


def main() -> int:
    subprocess.run(
        [sys.executable, "-m", "coverage", "json", "-o", "coverage.json", "-q"],
        check=True,
    )
    with open("coverage.json") as f:
        totals = json.load(f)["totals"]

    num_statements = totals["num_statements"]
    percent_covered = totals["percent_covered"]

    if num_statements == 0:
        print("No statements measured yet — nothing to enforce coverage on.")
        return 0

    if percent_covered < REQUIRED_PERCENT:
        print(f"Coverage {percent_covered:.2f}% is below the required {REQUIRED_PERCENT:.0f}%.")
        return 1

    print(f"Coverage: {percent_covered:.2f}% (required {REQUIRED_PERCENT:.0f}%).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
