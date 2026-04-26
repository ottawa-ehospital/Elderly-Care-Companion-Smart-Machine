from flask import Blueprint, jsonify, request
from werkzeug.security import generate_password_hash, check_password_hash

from extensions import db
from models import User
from api_auth import create_api_token, get_api_user_from_request

bp = Blueprint("api_auth", __name__)


def user_payload(user: User):
    return {
        "id": user.id,
        "email": user.email,
        "patient_id": user.patient_id,
        "created_at": user.created_at.isoformat() if user.created_at else None,
    }


@bp.route("/api/auth/register", methods=["POST"])
def api_register():
    data = request.get_json(force=True, silent=True) or {}

    email = (data.get("email") or "").strip().lower()
    password = data.get("password") or ""
    patient_id_raw = data.get("patient_id")

    if not email:
        return jsonify({"ok": False, "error": "email is required"}), 400
    if not password or len(password) < 6:
        return jsonify({"ok": False, "error": "password must be at least 6 characters"}), 400

    existing = User.query.filter_by(email=email).first()
    if existing:
        return jsonify({"ok": False, "error": "email already registered"}), 409

    patient_id = None
    if patient_id_raw not in (None, ""):
        try:
            patient_id = int(patient_id_raw)
        except Exception:
            return jsonify({"ok": False, "error": "patient_id must be an integer"}), 400

        existing_pid = User.query.filter_by(patient_id=patient_id).first()
        if existing_pid:
            return jsonify({"ok": False, "error": "patient_id already bound to another user"}), 409

    user = User(
        email=email,
        password_hash=generate_password_hash(password),
        patient_id=patient_id,
    )
    db.session.add(user)
    db.session.commit()

    token = create_api_token(user)
    return jsonify({
        "ok": True,
        "token": token,
        "user": user_payload(user),
    })


@bp.route("/api/auth/login", methods=["POST"])
def api_login():
    data = request.get_json(force=True, silent=True) or {}

    email = (data.get("email") or "").strip().lower()
    password = data.get("password") or ""

    if not email or not password:
        return jsonify({"ok": False, "error": "email and password are required"}), 400

    user = User.query.filter_by(email=email).first()
    if not user:
        return jsonify({"ok": False, "error": "invalid email or password"}), 401

    if not check_password_hash(user.password_hash, password):
        return jsonify({"ok": False, "error": "invalid email or password"}), 401

    token = create_api_token(user)
    return jsonify({
        "ok": True,
        "token": token,
        "user": user_payload(user),
    })


@bp.route("/api/auth/me")
def api_me():
    user = get_api_user_from_request()
    if not user:
        return jsonify({"ok": False, "error": "unauthorized"}), 401

    return jsonify({
        "ok": True,
        "user": user_payload(user),
    })


@bp.route("/api/auth/logout", methods=["POST"])
def api_logout():
    return jsonify({"ok": True})