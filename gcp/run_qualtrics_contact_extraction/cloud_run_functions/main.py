import functions_framework
import json

from flask import jsonify
from google.cloud import bigquery
from pathlib import Path

from utils import common_utils

# dynamically resolve the path to configs directory relative to this script
py_file = Path(__file__).resolve()  # path of this file (main.py)
cwd = py_file.parent  # dir containing this file
config_path = cwd / "configs"  # path to configs directory

print(f"Current working dir: {Path.cwd()}")
print(f"Resolved config path: {config_path}")

# load configuration using resolved path
config = common_utils.load_configs(config_path=str(config_path), use_box=True)
print(f"Loaded config: {json.dumps(config, indent=4)}")

# define required fields from config
REQUIRED_FIELDS = config.params.bq.raw_table_fields
# REQUIRED_FIELDS = config.get("params", {}).get("bq", {}).get("raw_table_fields", [])


@functions_framework.http
def qualtrics_receiver(request):
    # check if the request is JSON
    if not request.is_json:
        return jsonify(
            {"error": "Invalid content type. Expected application/json."}
        ), 400

    # attempt to parse JSON payload
    try:
        payload = request.get_json()
        print(f"Received survey data:\n {json.dumps(payload, indent=2)}")
    except Exception as e:
        return jsonify({"error": f"Invalid JSON payload: {str(e)}"}), 400

    # validate required keys in payload
    missing_keys = [key for key in REQUIRED_FIELDS if key not in payload]
    if missing_keys:
        return jsonify({"error": f"Missing required fields: {missing_keys}"}), 400

    # extract BigQuery config parameters safely with error handling
    try:
        project_id = config.params.gcp.project_id
        dataset_id = config.params.bq.dataset_id
        table_id = config.params.bq.raw_table
    except (AttributeError, KeyError) as e:
        return jsonify({"error": f"Configuration error: {str(e)}"}), 500

    # insert data into BigQuery with error handling
    client = bigquery.Client()
    rows_to_insert = [payload]

    try:
        errors = client.insert_rows_json(
            f"{project_id}.{dataset_id}.{table_id}", rows_to_insert
        )
        if errors:
            return jsonify({"error": errors}), 500
    except Exception as e:
        return jsonify({"error": f"BigQuery insertion failed: {str(e)}"}), 500

    return jsonify({"status": "success"}), 200
