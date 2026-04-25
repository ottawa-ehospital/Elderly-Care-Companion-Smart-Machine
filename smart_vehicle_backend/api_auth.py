from typing import Optional

from flask import request
from itsdangerous import URLSafeTimedSerializer, BadSignature, SignatureExpired

from config import Config
from models import User


def _serializer() -> URLSafeTimedSerializer:
    return URLSafeTimedSerializer(
        Config.SECRET_KEY,
        salt="smart-vehicle-api-auth",
    )


def create_api_token(user: User) -> str:
    return _serializer().dumps({"user_id": user.id})


def verify_api_token(token: str, max_age: int = 60 * 60 * 24 * 7) -> Optional[User]:
    try:
        data = _serializer().loads(token, max_age=max_age)
    except (BadSignature, SignatureExpired):
        return None

    user_id = data.get("user_id")
    if not user_id:
        return None

    return User.query.get(user_id)


def get_token_from_request() -> Optional[str]:
    auth = request.headers.get("Authorization", "").strip()
    if auth.startswith("Bearer "):
        token = auth[7:].strip()
        if token:
            return token

    token = request.args.get("token", "").strip()
    if token:
        return token

    return None


def get_api_user_from_request() -> Optional[User]:
    token = get_token_from_request()
    if not token:
        return None
    return verify_api_token(token)