import pendulum
# TODO: https://gspread-dataframe.readthedocs.io/en/latest/

# Get all available time zones from Pendulum
all_tzs = pendulum.timezones()

# Filter time zones that start with "America/"
us_tzs = [tz for tz in all_tzs if tz.startswith("US/")]

for tz in us_tzs:
    print(tz)

# # import logging
# import pendulum

# # Call the function to get the list of timezones
# timezones = pendulum.timezones()

# # Print the list
# for tz in timezones:
#     print(tz)
# # TODO: function should move data to new spreadsheet as well with updated fields; thus expand
# # loop through rows and process unprocessed data
# def process_and_update_raw_data(
#     sheet,
#     data,
#     status_col,):
#     for row_idx, row in enumerate(data, start=2):  # start at 2 because row 1 is headers
#         if row[status_col] == "FALSE":  # check if the row is unprocessed
#             unique_id = row["ProlificPIDEntry"]
#             relevant_data = row["LocalTZ"]

#             # run your data analysis or processing logic here
#             logging.info(f"Processing ID: {unique_id}, Data: {relevant_data}")

#             # Update the "Processed" flag in the sheet; must be sheet object
#             sheet.update_cell(
#                 row_idx,
#                 len(row),  # * assuming "Processed" is the last column
#                 "TRUE",
#             )

#     logging.info("Processing complete!")
