# import base64
import functions_framework
import json
# import jsonschema

from flask import jsonify # Request
# from google.cloud import bigquery
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


@functions_framework.http
def qualtrics_receiver(request):
    # Check if the request is JSON
    if request.is_json:
        payload = request.get_json()
        print(f"Received survey data:\n {json.dumps(payload, indent=2)}")
    else:
        return jsonify(
            {"error": "Invalid content type. Expected application/json."}
        ), 400

    return "OK, 200"

    # # Extract data from payload (example keys based on your survey)
    # respondent_id = payload.get("respondentId")
    # responses = payload.get("responses")

    # # Validate required fields
    # if not respondent_id or not responses:
    #     return jsonify({"error": "Missing required fields"}), 400

    # Example: Insert data into BigQuery (assuming you have the client set up)

    # client = bigquery.Client()
    # table_id = "your-project.your_dataset.your_table"

    # rows_to_insert = [{"respondent_id": respondent_id, "responses": responses}]

    # errors = client.insert_rows_json(table_id, rows_to_insert)
    # if errors:
    #     return jsonify({"error": errors}), 500

    # return jsonify({"status": "success"}), 200

# import json
# import logging
# from pathlib import Path

# import functions_framework
# from flask import jsonify, request

# from utils import common_utils

# # Set up logging
# logging.basicConfig(level=logging.INFO)
# logger = logging.getLogger(__name__)

# # Resolve the path to the configs directory relative to this script
# py_file = Path(__file__).resolve()  # current file path
# cwd = py_file.parent  # directory containing this file
# config_path = cwd / "configs"  # path to configs directory

# logger.info(f"Current working dir: {Path.cwd()}")
# logger.info(f"Resolved config path: {config_path}")

# # Load configuration using resolved path
# try:
#     config = common_utils.load_configs(config_path=str(config_path), use_box=True)
#     logger.info(f"Loaded config: {json.dumps(config, indent=4)}")
# except Exception as e:
#     logger.error(f"Failed to load configuration: {e}")
#     # Depending on the importance of config, you might choose to exit or continue with defaults.


# @functions_framework.http
# def qualtrics_receiver(request):
#     """
#     HTTP endpoint for receiving Qualtrics survey responses.
#     Expects a JSON payload.
#     """
#     try:
#         if not request.is_json:
#             logger.warning("Received non-JSON content")
#             return jsonify(
#                 {"error": "Invalid content type. Expected application/json."}
#             ), 400

#         payload = request.get_json()
#         logger.info(f"Received survey data: {json.dumps(payload, indent=2)}")

#         # TODO: Insert payload processing, validation, and further processing here.
#         # For example:
#         # respondent_id = payload.get("respondentId")
#         # responses = payload.get("responses")
#         # if not respondent_id or not responses:
#         #     return jsonify({"error": "Missing required fields"}), 400
#         # Insert into BigQuery or other storage as needed.

#         return jsonify({"status": "success"}), 200

#     except Exception as e:
#         logger.exception("Error processing request")
#         return jsonify({"error": "Internal Server Error", "message": str(e)}), 500
