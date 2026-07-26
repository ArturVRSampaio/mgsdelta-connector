import os
import sys
from pathlib import Path

os.environ.setdefault("SKIP_REQUIREMENTS_UPDATE", "1")

_archipelago_root = Path(__file__).parent / "Archipelago"
if str(_archipelago_root) not in sys.path:
    sys.path.insert(0, str(_archipelago_root))
