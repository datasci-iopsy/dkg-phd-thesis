"""
Quick sanity check -- run directly to see loaded config output.

Usage from project root:
    poetry run python gcp/tests/run_config.py
Usage from gcp/tests/:
    poetry run python run_config.py
"""

import sys
from pathlib import Path

# Same path setup that conftest.py does for pytest
gcp_dir = str(Path(__file__).resolve().parent.parent)
if gcp_dir not in sys.path:
    sys.path.insert(0, gcp_dir)

from shared.utils.config_loader import load_config  # noqa: E402

configs_dir = (
    Path(__file__).resolve().parent.parent
    / "cloud_run_functions"
    / "run_qualtrics_scheduling"
    / "configs"
)

config = load_config(configs_dir)
print(config.model_dump_json(indent=2))
