import json
import logging
import yaml

from box import Box
from pathlib import Path


def load_configs(dir_path: str, use_box: bool = True) -> dict | Box:
    """
    Load multiple configuration files from a directory. Optionally wrap the result in a Box object.
    Files must have '_config' in their names to be loaded.

    Args:
        dir_path (str): The path to the directory containing configuration files.
        use_box (bool): Whether to wrap the resulting configuration dictionary in a Box object.

    Returns:
        dict or Box: A merged dictionary (or Box object) containing configurations from all loaded files.

    Raises:
        FileNotFoundError: If the directory does not exist or no config files are found.
        yaml.YAMLError: If any YAML file cannot be parsed.
    """
    # Check if the directory exists
    config_dir = Path(dir_path)
    if not config_dir.exists() or not config_dir.is_dir():
        logging.error("Config directory not found: %s", dir_path, exc_info=True)
        raise FileNotFoundError(f"Config directory '{dir_path}' not found.")

    # Find all files with '_config' in their names
    config_files = list(config_dir.glob("*_config*.yaml"))
    if not config_files:
        logging.error("No config files found in directory: %s", dir_path)
        raise FileNotFoundError(f"No config files found in '{dir_path}'.")

    # Initialize an empty dictionary to store merged configurations
    merged_config = {}

    # Iterate over each config file and load its content
    for config_file in config_files:
        try:
            logging.info(f"Loading configuration file: {config_file.name}")
            with open(config_file, "r") as f:
                config = yaml.safe_load(f)

            # Merge the loaded configuration into the main dictionary
            if config:
                merged_config.update(config)

            logging.info(f"Successfully loaded configuration from: {config_file.name}")
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

    logging.info(f"Merged configuration content: {merged_config}")

    # optionally wrap the result in a Box object
    if use_box:
        return Box(merged_config, default_box=True)

    return merged_config


# TODO: reconfigure function to do write, read, etc.
def write_json_data(file_path: str, data: dict[str, any]) -> None:
    """Write JSON data to file with robust error handling.

    Args:
        file_path: Path to the target JSON file
        data: Dictionary data to serialize

    Raises:
        TypeError: If non-serializable data types are found
        OSError: For file system errors (permissions, path issues)
        RuntimeError: For unexpected errors during serialization
    """
    try:
        with open(file_path, "w") as f:
            json.dump(data, f, indent=4)
    except (TypeError, OverflowError) as e:
        raise TypeError(f"Serialization failure: {e}") from e
    except OSError as e:
        raise OSError(f"File operation failed: {e.strerror}") from e
    except Exception as e:
        raise RuntimeError(f"Unexpected error: {e}") from e


# ! ---------------------------------------------------------------------------
# # ! deprecated in lieu of multi config design and load function: `load_configs`
# # ! --------------------------------------------------------------------------
# def load_config(file_path: str):
#     """
#     Load a single configuration file.

#     Args:
#         file_path (str): The path to the configuration file.

#     Returns:
#         dict: The loaded configuration as a dictionary.

#     Raises:
#         FileNotFoundError: If the specified file does not exist.
#         yaml.YAMLError: If the YAML file cannot be parsed.
#     """
#     # check if the config file exists
#     config_file = Path(file_path)

#     if not config_file.exists():
#         logging.error("Config file not found: %s", file_path, exc_info=True)
#         raise FileNotFoundError(f"Config file '{file_path}' not found.")

#     # attempt to load the yaml configuration
#     try:
#         logging.info(f"Loading configuration file: {config_file.name}")
#         with open(config_file, "r") as f:
#             config = yaml.safe_load(f)

#         logging.info(f"Successfully loaded configuration from: {config_file.name}")
#         logging.info(f"Configuration content: {config}")
#         return config

#     except yaml.YAMLError as e:
#         logging.error(
#             f"Failed to parse YAML file '{config_file.name}': {e}", exc_info=True
#         )
#         raise

#     except Exception as e:
#         logging.error(
#             f"Unexpected error while loading config file '{config_file.name}': {e}",
#             exc_info=True,
#         )
#         raise
