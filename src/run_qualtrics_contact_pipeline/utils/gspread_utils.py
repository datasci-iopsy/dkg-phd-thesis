import gspread
import logging


# TODO: create function to create spreadsheet & worksheet (future release for ground-up project)
# TODO cont: should have column names and worksheet dimensions as function parameters
# TODO: cont: https://docs.gspread.org/en/latest/user-guide.html#creating-a-worksheet


# TODO: expand to have scopes
def auth_gspread(credentials: dict[str, str]) -> gspread.Client:
    """_summary_

    Args:
        credentials (dict[str, str]): _description_

    Returns:
        gspread.Client: _description_
    """
    try:
        # default scopes within gspread api
        # https://docs.gspread.org/en/latest/api/auth.html#gspread.auth.service_account_from_dict
        scopes = [
            "https://spreadsheets.google.com/feeds",
            "https://www.googleapis.com/auth/drive",
        ]

        client = gspread.service_account_from_dict(credentials, scopes=scopes)
        logging.info("Successfully authenticated with Google Sheets.")
        return client

    except Exception as e:
        logging.error(
            f"Failed to authenticate with Google Sheets: {e}",
            exc_info=True,
        )
        raise


def get_gsheet(
    client: gspread.Client,
    use_method: str,
    spreadsheet_id: str,
    sheet_name: str,
) -> gspread.Worksheet:
    """_summary_

    Args:
        client (gspread.Client): _description_
        use_method (str): _description_
        spreadsheet_id (str): _description_
        sheet_name (str): _description_

    Raises:
        ValueError: _description_

    Returns:
        gspread.Worksheet: _description_
    """

    # TODO: expand control flow and try-except blocks to check if sheet exists
    # TODO cont: create it if one wants; should be a parameter in function
    # def ensure_sheet_exists(client, spreadsheet_id, sheet_name):
    # try:
    #     return gspread_utils.get_gsheet(client=client, use_method="title", spreadsheet_id=spreadsheet_id, sheet_name=sheet_name)
    # except Exception:  # Replace with specific exception for missing sheets
    #     # Create a new sheet if it doesn't exist
    #     spreadsheet = client.open_by_key(spreadsheet_id)
    #     spreadsheet.add_worksheet(title=sheet_name, rows="100", cols="20")
    #     return spreadsheet.worksheet(sheet_name)
    try:
        if use_method == "key":
            sheet = client.open_by_key(spreadsheet_id).worksheet(sheet_name)
            logging.info(f"Client successfully open {sheet_name} using {use_method}.")
        elif use_method == "url":
            sheet = client.open_by_url(spreadsheet_id).worksheet(sheet_name)
            logging.info(f"Client successfully open {sheet_name} using {use_method}.")
        else:
            logging.error(f"{use_method} could not be used.", exc_info=True)
            raise ValueError(f"{use_method} must be 'key' or 'url'.")
        return sheet

    except Exception as e:
        logging.error(
            f"Client failed to open sheet {sheet_name} using {use_method}: {e}",
            exc_info=True,
        )
        raise
