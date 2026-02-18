"""Pydantic model for validated participant data.

Replaces the former dataclass + is_valid() pattern. Validation
now runs at construction time via Pydantic field validators.
If any field is invalid, model_validate() raises ValidationError
with a clear message -- no separate validation step needed.

Phone normalization (raw digits -> E.164) is handled by
normalize_phone_number() before constructing the model. The
model's validator enforces the E.164 format constraint; it does
not attempt to guess at normalization.
"""

import re
from datetime import UTC, date, datetime, time

from pydantic import BaseModel, Field, field_validator


def normalize_phone_number(raw_phone: str) -> str | None:
    """Normalize a raw phone string to E.164 format (+1XXXXXXXXXX).

    Handles common US formats: 10 digits, 11 digits with leading 1,
    or already-prefixed with +. Returns None if the input cannot
    be normalized.

    This is a pre-processing step -- call it before constructing
    ParticipantData, which validates the final format.

    Args:
        raw_phone: Raw phone string from the survey response.

    Returns:
        E.164 formatted string, or None if unrecognizable.
    """
    if not raw_phone or not raw_phone.strip():
        return None

    digits = "".join(c for c in raw_phone if c.isdigit())

    if len(digits) == 10:
        return f"+1{digits}"
    if len(digits) == 11 and digits[0] == "1":
        return f"+{digits}"
    if raw_phone.startswith("+") and len(digits) >= 10:
        return f"+{digits}"

    return None


class ParticipantData(BaseModel):
    """Validated participant extracted from a Qualtrics survey response.

    Construction fails with ValidationError if any field is invalid.
    This replaces the old pattern of constructing first and calling
    is_valid() afterward.

    Attributes:
        response_id: Qualtrics response identifier (e.g., R_1KNaaa...).
        prolific_pid: Prolific participant identifier from free-text field.
        phone: E.164 formatted phone number (validated).
        selected_date: Date chosen for follow-up scheduling.
        timezone: IANA-style timezone string (e.g., "US/Central").
        consent_given: Must be True -- non-consenting responses are
            rejected at validation time.
        created_at: Timestamp when this record was created.
    """

    response_id: str
    prolific_pid: str = Field(..., min_length=1)
    phone: str
    selected_date: date
    timezone: str = Field(..., min_length=1)
    consent_given: bool
    created_at: datetime = Field(default_factory=lambda: datetime.now(UTC))

    @field_validator("prolific_pid")
    @classmethod
    def strip_and_validate_pid(cls, v: str) -> str:
        """Strip whitespace and reject blank Prolific PIDs."""
        stripped = v.strip()
        if not stripped:
            raise ValueError("Prolific PID cannot be blank")
        return stripped

    @field_validator("phone")
    @classmethod
    def validate_e164_phone(cls, v: str) -> str:
        """Enforce E.164 phone format (+[country][number])."""
        if not re.match(r"^\+[1-9]\d{1,14}$", v):
            raise ValueError(
                f"Phone must be E.164 format (e.g., +18777804236), got: {v}"
            )
        return v

    @field_validator("consent_given")
    @classmethod
    def require_consent(cls, v: bool) -> bool:
        """Reject participants who have not given consent."""
        if not v:
            raise ValueError("Consent not given -- cannot process response")
        return v

    @property
    def phone_masked(self) -> str:
        """Masked phone for safe logging (e.g., +1***7878)."""
        if len(self.phone) > 4:
            return f"{self.phone[:2]}***{self.phone[-4:]}"
        return "***"

    @property
    def followup_times(self) -> list[time]:
        """Fixed daily times for follow-up survey delivery."""
        return [time(9, 0), time(13, 0), time(17, 0)]
