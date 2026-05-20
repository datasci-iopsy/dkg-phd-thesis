"""Phone number encryption/decryption using Fernet symmetric encryption.

The key is loaded once at cold start from PHONE_ENCRYPTION_KEY (injected
via Cloud Run --set-secrets from Secret Manager). The same pattern is used
for TWILIO_CONFIG in the other functions.

Key format: URL-safe base64-encoded 32-byte key, as returned by
Fernet.generate_key(). Store the raw string in Secret Manager.
"""

import os

from cryptography.fernet import Fernet

_key = os.environ.get("PHONE_ENCRYPTION_KEY")
if not _key:
    raise RuntimeError(
        "PHONE_ENCRYPTION_KEY is not set -- check Secret Manager mount in functions.yaml"
    )
_fernet = Fernet(_key.encode())


def encrypt_phone(plaintext: str | None) -> str | None:
    """Encrypt an E.164 phone number to a Fernet token.

    Args:
        plaintext: E.164 phone string, or None.

    Returns:
        Fernet-encrypted string, or None if input is None.
    """
    if plaintext is None:
        return None
    return _fernet.encrypt(plaintext.encode()).decode()


def decrypt_phone(ciphertext: str | None) -> str | None:
    """Decrypt a Fernet token back to an E.164 phone number.

    Args:
        ciphertext: Fernet-encrypted phone string, or None.

    Returns:
        Plaintext E.164 string, or None if input is None.

    Raises:
        cryptography.fernet.InvalidToken: If ciphertext is tampered or
            encrypted with a different key.
    """
    if ciphertext is None:
        return None
    return _fernet.decrypt(ciphertext.encode()).decode()
