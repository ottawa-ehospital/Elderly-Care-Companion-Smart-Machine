from flask import Blueprint, render_template, jsonify, request
from flask_login import login_required
from urllib.request import urlopen
from urllib.parse import urlencode
import json

from extensions import db
from models import Vital
from api_auth import get_api_user_from_request
from datetime import datetime, timezone

bp = Blueprint("vitals", __name__)

WEARABLE_API_BASE = "https://aetab8pjmb.us-east-1.awsapprunner.com/table/wearable_vitals"


@bp.route("/vitals")
@login_required
def vitals_page():
    return render_template("vitals.html")


def _iso_utc_from_datetime(dt: datetime | None):
    if dt is None:
        return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    else:
        dt = dt.astimezone(timezone.utc)
    return dt.isoformat()


def _normalize_external_timestamp(value):
    if value is None:
        return None
    if isinstance(value, datetime):
        return _iso_utc_from_datetime(value)

    s = str(value).strip()
    if not s:
        return None

    try:
        probe = s.replace("Z", "+00:00")
        dt = datetime.fromisoformat(probe)
        if dt.tzinfo is not None:
            return dt.isoformat()
    except Exception:
        pass

    return s


def _sort_key_timestamp(item: dict):
    ts = item.get("timestamp")
    if ts is None:
      return ""

    s = str(ts).strip()
    if not s:
      return ""

    try:
        probe = s.replace("Z", "+00:00")
        dt = datetime.fromisoformat(probe)
        if dt.tzinfo is None:
            return dt.replace(tzinfo=timezone.utc).isoformat()
        return dt.astimezone(timezone.utc).isoformat()
    except Exception:
        return s


def normalize_manual_vital(v: Vital):
    return {
        "id": v.id,
        "timestamp": _iso_utc_from_datetime(v.timestamp),
        "patient_id": v.patient_id,
        "source": "manual",
        "heart_rate": v.heart_rate,
        "steps": v.steps,
        "calories": v.calories,
        "sleep": v.sleep,
        "notes": v.notes or "",
    }


def normalize_external_wearable(item: dict):
    pid = item.get("patient_id")
    try:
        pid = int(pid) if pid is not None else None
    except Exception:
        pid = None

    return {
        "id": item.get("id"),
        "timestamp": item.get("timestamp"),
        "patient_id": pid,
        "source": item.get("source", "wearable"),
        "heart_rate": item.get("heart_rate"),
        "steps": item.get("steps"),
        "calories": item.get("calories"),
        "sleep": item.get("sleep"),
        "notes": "",
    }


def fetch_wearable_records_from_api(patient_id: int):
    query = urlencode({"patient_id": patient_id})
    url = f"{WEARABLE_API_BASE}?{query}"

    with urlopen(url, timeout=15) as resp:
        raw = resp.read().decode("utf-8")
        data = json.loads(raw)

    if isinstance(data, list):
        return data
    if isinstance(data, dict):
        if isinstance(data.get("items"), list):
            return data["items"]
        if isinstance(data.get("data"), list):
            return data["data"]

    return []


@bp.route("/api/vitals")
def vitals_api():
    user = get_api_user_from_request()
    if not user:
        return jsonify({
            "ok": False,
            "error": "unauthorized",
            "latest_manual": None,
            "latest_wearable": None,
            "latest_overall": None,
            "manual_records": [],
            "wearable_records": [],
        }), 401

    print("DEBUG user.id =", user.id)
    print("DEBUG user.email =", user.email)
    print("DEBUG user.patient_id =", user.patient_id)

    if user.patient_id is not None:
        manual_rows = (
            Vital.query
            .filter_by(patient_id=user.patient_id)
            .order_by(Vital.timestamp.desc())
            .limit(100)
            .all()
        )
    else:
        manual_rows = (
            Vital.query
            .filter_by(user_id=user.id)
            .order_by(Vital.timestamp.desc())
            .limit(100)
            .all()
        )

    manual_records = [normalize_manual_vital(v) for v in manual_rows]

    wearable_records = []
    wearable_error = None

    if user.patient_id is not None:
        try:
            print("DEBUG wearable query patient_id =", user.patient_id)
            wearable_rows = fetch_wearable_records_from_api(user.patient_id)
            wearable_records = [normalize_external_wearable(x) for x in wearable_rows]

            wearable_records = [
                x for x in wearable_records
                if x.get("patient_id") == user.patient_id
            ]

            wearable_records = sorted(
                wearable_records,
                key=_sort_key_timestamp,
                reverse=True,
            )
        except Exception as e:
            wearable_error = str(e)

    combined_records = sorted(
        manual_records + wearable_records,
        key=_sort_key_timestamp,
        reverse=True,
    )

    latest_manual = manual_records[0] if manual_records else None
    latest_wearable = wearable_records[0] if wearable_records else None
    latest_overall = combined_records[0] if combined_records else None

    return jsonify({
        "ok": True,
        "user_id": user.id,
        "patient_id": user.patient_id,
        "latest_manual": latest_manual,
        "latest_wearable": latest_wearable,
        "latest_overall": latest_overall,
        "manual_records": manual_records,
        "wearable_records": wearable_records,
        "wearable_error": wearable_error,
    })


@bp.route("/api/vitals/manual", methods=["POST"])
def vitals_manual_create():
    user = get_api_user_from_request()
    if not user:
        return jsonify({"ok": False, "error": "unauthorized"}), 401

    data = request.get_json(force=True, silent=True) or {}

    heart_rate_raw = data.get("heart_rate")
    steps_raw = data.get("steps")
    calories_raw = data.get("calories")
    sleep_raw = data.get("sleep")
    notes = (data.get("notes") or "").strip()

    def parse_optional_int(value, field_name):
        if value in (None, ""):
            return None
        try:
            return int(value)
        except Exception:
            raise ValueError(f"{field_name} must be an integer")

    def parse_optional_float(value, field_name):
        if value in (None, ""):
            return None
        try:
            return float(value)
        except Exception:
            raise ValueError(f"{field_name} must be a number")

    try:
        heart_rate = parse_optional_int(heart_rate_raw, "heart_rate")
        steps = parse_optional_int(steps_raw, "steps")
        calories = parse_optional_int(calories_raw, "calories")
        sleep = parse_optional_float(sleep_raw, "sleep")
    except ValueError as e:
        return jsonify({"ok": False, "error": str(e)}), 400

    if all(v is None for v in [heart_rate, steps, calories, sleep]):
        return jsonify({
            "ok": False,
            "error": "at least one of heart_rate, steps, calories, sleep is required"
        }), 400

    row = Vital(
        user_id=user.id,
        patient_id=user.patient_id,
        heart_rate=heart_rate,
        steps=steps,
        calories=calories,
        sleep=sleep,
        spo2=None,
        bp_sys=None,
        bp_dia=None,
        temperature=None,
        notes=notes,
    )
    db.session.add(row)
    db.session.commit()

    return jsonify({
        "ok": True,
        "message": "manual vital created",
        "item": normalize_manual_vital(row),
    })


@bp.route("/api/vitals/manual/<int:vid>", methods=["DELETE"])
def vitals_manual_delete(vid: int):
    user = get_api_user_from_request()
    if not user:
        return jsonify({"ok": False, "error": "unauthorized"}), 401

    row = Vital.query.filter_by(id=vid, user_id=user.id).first()
    if not row:
        return jsonify({"ok": False, "error": "record not found"}), 404

    db.session.delete(row)
    db.session.commit()

    return jsonify({
        "ok": True,
        "message": "manual vital deleted",
        "id": vid,
    })