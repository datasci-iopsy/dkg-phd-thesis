import logging
import gspread
import pandas as pd

from gspread_dataframe import get_as_dataframe

pd.options.display.max_columns = None
pd.options.display.max_colwidth = None
pd.options.display.max_rows = 10


def load_sheet_to_df(worksheet: gspread.Worksheet) -> pd.DataFrame:
    """_summary_

    Args:
        worksheet (gspread.Worksheet): _description_

    Raises:
        e: _description_

    Returns:
        pd.DataFrame: _description_
    """
    try:
        df = get_as_dataframe(
            worksheet=worksheet,
            evaluate_formulas=True,
            dtype=str,  # * read all cols as type str
        )

        # df = df.dropna(how="all")  # Drop empty rows
        logging.info(f"Loaded data with shape {df.shape}.")
        return df

    except Exception as e:
        logging.exception("Failed to load data from worksheet.")
        raise e


# TODO: build in logic so that not every field is mandatory...
# TODO cont: this will provide useful for dfs outside of this project
def transform_df(
    df: pd.DataFrame,
    rename_map: dict[str, str],
    bool_key: str,
    bool_value: str,
) -> pd.DataFrame:
    try:
        # * rename cols
        # TODO: add error handling if col count does not match
        df = df.rename(columns=rename_map)
        logging.info("Columns have been renamed based on provided map.")

        # * convert flag cols from string values to bools
        # TODO: add error handling if col count does not match
        bool_cols = [bool_cols for bool_cols in df.columns if bool_key in bool_cols]
        df[bool_cols] = df[bool_cols].apply(
            lambda col: col.astype(str).str.strip() == bool_value
        )

        # * add country code (i.e., +1) to phone number
        if "PHONE" in df.columns:
            # Convert to string first and handle potential NaN values.
            df["PHONE"] = df["PHONE"].apply(
                lambda x: f"+1{str(x)}" if pd.notnull(x) else x
            )

        logging.info("Updated 'PHONE' column by prefixing with '+1'.")

        # * Convert dates from m/d/yyyy to yyyy-mm-dd
        if "DATE" in df.columns:
            df["DATE"] = pd.to_datetime(
                df["DATE"], format="%m/%d/%Y", errors="coerce"
            ).dt.strftime("%Y-%m-%d")
        logging.info("Converted date format.")

        # # Convert PROCESSED to bool (for internal logic)
        # if "PROCESSED" in df.columns:
        #     df["PROCESSED"] = (
        #         df["PROCESSED"].astype(str).str.strip().str.upper() == "TRUE"
        #     )

        return df

    except Exception as e:
        logging.exception("Error during DataFrame transformation.")
        raise e
