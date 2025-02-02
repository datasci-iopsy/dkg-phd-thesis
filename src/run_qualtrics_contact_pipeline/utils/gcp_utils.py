import hashlib
import json
import logging

from google.cloud import secretmanager


def get_secret_payload(
    project_id: str,
    secret_id: str,
    version_id: str = "latest",
    hash_output: bool = False,  # argument to control hashing
) -> str:
    """_summary_

    Args:
        project_id (str): _description_
        secret_id (str): _description_
        version_id (str, optional): _description_. Defaults to "latest".
        hash_output (bool, optional): _description_. Defaults to False.

    Raises:
        ValueError: _description_

    Returns:
        str: _description_
    """
    try:
        client = secretmanager.SecretManagerServiceClient()

        # Build the FULL secret version path
        name = client.secret_version_path(project_id, secret_id, version_id)

        # Access the secret version
        response = client.access_secret_version(request={"name": name})

        # Decode payload to string (UTF-8)
        secret_payload = response.payload.data.decode("UTF-8")
        secret_json = json.loads(secret_payload)

        if hash_output:
            # hash the response and return it
            hashed_response = hashlib.sha224(secret_payload.encode("utf-8")).hexdigest()
            logging.info(f"Hashed response: {hashed_response}")
            return hashed_response

        # otherwise, return the plain payload
        logging.info("Secret payload retrieved successfully.")
        return secret_json

    except json.JSONDecodeError as e:
        logging.error(f"Invalid JSON in secret payload: {e}", exc_info=True)
        raise

    except Exception as e:
        logging.error(f"Secret retrieval failed: {e}", exc_info=True)
        raise ValueError(f"Could not access secret '{secret_id}': {e}")
