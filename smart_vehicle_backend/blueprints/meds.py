from flask import Blueprint, render_template, jsonify, request
from flask_login import login_required
from datetime import datetime, timezone

from extensions import db
from models import MedReminder
from api_auth import get_api_user_from_request

bp = Blueprint("meds", __name__)


@bp.route("/meds")
@login_required
def meds_page():
    return render_template("meds.html")


def today_key_local():
    now = datetime.now()
    return now.strftime("%Y-%m-%d")


def to_iso_utc(dt):
    if not dt:
        return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.isoformat()


def normalize_pending_state(m: MedReminder):
    today = today_key_local()
    if m.pending_date != today:
        m.pending_today = False
        m.pending_date = today


def serialize_med(m: MedReminder):
    normalize_pending_state(m)
    return {
        "id": m.id,
        "name": m.name,
        "dosage": m.dosage or "",
        "time_of_day": m.time_of_day,
        "enabled": bool(m.enabled),
        "last_sent_at": to_iso_utc(m.last_sent_at),
        "last_confirmed_at": to_iso_utc(m.last_confirmed_at),
        "last_confirmed_by": m.last_confirmed_by or "",
        "pending_today": bool(m.pending_today),
        "pending_date": m.pending_date,
    }


@bp.route("/api/meds")
def meds_api():
    user = get_api_user_from_request()
    if not user:
        return jsonify({"ok": False, "error": "unauthorized", "count": 0, "items": []}), 401

    meds = (
        MedReminder.query
        .filter_by(user_id=user.id)
        .order_by(MedReminder.time_of_day.asc(), MedReminder.id.asc())
        .all()
    )

    changed = False
    out = []
    for m in meds:
        old_pending = m.pending_today
        old_date = m.pending_date
        item = serialize_med(m)
        out.append(item)
        if m.pending_today != old_pending or m.pending_date != old_date:
            changed = True

    if changed:
        db.session.commit()

    return jsonify({
        "ok": True,
        "count": len(out),
        "items": out,
    })


@bp.route("/api/meds", methods=["POST"])
def meds_create():
    user = get_api_user_from_request()
    if not user:
        return jsonify({"ok": False, "error": "unauthorized"}), 401

    data = request.get_json(force=True, silent=True) or {}

    name = (data.get("name") or "").strip()
    dosage = (data.get("dosage") or "").strip()
    time_of_day = (data.get("time_of_day") or "").strip()
    enabled = bool(data.get("enabled", True))

    if not name:
        return jsonify({"ok": False, "error": "name is required"}), 400

    if len(time_of_day) != 5 or time_of_day[2] != ":":
        return jsonify({"ok": False, "error": "time_of_day must be HH:MM"}), 400

    hh, mm = time_of_day.split(":")
    try:
        hh = int(hh)
        mm = int(mm)
    except Exception:
        return jsonify({"ok": False, "error": "time_of_day must be HH:MM"}), 400

    if not (0 <= hh <= 23 and 0 <= mm <= 59):
        return jsonify({"ok": False, "error": "invalid time_of_day"}), 400

    row = MedReminder(
        user_id=user.id,
        name=name,
        dosage=dosage,
        time_of_day=time_of_day,
        enabled=enabled,
        pending_today=False,
        pending_date=today_key_local(),
    )
    db.session.add(row)
    db.session.commit()

    return jsonify({
        "ok": True,
        "message": "med reminder created",
        "item": serialize_med(row),
    })


@bp.route("/api/meds/<int:mid>", methods=["PUT"])
def meds_update(mid: int):
    user = get_api_user_from_request()
    if not user:
        return jsonify({"ok": False, "error": "unauthorized"}), 401

    row = MedReminder.query.filter_by(id=mid, user_id=user.id).first()
    if not row:
        return jsonify({"ok": False, "error": "record not found"}), 404

    data = request.get_json(force=True, silent=True) or {}

    name = data.get("name")
    dosage = data.get("dosage")
    time_of_day = data.get("time_of_day")
    enabled = data.get("enabled")

    if name is not None:
        name = str(name).strip()
        if not name:
            return jsonify({"ok": False, "error": "name cannot be empty"}), 400
        row.name = name

    if dosage is not None:
        row.dosage = str(dosage).strip()

    if time_of_day is not None:
        time_of_day = str(time_of_day).strip()
        if len(time_of_day) != 5 or time_of_day[2] != ":":
            return jsonify({"ok": False, "error": "time_of_day must be HH:MM"}), 400
        hh, mm = time_of_day.split(":")
        try:
            hh = int(hh)
            mm = int(mm)
        except Exception:
            return jsonify({"ok": False, "error": "time_of_day must be HH:MM"}), 400
        if not (0 <= hh <= 23 and 0 <= mm <= 59):
            return jsonify({"ok": False, "error": "invalid time_of_day"}), 400
        row.time_of_day = time_of_day

    if enabled is not None:
        row.enabled = bool(enabled)

    db.session.commit()

    return jsonify({
        "ok": True,
        "message": "med reminder updated",
        "item": serialize_med(row),
    })


@bp.route("/api/meds/<int:mid>", methods=["DELETE"])
def meds_delete(mid: int):
    user = get_api_user_from_request()
    if not user:
        return jsonify({"ok": False, "error": "unauthorized"}), 401

    row = MedReminder.query.filter_by(id=mid, user_id=user.id).first()
    if not row:
        return jsonify({"ok": False, "error": "record not found"}), 404

    db.session.delete(row)
    db.session.commit()

    return jsonify({
        "ok": True,
        "message": "med reminder deleted",
        "id": mid,
    })


@bp.route("/api/meds/<int:mid>/toggle", methods=["POST"])
def meds_toggle(mid: int):
    user = get_api_user_from_request()
    if not user:
        return jsonify({"ok": False, "error": "unauthorized"}), 401

    row = MedReminder.query.filter_by(id=mid, user_id=user.id).first()
    if not row:
        return jsonify({"ok": False, "error": "record not found"}), 404

    row.enabled = not bool(row.enabled)
    db.session.commit()

    return jsonify({
        "ok": True,
        "message": "med reminder toggled",
        "item": serialize_med(row),
    })


@bp.route("/api/meds/<int:mid>/mark-sent", methods=["POST"])
def meds_mark_sent(mid: int):
    user = get_api_user_from_request()
    if not user:
        return jsonify({"ok": False, "error": "unauthorized"}), 401

    row = MedReminder.query.filter_by(id=mid, user_id=user.id).first()
    if not row:
        return jsonify({"ok": False, "error": "record not found"}), 404

    row.last_sent_at = datetime.now(timezone.utc)
    row.pending_today = True
    row.pending_date = today_key_local()
    db.session.commit()

    return jsonify({
        "ok": True,
        "message": "med reminder marked as sent",
        "item": serialize_med(row),
    })


@bp.route("/api/meds/<int:mid>/confirm", methods=["POST"])
def meds_confirm(mid: int):
    user = get_api_user_from_request()
    if not user:
        return jsonify({"ok": False, "error": "unauthorized"}), 401

    row = MedReminder.query.filter_by(id=mid, user_id=user.id).first()
    if not row:
        return jsonify({"ok": False, "error": "record not found"}), 404

    data = request.get_json(force=True, silent=True) or {}
    confirmed_by = (data.get("confirmed_by") or user.email or "user").strip()

    row.last_confirmed_at = datetime.now(timezone.utc)
    row.last_confirmed_by = confirmed_by
    row.pending_today = False
    row.pending_date = today_key_local()
    db.session.commit()

    return jsonify({
        "ok": True,
        "message": "med reminder confirmed",
        "item": serialize_med(row),
    })