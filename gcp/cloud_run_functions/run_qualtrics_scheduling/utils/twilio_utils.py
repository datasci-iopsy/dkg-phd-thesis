"""
Twilio SMS utilities with native message scheduling.
Leverages Twilio's built-in scheduling feature instead of Cloud Tasks.
"""

import logging
from datetime import datetime, timedelta, time as dt_time
from typing import List, Optional
from twilio.rest import Client
from twilio.base.exceptions import TwilioRestException
from box import Box

from models.participant import ParticipantData
from utils.qualtrics_utils import build_followup_survey_url

logger = logging.getLogger(__name__)


def get_twilio_client(config: Box) -> Client:
    """
    Initializes authenticated Twilio client.

    Args:
        config: Configuration Box with Twilio credentials

    Returns:
        Client: Authenticated Twilio client instance
    """
    account_sid = config.params.twilio.account_sid
    auth_token = config.params.twilio.auth_token

    return Client(account_sid, auth_token)


def schedule_followup_surveys(
    participant: ParticipantData, survey_id: str, config: Box
) -> List[str]:
    """
    Schedules three follow-up SMS messages using Twilio's native scheduling.

    Twilio allows scheduling 15 minutes to 35 days in advance with no extra cost.
    Handles message cancellation if user opts out before send time.

    Reference: https://www.twilio.com/docs/messaging/features/message-scheduling

    Args:
        participant: ParticipantData instance with contact info
        survey_id: Qualtrics survey identifier
        config: Configuration Box

    Returns:
        list: Message SIDs of scheduled messages
    """
    try:
        client = get_twilio_client(config)
        messaging_service_sid = config.params.twilio.messaging_service_sid

        scheduled_messages = []

        for idx, followup_time in enumerate(participant.followup_times, start=1):
            # Combine selected date with followup time
            send_datetime = datetime.combine(participant.selected_date, followup_time)

            # Build personalized survey URL
            survey_url = build_followup_survey_url(
                survey_id=survey_id,
                response_id=participant.response_id,
                timepoint=idx,
                config=config,
            )

            # Construct SMS message
            message_body = (
                f"Hi {participant.name}! Time for follow-up survey #{idx} "
                f"({followup_time.strftime('%I:%M %p')}). "
                f"Please complete it here: {survey_url}. "
                f"Takes ~5 minutes. Thank you!"
            )

            # Schedule message via Twilio's native scheduling
            message = client.messages.create(
                messaging_service_sid=messaging_service_sid,
                to=participant.phone,
                body=message_body,
                schedule_type="fixed",
                send_at=send_datetime,
            )

            scheduled_messages.append(message.sid)

            logger.info(
                f"Scheduled SMS {idx}/3 (SID: {message.sid}) for "
                f"{send_datetime.isoformat()} to {participant.phone_masked}"
            )

        return scheduled_messages

    except TwilioRestException as e:
        logger.error(
            f"Twilio API error scheduling messages: {e.code} - {e.msg}", exc_info=True
        )
        raise

    except Exception as e:
        logger.error(f"Failed to schedule follow-up SMS: {str(e)}", exc_info=True)
        raise


def send_confirmation_sms(participant: ParticipantData, config: Box) -> bool:
    """
    Sends immediate confirmation SMS after consent form completion.

    Args:
        participant: ParticipantData instance
        config: Configuration Box

    Returns:
        bool: True if SMS sent successfully
    """
    try:
        client = get_twilio_client(config)
        messaging_service_sid = config.params.twilio.messaging_service_sid

        message_body = (
            f"Hi {participant.name}! Thank you for enrolling in our study. "
            f"You will receive 3 follow-up survey links on "
            f"{participant.selected_date.strftime('%B %d, %Y')} at "
            f"9:00 AM, 1:00 PM, and 5:00 PM. Reply STOP to opt out."
        )

        message = client.messages.create(
            messaging_service_sid=messaging_service_sid,
            to=participant.phone,
            body=message_body,
        )

        logger.info(
            f"Confirmation SMS sent (SID: {message.sid}) to {participant.phone_masked}"
        )

        return True

    except TwilioRestException as e:
        logger.error(
            f"Twilio error sending confirmation: {e.code} - {e.msg}", exc_info=True
        )
        return False

    except Exception as e:
        logger.error(f"Failed to send confirmation SMS: {str(e)}", exc_info=True)
        return False


def cancel_scheduled_message(message_sid: str, config: Box) -> bool:
    """
    Cancels a scheduled Twilio message before it's sent.

    Useful if participant opts out or withdraws consent.

    Args:
        message_sid: Twilio message identifier
        config: Configuration Box

    Returns:
        bool: True if cancellation successful
    """
    try:
        client = get_twilio_client(config)

        message = client.messages(message_sid).update(status="canceled")

        logger.info(f"Cancelled scheduled message: {message_sid}")
        return True

    except TwilioRestException as e:
        logger.error(f"Failed to cancel message {message_sid}: {e.msg}")
        return False
