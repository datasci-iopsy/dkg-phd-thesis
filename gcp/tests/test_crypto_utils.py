"""
Unit tests for phone number encryption/decryption.

PHONE_ENCRYPTION_KEY is injected by pytest-env from pyproject.toml
before module import, so the module-level Fernet init in crypto_utils
succeeds without any test-level setup.

Usage from project root:
    uv run pytest gcp/tests/test_crypto_utils.py -v
"""

import pytest
from cryptography.fernet import InvalidToken
from shared.utils.crypto_utils import decrypt_phone, encrypt_phone


class TestEncryptPhone:
    """encrypt_phone produces valid Fernet tokens."""

    def test_returns_string(self):
        result = encrypt_phone("+18777804236")
        assert isinstance(result, str)

    def test_non_deterministic(self):
        """Same input produces different ciphertext each call (fresh IV)."""
        c1 = encrypt_phone("+18777804236")
        c2 = encrypt_phone("+18777804236")
        assert c1 != c2

    def test_none_passthrough(self):
        assert encrypt_phone(None) is None

    def test_output_is_not_plaintext(self):
        result = encrypt_phone("+18777804236")
        assert "+18777804236" not in result


class TestDecryptPhone:
    """decrypt_phone recovers the original E.164 value."""

    def test_round_trip_e164(self):
        plaintext = "+18777804236"
        assert decrypt_phone(encrypt_phone(plaintext)) == plaintext

    def test_round_trip_ten_digit_normalized(self):
        plaintext = "+19845557878"
        assert decrypt_phone(encrypt_phone(plaintext)) == plaintext

    def test_none_passthrough(self):
        assert decrypt_phone(None) is None

    def test_tampered_token_raises(self):
        ciphertext = encrypt_phone("+18777804236")
        # Flip a character near the middle of the token
        mid = len(ciphertext) // 2
        tampered = (
            ciphertext[:mid]
            + ("X" if ciphertext[mid] != "X" else "Y")
            + ciphertext[mid + 1 :]
        )
        with pytest.raises(InvalidToken):
            decrypt_phone(tampered)

    def test_plaintext_phone_raises(self):
        """Passing raw E.164 directly (not encrypted) raises InvalidToken."""
        with pytest.raises(InvalidToken):
            decrypt_phone("+18777804236")

    def test_empty_string_raises(self):
        with pytest.raises(InvalidToken):
            decrypt_phone("")
