"""Pytest path configuration for scripts/qualtrics tests.

Adds scripts/qualtrics/ to sys.path so absolute imports in client.py,
reporter.py, and inspect_surveys.py resolve without package installation.
"""

import sys
from pathlib import Path

_qualtrics_dir = str(Path(__file__).resolve().parent.parent)
if _qualtrics_dir not in sys.path:
    sys.path.insert(0, _qualtrics_dir)
