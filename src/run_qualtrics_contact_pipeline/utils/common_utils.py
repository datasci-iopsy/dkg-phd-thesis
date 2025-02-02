import logging
import yaml

from pathlib import Path


def load_config(file_path: str):
    """
    Load a single configuration file.

    Args:
        file_path (str): The path to the configuration file.

    Returns:
        dict: The loaded configuration as a dictionary.

    Raises:
        FileNotFoundError: If the specified file does not exist.
        yaml.YAMLError: If the YAML file cannot be parsed.
    """
    # check if the config file exists
    config_file = Path(file_path)

    if not config_file.exists():
        logging.error("Config file not found: %s", file_path, exc_info=True)
        raise FileNotFoundError(f"Config file '{file_path}' not found.")

    # attempt to load the yaml configuration
    try:
        logging.info(f"Loading configuration file: {config_file.name}")
        with open(config_file, "r") as f:
            config = yaml.safe_load(f)

        logging.info(f"Successfully loaded configuration from: {config_file.name}")
        logging.info(f"Configuration content: {config}")
        return config

    except yaml.YAMLError as e:
        logging.error(
            f"Failed to parse YAML file '{config_file.name}': {e}", exc_info=True
        )
        raise

    except Exception as e:
        logging.error(
            f"Unexpected error while loading config file '{config_file.name}': {e}",
            exc_info=True,
        )
        raise
