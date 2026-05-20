"""Phone number normalization utilities."""


def normalize_phone_number(raw_phone: str) -> str | None:
    """Normalize a raw phone string to E.164 format (+1XXXXXXXXXX).

    Handles common US formats: 10 digits, 11 digits with leading 1,
    or already-prefixed with +. Returns None if the input cannot
    be normalized.

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
