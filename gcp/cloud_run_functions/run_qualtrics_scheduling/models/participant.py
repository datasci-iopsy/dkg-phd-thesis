"""
Data models for type-safe participant information handling.
"""

from dataclasses import dataclass, field
from datetime import datetime, date, time
from typing import Optional
import re


@dataclass
class ParticipantData:
    """
    Represents a survey participant with PII and preferences.

    Attributes:
        response_id: Qualtrics response identifier
        name: Participant full name
        email: Participant email address
        phone: E.164 formatted phone number
        selected_date: Date for follow-up surveys
        consent_given: Whether informed consent was provided
        created_at: Timestamp of data creation
    """

    response_id: str
    name: str
    email: str
    phone: str
    selected_date: date
    consent_given: bool
    created_at: datetime = field(default_factory=datetime.utcnow)

    @property
    def phone_masked(self) -> str:
        """Returns masked phone number for logging (e.g., +1***5678)."""
        if len(self.phone) > 4:
            return f"{self.phone[:2]}***{self.phone[-4:]}"
        return "***"

    @property
    def followup_times(self) -> list[time]:
        """Returns the three follow-up survey times."""
        return [time(9, 0), time(13, 0), time(17, 0)]

    def is_valid(self) -> bool:
        """
        Validates participant data integrity.

        Returns:
            bool: True if all required fields are valid
        """
        if not all([self.response_id, self.name, self.email, self.phone]):
            return False

        if not self.consent_given:
            return False

        # Validate E.164 phone format
        phone_pattern = r"^\+[1-9]\d{1,14}$"
        if not re.match(phone_pattern, self.phone):
            return False

        # Validate email format
        email_pattern = r"^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$"
        if not re.match(email_pattern, self.email):
            return False

        return True

    def to_dict(self) -> dict:
        """Converts to dictionary for JSON serialization."""
        return {
            "response_id": self.response_id,
            "name": self.name,
            "email": self.email,
            "phone": self.phone,
            "selected_date": self.selected_date.isoformat(),
            "consent_given": self.consent_given,
            "created_at": self.created_at.isoformat(),
        }
