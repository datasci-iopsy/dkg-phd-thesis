"""
YAML configuration loader with Pydantic validation.

Loads all YAML files from a directory, merges them into a single
dict, and validates the result against the AppConfig schema.

Replaces the former common_utils.load_configs() + Box pattern.
"""

import logging
from pathlib import Path
from typing import Any

import yaml

from .config_models import AppConfig

logger = logging.getLogger(__name__)


def _deep_merge(base: dict, override: dict) -> dict:
    """Recursively merge *override* into *base*, preferring override values.

    Returns a new dict — neither input is mutated.
    """
    merged = base.copy()
    for key, value in override.items():
        if (
            key in merged
            and isinstance(merged[key], dict)
            and isinstance(value, dict)
        ):
            merged[key] = _deep_merge(merged[key], value)
        else:
            merged[key] = value
    return merged


def _load_yaml_files(config_dir: Path) -> dict[str, Any]:
    """Load and merge all YAML files from *config_dir*.

    Files are sorted alphabetically so merge order is deterministic
    (later files override earlier ones on key collisions).

    Raises:
        FileNotFoundError: If no .yaml/.yml files exist in the directory.
        TypeError: If a file contains something other than a YAML mapping.
        yaml.YAMLError: If a file is malformed YAML.
    """
    files = sorted([*config_dir.glob("*.yaml"), *config_dir.glob("*.yml")])
    if not files:
        raise FileNotFoundError(f"No YAML config files found in '{config_dir}'")

    merged: dict[str, Any] = {}
    for path in files:
        logger.info("Loading config: %s", path.name)
        raw = yaml.safe_load(path.read_text())

        if raw is None:
            logger.warning("Skipping empty config file: %s", path.name)
            continue
        if not isinstance(raw, dict):
            raise TypeError(
                f"Config file '{path.name}' must be a YAML mapping, "
                f"got {type(raw).__name__}"
            )

        merged = _deep_merge(merged, raw)

    if not merged:
        raise ValueError(f"All config files in '{config_dir}' were empty.")

    return merged


def load_config(config_dir: str | Path) -> AppConfig:
    """Load, merge, and validate configuration from YAML files.

    Args:
        config_dir: Path to the directory containing YAML config files.

    Returns:
        Validated AppConfig instance with dot-notation access.

    Raises:
        FileNotFoundError: If the directory doesn't exist or has no YAML files.
        pydantic.ValidationError: If the merged config doesn't match the schema.
            The error message will list every missing or invalid field.
    """
    config_path = Path(config_dir)
    if not config_path.is_dir():
        raise FileNotFoundError(f"Config directory not found: '{config_dir}'")

    raw = _load_yaml_files(config_path)
    return AppConfig.model_validate(raw)
