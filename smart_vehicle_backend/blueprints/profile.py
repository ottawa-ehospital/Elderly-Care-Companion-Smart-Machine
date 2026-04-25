from flask import Blueprint, jsonify, request
from werkzeug.security import check_password_hash, generate_password_hash

from extensions import db
from models import User, Vital, FallEvent, MedReminder, WearableVital
from api_auth import get_api_user_from_request

from datetime import timezone

bp = Blueprint("profile", __name__)


def to_iso_utc(dt):
    if dt is None:
        return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    else:
        dt = dt.astimezone(timezone.utc)
    return dt.isoformat()


def user_payload(user: User):
    return {
        "id": user.id,
        "email": user.email,
        "patient_id": user.patient_id,
        "created_at": to_iso_utc(user.created_at),
    }


@bp.route("/api/profile")
def profile_get():
    user = get_api_user_from_request()
    if not user:
        return jsonify({"ok": False, "error": "unauthorized"}), 401

    return jsonify({
        "ok": True,
        "user": user_payload(user),
    })


@bp.route("/api/profile/patient-id", methods=["PUT", "POST"])
def profile_set_patient_id():
    user = get_api_user_from_request()
    if not user:
        return jsonify({"ok": False, "error": "unauthorized"}), 401

    data = request.get_json(force=True, silent=True) or {}
    patient_id = data.get("patient_id")

    if patient_id is None or str(patient_id).strip() == "":
        return jsonify({"ok": False, "error": "patient_id is required"}), 400

    try:
        patient_id = int(patient_id)
    except Exception:
        return jsonify({"ok": False, "error": "patient_id must be an integer"}), 400

    existing = User.query.filter(
        User.patient_id == patient_id,
        User.id != user.id
    ).first()

    if existing:
        return jsonify({
            "ok": False,
            "error": f"patient_id {patient_id} is already bound to another user"
        }), 409

    user.patient_id = patient_id

    Vital.query.filter_by(user_id=user.id).update(
        {"patient_id": patient_id},
        synchronize_session=False
    )

    FallEvent.query.filter_by(user_id=user.id).update(
        {"patient_id": patient_id},
        synchronize_session=False
    )

    db.session.commit()

    return jsonify({
        "ok": True,
        "message": "patient_id updated",
        "user": user_payload(user),
    })


@bp.route("/api/profile/email", methods=["PUT"])
def profile_update_email():
    user = get_api_user_from_request()
    if not user:
        return jsonify({"ok": False, "error": "unauthorized"}), 401

    data = request.get_json(force=True, silent=True) or {}
    new_email = (data.get("new_email") or "").strip().lower()
    current_password = data.get("current_password") or ""

    if not new_email:
        return jsonify({"ok": False, "error": "new_email is required"}), 400
    if not current_password:
        return jsonify({"ok": False, "error": "current_password is required"}), 400

    if not check_password_hash(user.password_hash, current_password):
        return jsonify({"ok": False, "error": "current password is incorrect"}), 401

    existing = User.query.filter(
        User.email == new_email,
        User.id != user.id
    ).first()
    if existing:
        return jsonify({"ok": False, "error": "email already in use"}), 409

    user.email = new_email
    db.session.commit()

    return jsonify({
        "ok": True,
        "message": "email updated",
        "user": user_payload(user),
    })


@bp.route("/api/profile/password", methods=["PUT"])
def profile_update_password():
    user = get_api_user_from_request()
    if not user:
        return jsonify({"ok": False, "error": "unauthorized"}), 401

    data = request.get_json(force=True, silent=True) or {}
    current_password = data.get("current_password") or ""
    new_password = data.get("new_password") or ""

    if not current_password:
        return jsonify({"ok": False, "error": "current_password is required"}), 400
    if not new_password:
        return jsonify({"ok": False, "error": "new_password is required"}), 400
    if len(new_password) < 6:
        return jsonify({"ok": False, "error": "new_password must be at least 6 characters"}), 400

    if not check_password_hash(user.password_hash, current_password):
        return jsonify({"ok": False, "error": "current password is incorrect"}), 401

    user.password_hash = generate_password_hash(new_password)
    db.session.commit()

    return jsonify({
        "ok": True,
        "message": "password updated",
    })


@bp.route("/api/profile/account", methods=["DELETE"])
def profile_delete_account():
    user = get_api_user_from_request()
    if not user:
        return jsonify({"ok": False, "error": "unauthorized"}), 401

    data = request.get_json(force=True, silent=True) or {}
    current_password = data.get("current_password") or ""

    if not current_password:
        return jsonify({"ok": False, "error": "current_password is required"}), 400

    if not check_password_hash(user.password_hash, current_password):
        return jsonify({"ok": False, "error": "current password is incorrect"}), 401

    user_id = user.id
    user_email = user.email

    Vital.query.filter_by(user_id=user_id).delete(synchronize_session=False)
    FallEvent.query.filter_by(user_id=user_id).delete(synchronize_session=False)
    MedReminder.query.filter_by(user_id=user_id).delete(synchronize_session=False)
    WearableVital.query.filter_by(user_id=user_id).delete(synchronize_session=False)

    db.session.delete(user)
    db.session.commit()

    return jsonify({
        "ok": True,
        "message": "account deleted",
        "deleted_user_id": user_id,
        "deleted_email": user_email,
    })