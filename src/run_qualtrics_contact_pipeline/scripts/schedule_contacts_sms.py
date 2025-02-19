import gspread
import pandas as pd
from twilio.rest import Client
from datetime import datetime, time
import pytz
import os

# -------------------------------
# Configuration and Setup
# -------------------------------

# Your Twilio credentials and Messaging Service SID
TWILIO_ACCOUNT_SID = "ACXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"
TWILIO_AUTH_TOKEN = "your_auth_token"
MESSAGING_SERVICE_SID = "MGXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"

client = Client(TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN)

# Connect to Google Sheets using a service account.
# Make sure the JSON key file is available.
gc = gspread.service_account(filename="path/to/your_service_account.json")

# Open your spreadsheet and select the worksheet (for instance, the first sheet)
spreadsheet = gc.open("YOUR_SPREADSHEET_NAME")
worksheet = spreadsheet.sheet1

# Read the data into a list of dictionaries and also as a DataFrame (if needed)
data = worksheet.get_all_records()
df = pd.DataFrame(data)

# Get header row to determine the column number of the "SCHEDULED" column
headers = worksheet.row_values(1)
try:
    scheduled_col = headers.index("SCHEDULED") + 1  # gspread columns are 1-indexed
except ValueError:
    raise Exception('The worksheet must have a header named "SCHEDULED".')

# Fixed time points (local times) which will be scheduled every day
FIXED_TIMES = [time(9, 0), time(12, 0), time(15, 0)]

# -------------------------------
# Processing each row
# -------------------------------

for idx, row in df.iterrows():
    # Check if already processed. We use a robust check in case the value is boolean or a string.
    scheduled_flag = row.get("SCHEDULED")
    if scheduled_flag is True or str(scheduled_flag).strip().lower() == "true":
        print(f"Row {idx + 2}: Already processed.")
        continue

    # Extract required values from the row. Adjust keys as needed.
    phone_number = row["phone"]
    selected_date_str = row["selected_date"]  # e.g., "2025-03-15"
    timezone_str = row["timezone"]  # e.g., "America/New_York"
    survey_links = [
        row.get("survey_link1"),
        row.get("survey_link2"),
        row.get("survey_link3"),
    ]

    # Prepare the timezone conversion
    try:
        local_tz = pytz.timezone(timezone_str)
    except pytz.UnknownTimeZoneError:
        print(f"Row {idx + 2}: Unknown timezone '{timezone_str}'. Skipping.")
        continue

    # Loop over the three time slots and corresponding survey links.
    for send_time_local, survey_link in zip(FIXED_TIMES, survey_links):
        # Combine the selected date and the fixed time in the user’s local timezone.
        local_dt = datetime.combine(
            datetime.strptime(selected_date_str, "%Y-%m-%d"), send_time_local
        )
        local_dt = local_tz.localize(local_dt)
        # Convert to UTC since Twilio scheduling expects ISO 8601 UTC time.
        utc_dt = local_dt.astimezone(pytz.utc)
        send_at_iso = utc_dt.strftime("%Y-%m-%dT%H:%M:%SZ")

        # Craft the SMS body (you can customize the message as needed)
        body = f"Please complete the survey: {survey_link}"

        try:
            # Schedule the message by including the send_at and schedule_type parameters.
            # (See https://www.twilio.com/docs/messaging/api/message-resource#schedule-a-message-resource)
            message = client.messages.create(
                body=body,
                messaging_service_sid=MESSAGING_SERVICE_SID,
                to=phone_number,
                send_at=send_at_iso,
                schedule_type="fixed",
            )
            print(
                f"Scheduled message {message.sid} for {phone_number} at {send_at_iso}"
            )
        except Exception as e:
            print(f"Error scheduling message for {phone_number} at {send_at_iso}: {e}")

    # Update the Google Sheet row to mark it as processed.
    # Assuming that the first data row is on row 2 (after header)
    sheet_row_number = idx + 2
    worksheet.update_cell(sheet_row_number, scheduled_col, "True")
    print(f"Row {sheet_row_number} marked as SCHEDULED.")

# -------------------------------
# End of Script
# -------------------------------

# This script can be scheduled to run every 15 minutes (e.g., using a cron job or a scheduler library)


##############
from datetime import datetime, time
import os
import pytz
from twilio.rest import Client

# Set your Twilio configuration using environment variables
account_sid = os.environ["TWILIO_ACCOUNT_SID"]
auth_token = os.environ["TWILIO_AUTH_TOKEN"]
messaging_service_sid = os.environ["TWILIO_MESSAGING_SERVICE_SID"]
client = Client(account_sid, auth_token)

# Specify the user’s desired schedule date in YYYY-MM-DD format
schedule_date_str = "2025-03-15"
schedule_date = datetime.strptime(schedule_date_str, "%Y-%m-%d").date()

# Define the fixed local times for sending messages
local_times = [time(9, 0), time(12, 0), time(15, 0)]

# Define the local timezone (update as needed)
local_tz = pytz.timezone("America/New_York")

# Define the body text for the SMS (customize as needed)
sms_body = "Friendly reminder: Please complete your survey."

for send_time in local_times:
    # Combine the schedule date and fixed time to create a datetime object in local time
    local_dt = datetime.combine(schedule_date, send_time)
    local_dt = local_tz.localize(local_dt)

    # Convert the local datetime to UTC for Twilio (ISO 8601 format is required)
    utc_dt = local_dt.astimezone(pytz.utc)
    send_at_iso = utc_dt.strftime("%Y-%m-%dT%H:%M:%SZ")

    # Use Twilio's API to schedule the message with a fixed send time
    message = client.messages.create(
        from_=messaging_service_sid,  # Scheduling requires sending from a Messaging Service SID
        to="+1xxxxxxxxxx",  # Replace with the recipient's phone number in E.164 format
        body=sms_body,
        schedule_type="fixed",
        send_at=send_at_iso,
    )

    print(f"Scheduled message {message.sid} for {send_at_iso}")
