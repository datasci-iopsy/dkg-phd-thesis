# Run this once to generate a secure secret
import secrets

webhook_secret = secrets.token_urlsafe(32)
print(f"Your webhook secret: {webhook_secret}")
