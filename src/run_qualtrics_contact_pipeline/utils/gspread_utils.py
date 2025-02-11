import gspread
import logging


# TODO: create function to create spreadsheet & worksheet (future release for ground-up project)
# TODO cont: should have column names and worksheet dimensions as function parameters
# TODO: cont: https://docs.gspread.org/en/latest/user-guide.html#creating-a-worksheet


# TODO: expand to have scopes
def auth_gspread(credentials: dict[str, str]) -> gspread.Client:
    """Authenticates with Google Sheets using service account credentials.

    Applies default scopes for both spreadsheets and Drive access.

    Args:
        credentials (dict[str, str]): Service account credentials provided as a dictionary.

    Returns:
        gspread.Client: An authenticated client for interacting with Google Sheets.
    """
    try:
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
    """Retrieves a worksheet from a Google spreadsheet based on the specified access method.

    Depending on the method provided ('key' or 'url'), opens the spreadsheet accordingly
    and returns the worksheet by its name.

    Args:
        client (gspread.Client): An authenticated gspread client.
        use_method (str): The method for opening the spreadsheet; must be either "key" or "url".
        spreadsheet_id (str): The identifier of the spreadsheet. For 'key', this is the spreadsheet key;
                              for 'url', the full spreadsheet URL.
        sheet_name (str): The name of the worksheet to retrieve.

    Raises:
        ValueError: If the provided use_method is not "key" or "url".
        Exception: For any other error encountered while accessing the spreadsheet or worksheet.

    Returns:
        gspread.Worksheet: The worksheet matching the provided sheet_name.
    """
    try:
        if use_method == "key":
            sheet = client.open_by_key(spreadsheet_id).worksheet(sheet_name)
            logging.info(
                f"Client successfully opened {sheet_name} using method '{use_method}'."
            )
        elif use_method == "url":
            sheet = client.open_by_url(spreadsheet_id).worksheet(sheet_name)
            logging.info(
                f"Client successfully opened {sheet_name} using method '{use_method}'."
            )
        else:
            logging.error(f"{use_method} is not a valid access method.", exc_info=True)
            raise ValueError(f"{use_method} must be 'key' or 'url'.")
        return sheet

    except Exception as e:
        logging.error(
            f"Client failed to open sheet {sheet_name} using method '{use_method}': {e}",
            exc_info=True,
        )
        raise
