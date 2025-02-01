import gspread
import logging
import json

from utils import gcp_utils
# TODO: figure out how to use shared.utils module; use setuptools possibly
# TODO: set up params file in config dir for variable substitution

# configure logging
logging.basicConfig(level=logging.INFO)

# * get gcp secret for gsheets service account
# TODO: (v2) use ADC to authentic function; could be triggered by cloud function if row is created in sheet
project_id = "dkg-phd-thesis"  # ! use as param
secret_id = "dkg-gsheets-sa-key"  # ! use as param
version_id = "latest"  # ! use as param
credentials = gcp_utils.get_secret_payload(
    project_id=project_id,
    secret_id=secret_id,
    version_id=version_id,
    hash_output=False,  # * must be type dict for downstream
)
# print(type(credentials))
# print(credentials)

# * access gsheets data
# TODO: create function to handle gsheet work outside of main script and call it
gc = gspread.service_account_from_dict(credentials)

spreadsheet_id = "1Afv09f_ne06Ji67c044CWDoZU9AM55VAu3KQcTZsGAk"  # ! use as param
spreadsheet_name = "raw_distrib_ls"  # ! use as param
sheet = gc.open_by_key(spreadsheet_id).worksheet(spreadsheet_name)

# fetch all data from the sheet
data = sheet.get_all_records()
print(json.dumps(data, indent=4))

# * process raw distribution file
# TODO: create function to handle processing work outside of main script and call it
# TODO: function should move data to new spreadsheet as well with updated fields; thus expand
# loop through rows and process unprocessed data
for row_idx, row in enumerate(data, start=2):  # start at 2 because row 1 is headers
    if row["Processed"] == "FALSE":  # check if the row is unprocessed
        unique_id = row["ProlificPIDEntry"]
        relevant_data = row["LocalTZ"]

        # run your data analysis or processing logic here
        logging.info(f"Processing ID: {unique_id}, Data: {relevant_data}")

        # Update the "Processed" flag in the sheet
        sheet.update_cell(
            row_idx, len(row), "TRUE"
        )  # assuming "Processed" is the last column

logging.info("Processing complete!")
