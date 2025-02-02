# import gspread
# import logging
# import json

from utils import common_utils, gcp_utils, gsheets_utils
# TODO: figure out how to use shared.utils module; use setuptools possibly

# * load config file
file_path = "configs/run_qualtrics_contact_pipeline_config.yaml"
config = common_utils.load_config(file_path=file_path)
# print(config)

# * get gcp secret to authenticate gsheets service account
# TODO: (v2) use ADC to authentic function; could be triggered by cloud function if row is created in sheet
project_id = config.get("params").get("gcp").get("project_id")
secret_id = config.get("params").get("gcp").get("secret_id")
version_id = config.get("params").get("gcp").get("version_id")
# print(project_id)
# print(secret_id)
# print(version_id)

credentials = gcp_utils.get_secret_payload(
    project_id=project_id,
    secret_id=secret_id,
    version_id=version_id,
    hash_output=False,  # ! must be type dict for downstream; True is type: str
)
# print(type(credentials))
# print(credentials)

# * extract gsheets data
use_method = config.get("params").get("gspread").get("use_method")
spreadsheet_id = config.get("params").get("gspread").get("spreadsheet_id")
sheet_name = config.get("params").get("gspread").get("sheet_name")
# print(use_method)
# print(spreadsheet_id)
# print(sheet_name)

inbound_sheet = gsheets_utils.get_gsheet(
    credentials=credentials,
    use_method=use_method,
    spreadsheet_id=spreadsheet_id,
    sheet_name=sheet_name,
)
# print(type(inbound_sheet))

inbound_data = gsheets_utils.get_gsheet_records(sheet=inbound_sheet)
print(type(inbound_data))
print(inbound_data)

# * process raw distribution file
