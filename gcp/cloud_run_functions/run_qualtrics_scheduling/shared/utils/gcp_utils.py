"""
BigQuery data operations for survey response storage.
"""

# import hashlib
import json
import logging
from datetime import datetime
from typing import Any, Dict

from box import Box
from google.cloud import bigquery  # secretmanager
from google.cloud.exceptions import GoogleCloudError

logger = logging.getLogger(__name__)


def get_bigquery_client(config: Box) -> bigquery.Client:
    """
    Initializes BigQuery client.

    Args:
        config: Configuration Box with GCP project ID

    Returns:
        bigquery.Client: Authenticated BigQuery client
    """
    project_id = config.params.gcp.project_id
    return bigquery.Client(project=project_id)


def insert_raw_response(
    response_data: Dict[str, Any], survey_id: str, response_id: str, config: Box
) -> bool:
    """
    Inserts raw survey response into BigQuery using streaming API.

    Stores the complete Qualtrics response as JSON for audit trail
    and potential reprocessing.

    Args:
        response_data: Complete response data from Qualtrics
        survey_id: Survey identifier
        response_id: Response identifier
        config: Configuration Box

    Returns:
        bool: True if insert successful
    """
    try:
        client = get_bigquery_client(config)

        dataset_id = config.params.bq.dataset_id
        table_id = config.params.bq.raw_table
        full_table_id = f"{config.params.gcp.project_id}.{dataset_id}.{table_id}"

        # Prepare row for insertion
        row = {
            "response_id": response_id,
            "survey_id": survey_id,
            "recorded_date": datetime.utcnow().isoformat(),
            "response_data": json.dumps(response_data),
            "processed": False,
            "created_at": datetime.utcnow().isoformat(),
        }

        # Stream insert to BigQuery
        table = client.get_table(full_table_id)
        errors = client.insert_rows_json(table, [row])

        if errors:
            logger.error(f"BigQuery insert errors: {errors}")
            return False

        logger.info(
            f"Successfully inserted response {response_id} into {full_table_id}"
        )
        return True

    except GoogleCloudError as e:
        logger.error(f"BigQuery error: {str(e)}", exc_info=True)
        return False

    except Exception as e:
        logger.error(f"Unexpected error writing to BigQuery: {str(e)}", exc_info=True)
        return False


# def insert_followup_response(
#     response_data: Dict[str, Any],
#     survey_id: str,
#     response_id: str,
#     timepoint: int,
#     config: Box,
# ) -> bool:
#     """
#     Inserts follow-up survey response with timepoint metadata.

#     Args:
#         response_data: Response data from Qualtrics
#         survey_id: Survey identifier
#         response_id: Response identifier
#         timepoint: Survey timepoint (1, 2, or 3)
#         config: Configuration Box

#     Returns:
#         bool: True if insert successful
#     """
#     try:
#         client = get_bigquery_client(config)

#         dataset_id = config.params.bq.dataset_id
#         table_id = config.params.bq.followup_table
#         full_table_id = f"{config.params.gcp.project_id}.{dataset_id}.{table_id}"

#         row = {
#             "response_id": response_id,
#             "survey_id": survey_id,
#             "timepoint": timepoint,
#             "recorded_date": datetime.utcnow().isoformat(),
#             "response_data": json.dumps(response_data),
#             "created_at": datetime.utcnow().isoformat(),
#         }

#         table = client.get_table(full_table_id)
#         errors = client.insert_rows_json(table, [row])

#         if errors:
#             logger.error(f"BigQuery followup insert errors: {errors}")
#             return False

#         logger.info(f"Inserted followup response {response_id} (timepoint {timepoint})")
#         return True

#     except Exception as e:
#         logger.error(f"Failed to insert followup response: {str(e)}", exc_info=True)
#         return False

# # * Keep Your get_secret_payload() Function For:
# # Development/Testing: When running locally without Cloud Run environment
# # Batch Jobs on Compute Engine/VMs: Where environment variable mounting isn't as seamless
# # Admin Scripts: One-off scripts that need temporary secret access
# # Secret Rotation Automation: Scripts that programmatically update secrets
# # **
# def get_secret_payload(
#     project_id: str,
#     secret_id: str,
#     version_id: str = "latest",
#     hash_output: bool = False,  # argument to control hashing
# ) -> dict[str, str]:
#     """Retrieves a secret payload from GCP Secret Manager and optionally returns its SHA-224 hash.

#     Args:
#         project_id (str): Google Cloud project ID hosting the secret.
#         secret_id (str): Identifier of the secret in Secret Manager.
#         version_id (str, optional): Specific secret version to access (default: "latest").
#         hash_output (bool, optional): If True, returns a SHA-224 hash string of the payload instead of its parsed JSON.

#     Raises:
#         ValueError: If the secret cannot be accessed or its payload fails to parse properly.

#     Returns:
#         dict[str, str] or str: The secret's JSON payload as a dictionary, or its SHA-224 hash string if hash_output is True.
#     """
#     try:
#         client = secretmanager.SecretManagerServiceClient()
#         logging.info("Client created successfully.")

#         # build the FULL secret version path
#         name = client.secret_version_path(
#             project=project_id,
#             secret=secret_id,
#             secret_version=version_id,
#         )

#         # access the secret version
#         response = client.access_secret_version(request={"name": name})

#         # decode payload to string (UTF-8)
#         secret_payload = response.payload.data.decode("UTF-8")
#         secret_json = json.loads(secret_payload)

#         if hash_output:
#             # hash the response and return it
#             hashed_response = hashlib.sha224(secret_payload.encode("utf-8")).hexdigest()
#             logging.info(f"Hashed response: {hashed_response}")
#             return hashed_response

#         # otherwise, return the plain payload
#         logging.info("Secret payload retrieved successfully.")
#         return secret_json

#     except json.JSONDecodeError as e:
#         logging.error(f"Invalid JSON in secret payload: {e}", exc_info=True)
#         raise

#     except Exception as e:
#         logging.error(f"Secret retrieval failed: {e}", exc_info=True)
#         raise ValueError(f"Could not access secret '{secret_id}': {e}")
