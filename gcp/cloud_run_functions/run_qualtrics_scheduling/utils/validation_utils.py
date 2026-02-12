"""Web Service payload validation and participant extraction.

Handles two distinct steps in the processing pipeline:

1. extract_web_service_payload -- parses the raw Flask request into a
   validated WebServicePayload from the Qualtrics Workflow Web Service
   task.

2. extract_participant_data -- pulls scheduling-relevant fields from
   the validated payload and constructs a ParticipantData model with
   full validation. Returns None if any required scheduling field
   is missing (which happens when survey logic routes a participant
   to the end early).
"""

import logging
from datetime import date

from flask import Request
from models.participant import ParticipantData, normalize_phone_number
from models.qualtrics import CONSENT_AGREE_VALUE, WebServicePayload
from pydantic import ValidationError

logger = logging.getLogger(__name__)


def extract_web_service_payload(request: Request) -> WebServicePayload | None:
    """Parse and validate a Qualtrics Web Service task POST payload.

    The Web Service task sends the complete survey response as a
    JSON body with semantic field names. Pydantic validates all
    required fields and types.

    Args:
        request: Flask request object from the incoming webhook.

    Returns:
        Validated WebServicePayload, or None if the payload is
        missing, malformed, or fails validation.
    """
    try:
        raw = request.get_json(silent=True, force=True)

        if not raw:
            logger.error("No JSON payload in request")
            return None

        try:
            payload = WebServicePayload.model_validate(raw)
        except ValidationError as e:
            logger.error("Web service payload validation failed: %s", e)
            return None

        logger.info(
            "Received web service payload for response: %s",
            payload.response_id,
        )
        return payload

    except Exception as e:
        logger.error(
            "Error extracting web service payload: %s", e, exc_info=True
        )
        return None


def extract_participant_data(
    payload: WebServicePayload,
) -> ParticipantData | None:
    """Extract and validate participant data from a Web Service payload.

    Reads scheduling-relevant fields (Prolific PID, phone, date,
    timezone, consent) directly from the payload's semantic fields,
    normalizes them, and constructs a validated ParticipantData.

    Returns None if any required scheduling field is missing
    (None). This happens when Qualtrics survey logic routes a
    participant to the end early due to failed screening or
    attention checks.

    Args:
        payload: Validated WebServicePayload from the Qualtrics
            Web Service task.

    Returns:
        Validated ParticipantData, or None if extraction or
        validation fails (consent not given, bad phone, etc.).
    """
    try:
        # -- Check consent before doing any other work ---------------
        if payload.consent != CONSENT_AGREE_VALUE:
            logger.error(
                "Consent not given for response %s (value: %s)",
                payload.response_id,
                payload.consent,
            )
            return None

        # -- Guard against missing scheduling fields -----------------
        # These are None when survey logic skips sections.
        if not payload.phone:
            logger.error(
                "Missing phone for response %s",
                payload.response_id,
            )
            return None

        if not payload.selected_date:
            logger.error(
                "Missing selected_date for response %s",
                payload.response_id,
            )
            return None

        if not payload.timezone:
            logger.error(
                "Missing timezone for response %s",
                payload.response_id,
            )
            return None

        if not payload.prolific_pid:
            logger.error(
                "Missing prolific_pid for response %s",
                payload.response_id,
            )
            return None

        # -- Normalize phone -----------------------------------------
        phone = normalize_phone_number(payload.phone)
        if not phone:
            logger.error(
                "Could not normalize phone for response %s: '%s'",
                payload.response_id,
                payload.phone,
            )
            return None

        # -- Parse selected date (MM/DD/YYYY from Qualtrics) ---------
        try:
            month, day, year = payload.selected_date.split("/")
            selected_date = date(int(year), int(month), int(day))
        except (ValueError, AttributeError):
            logger.error(
                "Invalid date format for response %s: '%s'",
                payload.response_id,
                payload.selected_date,
            )
            return None

        # -- Construct validated participant -------------------------
        participant = ParticipantData(
            response_id=payload.response_id,
            prolific_pid=payload.prolific_pid,
            phone=phone,
            selected_date=selected_date,
            timezone=payload.timezone,
            consent_given=True,
        )

        logger.info(
            "Extracted participant for response %s (phone: %s)",
            payload.response_id,
            participant.phone_masked,
        )
        return participant

    except ValidationError as e:
        logger.error(
            "Participant validation failed for %s: %s",
            payload.response_id,
            e,
        )
        return None
    except Exception as e:
        logger.error(
            "Error extracting participant data for %s: %s",
            payload.response_id,
            e,
            exc_info=True,
        )
        return None
