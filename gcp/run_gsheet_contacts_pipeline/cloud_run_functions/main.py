import gspread
import functions_framework
import json

from flask import jsonify
from google.cloud import bigquery
from pathlib import Path

from utils import common_utils, gcp_utils, gspread_utils

# dynamically resolve the path to configs directory relative to this script
py_file = Path(__file__).resolve()  # path of this file (main.py)
cwd = py_file.parent  # dir containing this file
config_path = cwd / "configs"  # path to configs directory

# print(f"Current working dir: {Path.cwd()}")

# load configuration using resolved path
config = common_utils.load_configs(config_path=str(config_path), use_box=True)
print(f"Loaded config: {json.dumps(config, indent=2)}")


@functions_framework.http
def stream_raw_contact_directory(request):
    try:
        # authentication and Google Sheet setup
        credentials = gcp_utils.get_secret_payload(
            project_id=config.params.gcp.project_id,
            secret_id=config.params.secret_mgr.service_account_secret_id,
            version_id=config.params.secret_mgr.version_id,
        )
        gspread_client = gspread_utils.auth_gspread(credentials)

        if not isinstance(gspread_client, gspread.client.Client):
            return jsonify({"error": "Authentication failed"}), 401

        # get worksheet
        ws = gspread_utils.get_gsheet(
            client=gspread_client,
            use_method=config.params.gspread.use_method,
            spreadsheet_id=config.params.gspread.spreadsheet_id,
            sheet_name=config.params.gspread.sheet_name,
        )

        if not isinstance(ws, gspread.Worksheet):
            return jsonify({"error": "Failed to retrieve worksheet"}), 401

        # data extraction and validation
        data = ws.get_all_records()

        if not isinstance(data, list):
            return jsonify({"error": "Data is not a list of dictionaries"}), 500
        elif not all(isinstance(item, dict) for item in data):
            return jsonify({"error": "Not all items in list is dictionary"})
        else:
            jsonify({"status": "Data is valid"})

        # BigQuery setup
        bq_client = bigquery.Client()

        project_id = config.params.gcp.project_id
        dataset_id = config.params.bq.dataset_id
        table_id = config.params.bq.raw_table

        full_table_id = f"{project_id}.{dataset_id}.{table_id}"

        # atomic truncate-and-insert operation
        try:
            # 1. truncate table
            truncate_job = bq_client.query(f"TRUNCATE TABLE `{full_table_id}`")
            truncate_job.result()  # Wait for completion

            # 2. insert fresh data
            errors = bq_client.insert_rows_json(
                table=full_table_id, json_rows=data, row_ids=[None] * len(data)
            )
            if errors:
                print("Errors:", errors)
            else:
                print("Data streamed successfully.")

        except Exception as e:
            return jsonify({"error": "Transaction failed", "details": str(e)}), 500

        return jsonify(
            {
                "status": f"Successfully refreshed {len(data)} rows",
                "table": full_table_id,
            }
        ), 200

    except gspread.exceptions.APIError as e:
        return jsonify({"error": f"Sheets API error: {str(e)}"}), 502
    except Exception as e:
        return jsonify({"error": f"Unexpected error: {str(e)}"}), 500
