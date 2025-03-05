import gspread
from box import Box
from datetime import datetime
from utils import common_utils, gcp_utils, gspread_utils


def auth_gspread_via_secret_manager(config: Box):
    """
    Authenticates a gspread client using service account credentials retrieved from GCP Secret Manager.

    This function reads configuration values from the provided Box object, retrieves the secret
    containing the Google Sheets credentials using the GCP utility, and then uses gspread to authenticate
    and return an authenticated client.

    Args:
        config (Box): Configuration object with the following nested parameters:
            - params.gcp.project_id (str): Google Cloud project ID.
            - params.gcp.version_id (str): Version identifier for the secret.
            - params.gspread.secret_id (str): Secret ID holding the Google Sheets credentials.

    Returns:
        gspread.Client: An authenticated client used to access Google Sheets.

    Raises:
        Exception: Propagates any exceptions raised during secret retrieval or client authentication.
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


def get_raw_and_clean_sheets(client: gspread.Client, config: Box):
    """
    Retrieves both raw and clean worksheets from a Google Sheets spreadsheet.

    Using the provided gspread client and configuration, this function accesses the specified
    spreadsheet (either via a key or URL) and retrieves the worksheets designated for raw and clean contacts.

    Args:
        client (gspread.Client): An authenticated gspread client.
        config (Box): Configuration object with the following nested parameters:
            - params.gspread.use_method (str): Method for accessing the spreadsheet ("key" or "url").
            - params.gspread.spreadsheet_id (str): Spreadsheet identifier (key or URL).
            - params.gspread.raw_contacts_sheet_name (str): Name of the worksheet with raw contacts.
            - params.gspread.clean_contacts_sheet_name (str): Name of the worksheet with clean contacts.

    Returns:
        tuple(gspread.Worksheet, gspread.Worksheet): A tuple containing the raw worksheet and the clean worksheet.

    Raises:
        Exception: Propagates any exceptions from the sheet retrieval process.
    """
    use_method = config.params.gspread.use_method
    spreadsheet_id = config.params.gspread.spreadsheet_id
    raw_sheet_name = config.params.gspread.raw_contacts_sheet_name
    clean_sheet_name = config.params.gspread.clean_contacts_sheet_name

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
    """
    Extracts processed contact identifiers from the clean worksheet.

    The function retrieves all records from the clean worksheet and builds a set of unique identifiers
    from the specified column. If the column does not exist in the sheet's headers, it raises an exception.

    Args:
        clean_sheet (gspread.Worksheet): Worksheet containing processed (clean) contact records.
        clean_id_col (str): The column name that uniquely identifies a contact record in the clean sheet.

    Raises:
        ValueError: If the column specified by clean_id_col is not present in the clean sheet headers.

    Returns:
        set: A set of identifiers (as strings) corresponding to contacts that have already been processed.
        An empty set is returned if the clean sheet has no data.
    """
    clean_sheet_data = clean_sheet.get_all_records()
    if not clean_sheet_data:
        return set()

    if clean_id_col not in clean_sheet_data[0]:
        raise ValueError(
            f"Column '{clean_id_col}' not found in the clean sheet headers."
        )

    return {row[clean_id_col] for row in clean_sheet_data if row[clean_id_col]}


def clean_and_transform(record: dict, config: Box):
    """
    Cleans and transforms a raw record using configurable rules.

    This function performs several transformations on a raw record:
    - Renames columns based on a provided mapping.
    - Converts values to booleans if the column matches a specified boolean key.
    - Formats phone numbers by appending a default country code.
    - Converts dates from MM/DD/YYYY to YYYY-MM-DD format.
    - Ensures that the "PROCESSED" flag is explicitly set to True.

    Args:
        record (dict): The raw record containing original key-value pairs.
        config (Box): Configuration object with transformation settings:
            - analytic_params.rename_map (dict): Maps raw column names to new column names.
            - analytic_params.boolean_key (str): Identifier for columns that require boolean conversion.
            - analytic_params.boolean_value (str): Value to compare for converting strings to True.

    Returns:
        dict: A new record with updated keys, formatted values, and a "PROCESSED" flag set to True.
    """

    def convert_bool(value: str, true_value: str = "Yes"):
        """Converts a string value to a boolean based on the expected 'true_value'."""
        return str(value).strip().lower() == str(true_value).strip().lower()

    # def format_phone(phone_num: str, country_code: str = "+1"):
    #     """Formats the phone number by ensuring it is stored as text with a country code."""
    #     if phone_num and isinstance(phone_num, str):
    #         return f"{country_code}{phone_num.strip()}"
    #     return phone_num

    def format_phone(phone_num, country_code="+1"):
        """Ensures the phone number is stored as text with the country code."""
        if phone_num is not None:
            phone_str = str(phone_num).strip()
            if not phone_str.startswith(country_code):
                return f"{country_code}{phone_str}"
            return phone_str
        return ""

    def format_date(
        date_col: str,
        input_format: str = "%m/%d/%Y",
        output_format: str = "%Y-%m-%d",
    ):
        """Converts a date from MM/DD/YYYY format to YYYY-MM-DD format; returns original value if conversion fails."""
        try:
            return datetime.strptime(date_col, input_format).strftime(output_format)
        except (ValueError, TypeError):
            return date_col

    rename_map = config.analytic_params.rename_map
    bool_key = config.analytic_params.boolean_key
    bool_true_value = config.analytic_params.boolean_value

    transformed_record = {}
    for raw_col, clean_col in rename_map.items():
        value = record.get(raw_col, "")

        if bool_key in clean_col:
            transformed_record[clean_col] = convert_bool(value, bool_true_value)
        elif config.analytic_params.rename_map.Phone in clean_col.upper():
            transformed_record[clean_col] = format_phone(value)
        elif config.analytic_params.rename_map.Date in clean_col.upper():
            transformed_record[clean_col] = format_date(value)
        else:
            transformed_record[clean_col] = value

    # transformed_record["PROCESSED"] = True
    return transformed_record


def append_to_clean_sheet(clean_sheet: gspread.Worksheet, cleaned_record: dict):
    """
    Appends a cleaned record as a new row to the clean sheet.

    This function builds a row by aligning the cleaned record values with the header of the clean sheet
    and then appends the row to the sheet.

    Args:
        clean_sheet (gspread.Worksheet): The worksheet designated for storing cleaned records.
        cleaned_record (dict): A dictionary containing the cleaned record data, keyed by column names.

    Returns:
        None
    """
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
    """
    Processes new raw records and updates the clean sheet with transformed data.

    This function retrieves all raw records from the raw sheet and determines which records have not
    been processed by comparing raw identifiers against those present in the clean sheet. For each
    unprocessed record, it cleans and transforms the data, appends the cleaned record to the clean sheet,
    and marks the corresponding row in the raw sheet as processed.

    Args:
        raw_sheet (gspread.Worksheet): The worksheet containing raw contact records.
        clean_sheet (gspread.Worksheet): The worksheet where cleaned records are stored.
        raw_id_col (str): The column name in the raw sheet used to uniquely identify each record.
        clean_id_col (str): The column name in the clean sheet that tracks processed records.
        config (Box): Configuration object containing both transformation and access parameters.

    Returns:
        None

    Raises:
        Exception: Propagates any exceptions encountered during data transformation or sheet updates.
    """
    raw_data = raw_sheet.get_all_records()
    processed_ids = get_processed_contacts(clean_sheet, clean_id_col)

    for i, record in enumerate(raw_data, start=2):
        if str(record.get(raw_id_col, "")).strip() not in processed_ids:
            cleaned_record = clean_and_transform(record, config)
            append_to_clean_sheet(clean_sheet, cleaned_record)
            print(f"Processed {record.get('SurveyID')} - {record.get(raw_id_col)}")
        else:
            print(
                f"Skipping {record.get('SurveyID')} - {record.get(raw_id_col)} (Already Processed)"
            )


def main():
    """
    Main entry point for processing contact records from Google Sheets.

    This function loads configuration settings from the 'configs' directory, authenticates with
    Google Sheets using credentials stored in GCP Secret Manager, retrieves both raw and clean worksheets,
    and processes new raw records by cleaning and transferring them to the clean sheet while marking them
    as processed in the raw sheet.

    Returns:
        None
    """
    dir_path = "configs"
    config = common_utils.load_configs(dir_path=dir_path, use_box=True)

    client = auth_gspread_via_secret_manager(config)
    raw_sheet, clean_sheet = get_raw_and_clean_sheets(client=client, config=config)
    print(raw_sheet.get_all_records())
    process_new_records(
        raw_sheet=raw_sheet,
        clean_sheet=clean_sheet,
        raw_id_col="ResponseID",
        clean_id_col="RESPONSE_ID",
        config=config,
    )


if __name__ == "__main__":
    main()
