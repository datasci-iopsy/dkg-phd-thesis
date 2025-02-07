import gspread
from box import Box

from datetime import datetime
from utils import common_utils, gcp_utils, gspread_utils


# * Authenticate gspread client
def auth_gspread_via_secret_manager(config: Box):
    """_summary_

    Args:
        config (Box): _description_

    Returns:
        _type_: _description_
    """
    project_id = config.params.gcp.project_id
    secret_id = config.params.gspread.secret_id
    version_id = config.params.gcp.version_id

    credentials = gcp_utils.get_secret_payload(
        project_id=project_id,
        secret_id=secret_id,
        version_id=version_id,
        hash_output=False,
    )

    return gspread_utils.auth_gspread(credentials=credentials)


# * retrieve raw and clean sheets
def get_raw_and_clean_sheets(client: gspread.Client, config: Box):
    """_summary_

    Args:
        client (gspread.Client): _description_
        config (Box): _description_

    Returns:
        _type_: _description_
    """
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


def get_processed_contacts(clean_sheet: gspread.Worksheet, clean_id_col: str):
    """_summary_

    Args:
        clean_sheet (gspread.Worksheet): _description_
        clean_id_col (str): _description_

    Raises:
        ValueError: _description_

    Returns:
        _type_: _description_
    """
    clean_sheet_data = clean_sheet.get_all_records()
    if not clean_sheet_data:
        return set()

    if clean_id_col not in clean_sheet_data[0]:
        raise ValueError(
            f"Column '{clean_id_col}' not found in the clean sheet headers."
        )

    return {row[clean_id_col] for row in clean_sheet_data if row[clean_id_col]}


def clean_and_transform(record: str, config: Box):
    """
    Cleans and transforms a raw record using configurations.

    - Dynamically renames columns based on config
    - Converts boolean-like values to True/False if column matches boolean_key
    - Formats phone numbers to ensure they are treated as text
    - Converts date from MM/DD/YYYY to YYYY-MM-DD
    - Ensures "PROCESSED" is always marked as True

    Works with different config structures by handling missing keys gracefully.
    """

    def convert_bool(value: str, true_value: str = "Yes"):
        """Convert a string to a boolean based on expected true_value (default 'Yes')."""
        return str(value).strip().lower() == str(true_value).strip().lower()

    def format_phone(phone_num: str, country_code: str = "+1"):
        """Format phone numbers to ensure they are stored as text with a country code."""
        if phone_num and isinstance(phone_num, str):
            return f"{country_code}{phone_num.strip()}"
        return phone_num  # Return as-is if missing or not a string

    def format_date(
        date_col: str,
        input_format: str = "%m/%d/%Y",
        output_format: str = "%Y-%m-%d",
    ):
        """Convert date to standard format, returning original value if parsing fails."""
        try:
            return datetime.strptime(date_col, input_format).strftime(output_format)
        except (ValueError, TypeError):
            return date_col  # return unchanged if invalid

    # Extract settings from config with safe defaults
    rename_map = config.analytic_params.rename_map
    bool_key = config.analytic_params.boolean_key
    bool_true_value = config.analytic_params.boolean_value

    transformed_record = {}

    for raw_col, clean_col in rename_map.items():
        value = record.get(raw_col, "")

        # Apply transformations based on column type
        if bool_key in clean_col:
            transformed_record[clean_col] = convert_bool(value, bool_true_value)
        elif config.analytic_params.rename_map.Phone in clean_col.upper():
            transformed_record[clean_col] = format_phone(value)
        elif config.analytic_params.rename_map.Date in clean_col.upper():
            transformed_record[clean_col] = format_date(value)
        else:
            transformed_record[clean_col] = value  # Copy unchanged

    # Ensure PROCESSED is always included
    transformed_record["PROCESSED"] = True

    return transformed_record


def mark_row_processed(
    raw_sheet: gspread.Worksheet,
    row_index,
    raw_status_col: str = "Processed",
):
    """Update the Processed column (in raw sheet) to 'True' for a specific row."""

    headers = raw_sheet.row_values(1)
    # gspread uses 1-based indexing
    processed_col_index = headers.index(raw_status_col) + 1
    raw_sheet.update_cell(row_index, processed_col_index, True)


def append_to_clean_sheet(clean_sheet: gspread.Worksheet, cleaned_record):
    """Append the cleaned record as a new row in clean_sheet."""
    header = clean_sheet.row_values(1)
    row_to_append = [cleaned_record.get(col, "") for col in header]
    clean_sheet.append_row(row_to_append)


def process_new_records(
    raw_sheet: gspread.Worksheet,
    clean_sheet: gspread.Worksheet,
    raw_id_col: str,
    clean_id_col: str,
    config: Box,
):
    """Process raw contacts and update clean_contacts."""

    raw_data = raw_sheet.get_all_records()
    processed_ids = get_processed_contacts(clean_sheet, clean_id_col)

    for i, record in enumerate(raw_data, start=2):
        if str(record.get(raw_id_col, "")).strip() not in processed_ids:
            cleaned_record = clean_and_transform(record, config)
            append_to_clean_sheet(clean_sheet, cleaned_record)
            mark_row_processed(raw_sheet, i)
            print(f"Processed {record.get('SurveyID')} - {record.get(raw_id_col)}")
        else:
            print(
                f"Skipping {record.get('SurveyID')} - {record.get(raw_id_col)} (Already Processed)"
            )


def main():
    dir_path = "configs"
    config = common_utils.load_configs(dir_path=dir_path, use_box=True)
    # print(config)

    client = auth_gspread_via_secret_manager(config)
    # print(client)

    raw_sheet, clean_sheet = get_raw_and_clean_sheets(client=client, config=config)
    # print(f"Raw sheet: {raw_sheet} \nClean sheet: {clean_sheet}")

    process_new_records(
        raw_sheet=raw_sheet,
        clean_sheet=clean_sheet,
        raw_id_col="ResponseID",
        clean_id_col="RESPONSE_ID",
        config=config,
    )


if __name__ == "__main__":
    main()
