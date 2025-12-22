import logging
import os
import yaml
from box import Box
from pathlib import Path
from typing import overload, Literal


def deep_merge(base: dict, update: dict) -> dict:
    """Recursively merges two dictionaries, with values from 'update' taking precedence.

    Args:
        base (dict): The base dictionary to merge into.
        update (dict): The dictionary to merge from.

    Returns:
        dict: The merged dictionary.
    """
    for key, value in update.items():
        if key in base and isinstance(base[key], dict) and isinstance(value, dict):
            # Recursively merge nested dictionaries
            deep_merge(base[key], value)
        else:
            # Otherwise, update or add the key-value pair
            base[key] = value
    return base


def validate_config_structure(config: dict, filename: str) -> None:
    """Validates that the config file has the expected structure.

    Args:
        config (dict): The loaded configuration dictionary.
        filename (str): The name of the config file being validated.

    Raises:
        ValueError: If the config structure is invalid.
    """
    if not isinstance(config, dict):
        raise ValueError(
            f"Config file '{filename}' does not contain a valid dictionary."
        )

    if "params" not in config:
        raise ValueError(
            f"Config file '{filename}' is missing the top-level 'params' key."
        )

    if not isinstance(config["params"], dict):
        raise ValueError(
            f"Config file '{filename}' has 'params' but it's not a dictionary."
        )

    # Check that params contains at least one nested dictionary
    if not config["params"]:
        logging.warning(f"Config file '{filename}' has an empty 'params' section.")


def expand_env_vars(config: dict) -> dict:
    """Recursively expands environment variables in config values.

    Args:
        config (dict): The configuration dictionary.

    Returns:
        dict: The configuration with environment variables expanded.
    """
    for key, value in config.items():
        if isinstance(value, dict):
            config[key] = expand_env_vars(value)
        elif isinstance(value, str) and value.startswith("${") and value.endswith("}"):
            env_var = value[2:-1]
            env_value = os.getenv(env_var)
            if env_value is None:
                logging.warning(
                    f"Environment variable '{env_var}' not found. Keeping placeholder."
                )
            else:
                config[key] = env_value
    return config


@overload
def load_configs(
    config_path: str, use_box: Literal[True] = True, expand_vars: bool = True
) -> Box: ...


@overload
def load_configs(
    config_path: str, use_box: Literal[False], expand_vars: bool = True
) -> dict: ...


def load_configs(
    config_path: str, use_box: bool = True, expand_vars: bool = True
) -> dict | Box:
    """Loads and merges YAML configuration files from a directory.

    Scans the specified directory for files with '_config' or '.yaml' in their names,
    loads and merges their contents using deep merging, validates structure,
    and optionally expands environment variables and wraps in a Box object.

    Args:
        config_path (str): Path of the directory containing YAML configuration files.
        use_box (bool, optional): If True, returns the merged data wrapped in a Box object. Defaults to True.
        expand_vars (bool, optional): If True, expands environment variables in config values. Defaults to True.

    Returns:
        dict or Box: Merged configuration data as a dictionary or a Box instance.

    Raises:
        FileNotFoundError: If the directory does not exist or no matching config files are found.
        yaml.YAMLError: If any YAML file fails to parse.
        ValueError: If any config file has invalid structure.
    """
    # Check if the directory exists
    config_dir = Path(config_path)
    if not config_dir.exists() or not config_dir.is_dir():
        logging.error("Config directory not found: %s", config_path, exc_info=True)
        raise FileNotFoundError(f"Config directory '{config_path}' not found.")

    # Find all YAML files (you can adjust the pattern as needed)
    config_files = list(config_dir.glob("*.yaml")) + list(config_dir.glob("*.yml"))
    if not config_files:
        logging.error("No config files found in directory: %s", config_path)
        raise FileNotFoundError(f"No config files found in '{config_path}'.")

    # Sort files for consistent loading order
    config_files = sorted(config_files)

    # Initialize an empty dictionary to store merged configurations
    merged_config: dict = {}

    # Iterate over each config file and load its content
    for config_file in config_files:
        try:
            logging.info(f"Loading configuration file: {config_file.name}")
            with open(config_file, "r") as f:
                config: dict | None = yaml.safe_load(f)

            # Validate that file isn't empty
            if config is None:
                logging.warning(f"Config file '{config_file.name}' is empty. Skipping.")
                continue

            # Validate the structure
            validate_config_structure(config, config_file.name)

            # Deep merge the loaded configuration into the main dictionary
            merged_config = deep_merge(merged_config, config)

            logging.info(
                f"Successfully loaded and merged configuration from: {config_file.name}"
            )

        except yaml.YAMLError as e:
            logging.error(
                f"Failed to parse YAML file '{config_file.name}': {e}", exc_info=True
            )
            raise
        except ValueError as e:
            logging.error(
                f"Config validation failed for '{config_file.name}': {e}", exc_info=True
            )
            raise
        except Exception as e:
            logging.error(
                f"Unexpected error while loading config file '{config_file.name}': {e}",
                exc_info=True,
            )
            raise

    # Check if we have any valid configuration
    if not merged_config:
        raise ValueError("No valid configuration data was loaded from any file.")

    logging.info(f"Merged configuration keys: {list(merged_config.keys())}")

    # Optionally expand environment variables
    if expand_vars:
        logging.info("Expanding environment variables...")
        merged_config = expand_env_vars(merged_config)

    # Optionally wrap the result in a Box object
    if use_box:
        return Box(merged_config, default_box=True, default_box_attr=None)

    return merged_config
