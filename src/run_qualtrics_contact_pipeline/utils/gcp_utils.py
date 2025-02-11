import hashlib
import json
import logging

from google.cloud import secretmanager


def get_secret_payload(
    project_id: str,
    secret_id: str,
    version_id: str = "latest",
    hash_output: bool = False,  # argument to control hashing
) -> dict[str, str]:
    """Retrieves a secret payload from GCP Secret Manager and optionally returns its SHA-224 hash.

    Args:
        project_id (str): Google Cloud project ID hosting the secret.
        secret_id (str): Identifier of the secret in Secret Manager.
        version_id (str, optional): Specific secret version to access (default: "latest").
        hash_output (bool, optional): If True, returns a SHA-224 hash string of the payload instead of its parsed JSON.

    Raises:
        ValueError: If the secret cannot be accessed or its payload fails to parse properly.

    Returns:
        dict[str, str] or str: The secret's JSON payload as a dictionary, or its SHA-224 hash string if hash_output is True.
    """
    try:
        client = secretmanager.SecretManagerServiceClient()
        logging.info("Client created successfully.")

        # build the FULL secret version path
        name = client.secret_version_path(
            project=project_id,
            secret=secret_id,
            secret_version=version_id,
        )

        # access the secret version
        response = client.access_secret_version(request={"name": name})

        # decode payload to string (UTF-8)
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
