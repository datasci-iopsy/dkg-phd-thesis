import gspread
import logging


# TODO: create function to create worksheet (future release for ground-up project)
# TODO cont: should have column names and worksheet dimensions as function parameters
# TODO: cont: https://docs.gspread.org/en/latest/user-guide.html#creating-a-worksheet


def get_gsheet(
    credentials: dict[str, str],
    use_method: str,
    spreadsheet_id: str,
    sheet_name: str,
):
    """_summary_

    Args:
        credentials (dict[str, str]): _description_
        use_method (str): _description_
        spreadsheet_id (str): _description_
        sheet_name (str): _description_

    Raises:
        ValueError: _description_

    Returns:
        _type_: _description_
    """

    # default scopes within gspread api
    # https://docs.gspread.org/en/latest/api/auth.html#gspread.auth.service_account_from_dict
    try:
        client = gspread.service_account_from_dict(credentials)

        if use_method == "key":
            sheet = client.open_by_key(spreadsheet_id).worksheet(sheet_name)
        elif use_method == "url":
            sheet = client.open_by_url(spreadsheet_id).worksheet(sheet_name)
        else:
            logging.error(
                "Parameter 'use_method' must be 'key' or 'url'.",
                exc_info=True,
            )
            raise ValueError(f"{use_method} could not be used.")
        return sheet

    except Exception as e:
        logging.error(f"Client failed: {e}", exc_info=True)
        raise


# TODO: expand to get list of list in addition to the dict
# TODO cont: https://docs.gspread.org/en/latest/user-guide.html#getting-all-values-from-a-worksheet-as-a-list-of-lists
def get_gsheet_records(sheet) -> dict[str, any]:
    """_summary_

    Args:
        sheet (_type_): _description_

    Returns:
        _type_: _description_
    """
    data = sheet.get_all_records()

    return data
