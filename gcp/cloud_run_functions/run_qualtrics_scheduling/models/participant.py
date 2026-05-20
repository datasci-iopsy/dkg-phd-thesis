"""Pydantic model for validated participant data.

Replaces the former dataclass + is_valid() pattern. Validation
now runs at construction time via Pydantic field validators.
If any field is invalid, model_validate() raises ValidationError
with a clear message -- no separate validation step needed.

Phone normalization (raw digits -> E.164) is handled by
normalize_phone_number() in shared.utils.phone_utils before
constructing the model. The phone field stores the Fernet-encrypted
E.164 value after encryption in validation_utils.
"""

from datetime import UTC, date, datetime, time

from pydantic import BaseModel, Field, field_validator


class ParticipantData(BaseModel):
    """Validated participant extracted from a Qualtrics survey response.

    Construction fails with ValidationError if any field is invalid.
    This replaces the old pattern of constructing first and calling
    is_valid() afterward.

    Attributes:
        response_id: Qualtrics response identifier (e.g., R_1KNaaa...).
        connect_id: Connect participant identifier from free-text field.
        phone: Fernet-encrypted E.164 phone number.
        selected_date: Date chosen for follow-up scheduling.
        timezone: IANA-style timezone string (e.g., "US/Central").
        consent_given: Must be True -- non-consenting responses are
            rejected at validation time.
        created_at: Timestamp when this record was created.
    """

    response_id: str
    connect_id: str = Field(..., min_length=1)
    phone: str
    selected_date: date
    timezone: str = Field(..., min_length=1)
    consent_given: bool
    created_at: datetime = Field(default_factory=lambda: datetime.now(UTC))

    @field_validator("connect_id")
    @classmethod
    def strip_and_validate_connect_id(cls, v: str) -> str:
        """Strip whitespace and reject blank Connect IDs."""
        stripped = v.strip()
        if not stripped:
            raise ValueError("Connect ID cannot be blank")
        return stripped

    @field_validator("consent_given")
    @classmethod
    def require_consent(cls, v: bool) -> bool:
        """Reject participants who have not given consent."""
        if not v:
            raise ValueError("Consent not given -- cannot process response")
        return v

    @property
    def phone_masked(self) -> str:
        """Safe log token -- phone is encrypted at rest."""
        return "[encrypted]"

    @property
    def followup_times(self) -> list[time]:
        """Fixed daily times for follow-up survey delivery."""
        return [time(9, 0), time(13, 0), time(17, 0)]
