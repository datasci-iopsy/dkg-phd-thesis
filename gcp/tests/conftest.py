"""
Pytest path configuration.

Adds directories to sys.path so that imports resolve the same way
they do at runtime:

  - gcp/                      -> 'shared.utils...' imports
  - gcp/cloud_run_functions/
    run_qualtrics_scheduling/  -> 'models...' and 'utils...' imports

When functions-framework runs, it adds the function directory to
sys.path automatically. We replicate that here for pytest.
"""

import sys
from pathlib import Path

_tests_dir = Path(__file__).resolve().parent

# gcp/ is one level up from gcp/tests/
_gcp_dir = str(_tests_dir.parent)
if _gcp_dir not in sys.path:
    sys.path.insert(0, _gcp_dir)

# Function directories -- mirrors what functions-framework does at runtime.
# Add additional function directories here as new functions are created.
_fn_qualtrics_dir = str(
    _tests_dir.parent / "cloud_run_functions" / "run_qualtrics_scheduling"
)
if _fn_qualtrics_dir not in sys.path:
    sys.path.insert(0, _fn_qualtrics_dir)

_fn_confirmation_dir = str(
    _tests_dir.parent / "cloud_run_functions" / "run_intake_confirmation"
)
if _fn_confirmation_dir not in sys.path:
    sys.path.insert(0, _fn_confirmation_dir)

_fn_followup_dir = str(
    _tests_dir.parent / "cloud_run_functions" / "run_followup_scheduling"
)
if _fn_followup_dir not in sys.path:
    sys.path.insert(0, _fn_followup_dir)
