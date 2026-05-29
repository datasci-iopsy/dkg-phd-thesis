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
    connect_id: str | None = Field(default=None)
    phone: str
    selected_date: date
    timezone: str = Field(..., min_length=1)
    consent_given: bool
    created_at: datetime = Field(default_factory=lambda: datetime.now(UTC))

    @field_validator("connect_id", mode="before")
    @classmethod
    def strip_connect_id(cls, v: object) -> object:
        """Strip whitespace; coerce blank strings to None."""
        if isinstance(v, str):
            stripped = v.strip()
            return stripped if stripped else None
        return v

    @field_validator("consent_given")
    @classmethod
    def require_consent(cls, v: bool) -> bool:
        """Reject participants who have not given consent."""
        if not v:
            raise ValueError("Consent not given -- cannot process response")
        return v

    @field_validator("phone")
    @classmethod
    def require_encrypted_phone(cls, v: str) -> str:
        """Reject plaintext phone numbers (E.164 max 16 chars).

        Fernet tokens are always 100+ chars. A threshold of 50
        reliably distinguishes encrypted values from plaintext.
        """
        if len(v) < 50:
            raise ValueError(
                "phone must be a Fernet-encrypted string, not plaintext"
            )
        return v

    @property
    def phone_masked(self) -> str:
        """Safe log token -- phone is encrypted at rest."""
        return "[encrypted]"

    @property
    def followup_times(self) -> list[time]:
        """Fixed daily times for follow-up survey delivery."""
        return [time(9, 0), time(13, 0), time(17, 0)]
