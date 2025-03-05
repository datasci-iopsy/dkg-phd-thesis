import base64
import json

# import jsonschema
import functions_framework

from cloudevents.http import CloudEvent
from pathlib import Path
from utils import common_utils

# dynamically resolve the path to configs directory relative to this script
py_file = Path(__file__).resolve()  # path of this file (main.py)
cwd = py_file.parent  # dir containing this file
config_path = cwd / "configs"  # path to configs directory

print(f"Current working dir: {Path.cwd()}")
print(f"Resolved config path: {config_path}")

# Load configuration using resolved path
config = common_utils.load_configs(config_path=str(config_path), use_box=True)
print(f"Loaded config: {json.dumps(config, indent=4)}")


# Triggered from a message on a Cloud Pub/Sub topic.
@functions_framework.cloud_event
def subscribe(cloud_event: CloudEvent) -> None:
    pubsub_data = cloud_event.data["message"]["data"]
    decoded_data = base64.b64decode(pubsub_data).decode("utf-8")

    # Parse Qualtrics payload
    survey_response = json.loads(decoded_data)
    print(f"Received survey data: {json.dumps(survey_response, indent=2)}")
    # # Print out the data from Pub/Sub, to prove that it worked
    # print(
    #     "Hello, " + base64.b64decode(cloud_event.data["message"]["data"]).decode() + "!"
    # )


# ** try later
# def validate_payload(request: Request) -> dict:
#     """Authenticate and validate incoming payload"""
#     # Verify API token from header
#     api_token = request.headers.get("X-API-TOKEN")

#     valid_token = gcp_utils.get_secret_payload(
#         secret_id=config.params.project_id,
#         version_id=config.params.version_id,
#         hash_output=False,
#     )

#     if api_token != valid_token:
#         raise ValueError("Invalid API token")

#     # JSON schema validation
#     payload = request.get_json()
#     # jsonschema.validate(instance=payload, schema=SCHEMA)

#     return payload


# def process_survey(request: Request):
#     """Cloud Function entry point"""
#     try:
#         payload = validate_payload(request)
#         df = pd.json_normalize(payload)

#         # Temporal processing
#         time_fields = ["start_date", "end_date"]
#         df[time_fields] = df[time_fields].apply(pd.to_datetime, format="ISO8601")

#         # Data quality checks
#         df["age"] = pd.to_numeric(df["demographics.age"], errors="coerce")
#         df["gender"] = df["demographics.gender"].str.upper()

#         # Load into BigQuery
#         client = bigquery.Client()
#         table_ref = client.dataset("survey_data").table("responses")

#         job_config = bigquery.LoadJobConfig(
#             schema=[
#                 bigquery.SchemaField("survey_id", "STRING", mode="REQUIRED"),
#                 bigquery.SchemaField("response_id", "STRING", mode="REQUIRED"),
#                 bigquery.SchemaField("start_date", "TIMESTAMP"),
#                 bigquery.SchemaField("end_date", "TIMESTAMP"),
#                 bigquery.SchemaField("age", "INTEGER"),
#                 bigquery.SchemaField("gender", "STRING"),
#             ],
#             time_partitioning=bigquery.TimePartitioning(
#                 field="start_date", type_=bigquery.TimePartitioningType.DAY
#             ),
#             write_disposition="WRITE_APPEND",
#         )

#         job = client.load_table_from_dataframe(df, table_ref, job_config=job_config)
#         job.result()

#         return jsonify({"status": "success"}), 200

#     except Exception as e:
#         return jsonify({"error": str(e)}), 500


# @functions_framework.http
# def process_qualtrics_contact(request):
#     """
#     Receives an HTTP POST request, decodes either a direct JSON payload or a Pub/Sub message,
#     and processes the JSON data.
#     """
#     if request.method != "POST":
#         return "Method not allowed", 405

#     try:
#         envelope = request.get_json()

#         # Define the required keys for validation
#         required_keys = config.params.pubsub.required_keys

#         # Handle direct JSON payload (for testing purposes)
#         if envelope and all(key in envelope for key in required_keys):
#             payload = envelope

#         # Handle Pub/Sub message structure
#         elif envelope and "message" in envelope and "data" in envelope["message"]:
#             pubsub_message = envelope["message"]
#             data = base64.b64decode(pubsub_message["data"]).decode("utf-8")
#             payload = json.loads(data)

#             # Validate that all required keys are present in the decoded payload
#             if not all(key in payload for key in required_keys):
#                 return (
#                     f"Bad Request: Missing one or more required fields: {required_keys}",
#                     400,
#                 )

#         else:
#             return (
#                 f"Bad Request: Invalid message format or missing required fields: {required_keys}",
#                 400,
#             )

#         # Process the JSON payload here. Example:
#         print(f"Received payload: {payload}")

#         # Add any additional processing logic here.
#         return "OK", 200

#     except json.JSONDecodeError:
#         return "Bad Request: Invalid JSON payload", 400
#     except Exception as e:
#         print(f"Error: {e}")
#         return f"Internal Server Error: {e}", 500
