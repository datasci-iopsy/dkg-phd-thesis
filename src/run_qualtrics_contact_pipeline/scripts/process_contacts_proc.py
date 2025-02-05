import gspread

from box import Box
from utils import common_utils, gcp_utils, gspread_utils


# * authenticate gspread client
def auth_gspread_via_secret_manager(config: Box):
    project_id = config.params.gcp.project_id
    secret_id = config.params.gspread.secret_id
    version_id = config.params.gcp.version_id

    # fetch credentials from GCP Secret Manager
    credentials = gcp_utils.get_secret_payload(
        project_id=project_id,
        secret_id=secret_id,
        version_id=version_id,
        hash_output=False,
    )

    return gspread_utils.auth_gspread(credentials=credentials)


# * retrieve raw and clean sheets
def get_raw_and_clean_sheets(client: gspread.Client, config: Box):
    use_method = config.params.gspread.use_method
    spreadsheet_id = config.params.gspread.spreadsheet_id
    raw_sheet_name = config.params.gspread.raw_contacts_sheet_name
    clean_sheet_name = config.params.gspread.clean_contacts_sheet_name

    # Retrieve sheets
    raw_sheet = gspread_utils.get_gsheet(
        client=client,
        use_method=use_method,
        spreadsheet_id=spreadsheet_id,
        sheet_name=raw_sheet_name,
    )
    clean_sheet = gspread_utils.get_gsheet(
        client=client,
        use_method=use_method,
        spreadsheet_id=spreadsheet_id,
        sheet_name=clean_sheet_name,
    )
    return raw_sheet, clean_sheet


def get_processed_contacts(clean_sheet: list[dict], id_column: str):
    clean_sheet_data = clean_sheet.get_all_records()

    # Check if there are any rows and if the header exists
    if not clean_sheet_data:
        return set()  # Return an empty set if the sheet is empty

    if id_column not in clean_sheet_data[0]:
        raise ValueError(f"Column '{id_column}' not found in the sheet headers.")

    # Extract values under the specified header, skipping any empty rows
    processed_contacts = {row[id_column] for row in clean_sheet_data if row[id_column]}

    return set(processed_contacts)


def main():
    dir_path = "configs"
    config = common_utils.load_configs(dir_path=dir_path, use_box=True)
    # print(config)

    # * authenticate gspread client for sheets
    client = auth_gspread_via_secret_manager(config=config)
    # print(client)
    # print(type(client))

    raw_sheet, clean_sheet = get_raw_and_clean_sheets(client=client, config=config)
    print(raw_sheet.get_all_records())
    print(clean_sheet.get_all_records())

    processed_contacts = get_processed_contacts(
        clean_sheet=clean_sheet,
        id_column="RESPONSE_ID",
    )
    # print(type(processed_contacts))
    # print(processed_contacts)

    # # def process_new_records(raw_sheet, clean_sheet):
    # #     # Retrieve all raw data as a list of dictionaries
    # #     raw_data = raw_sheet.get_all_records()

    # #     # Get processed participant IDs from the clean sheet
    # #     processed_ids = get_processed_ids(clean_sheet)

    # #     # Identify new records
    # #     new_records = [
    # #         record
    # #         for record in raw_data
    # #         if str(record["participant_id"]) not in processed_ids
    # #     ]

    # #     # Process each new record
    # #     for record in new_records:
    # #         cleaned_record = clean_and_transform(record)
    # #         append_to_clean_sheet(clean_sheet, cleaned_record)

    # # def clean_and_transform(record):
    # #     """
    # #     Apply your cleaning logic here.
    # #     For example, you might reformat dates, standardize phone numbers, etc.
    # #     Return a list or dict that represents the cleaned row.
    # #     """
    # #     # Example transformation (customize as needed):
    # #     participant_id = record["participant_id"]
    # #     date = record["date"]  # Perhaps transform this date into a standardized format
    # #     phone = record["phone_number"]  # Clean or format the phone number

    # #     # Return as a list in the order of columns in the clean sheet
    # #     return [participant_id, date, phone]

    # # def append_to_clean_sheet(clean_sheet, cleaned_record):
    # #     # Append the cleaned record as a new row at the end of the clean sheet
    # #     clean_sheet.append_row(cleaned_record)


if __name__ == "__main__":
    main()

    # # Process only the new records
    # process_new_records(raw_sheet, clean_sheet)
