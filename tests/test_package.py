"""Smoke test proving the test/coverage/CI harness actually runs end to end."""

import mgsdelta_connector


def test_package_is_importable() -> None:
    assert mgsdelta_connector is not None
