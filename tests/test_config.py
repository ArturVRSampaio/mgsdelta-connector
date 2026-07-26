from mgsdelta_connector.config import OFFSETS


def test_offsets_starts_empty_pending_recon() -> None:
    assert OFFSETS == {}
