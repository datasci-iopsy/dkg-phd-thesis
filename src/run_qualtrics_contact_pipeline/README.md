# run_qualtrics_contact_pipeline

## IN DEVELOPMENT
This python module handles the extraction, transformation, and scheduling of follow-up surveys via a variety of APIs.

1. Participants complete the initial sign-up survey in Qualtrics
2. New responses are automatically uploaded into a Google Sheet
3. A python script runs every 15 minutes (i.e., Cron job) to extract and transform new participants to set up scheduling

Each participant will have the option to choose a date to receive three follow-up surveys at 09:00, 12:00, and 15:00. Each survey will be active for 1 hour.

APIS:

- Qualtrics
- Google Sheets (i.e., `gspread`)
- Twilio