from flask import Blueprint, render_template, jsonify
from flask_login import login_required, current_user
from datetime import datetime, timedelta, timezone
from urllib.request import urlopen
from urllib.parse import urlencode
import json

from models import Vital, FallEvent, MedReminder
from api_auth import get_api_user_from_request

bp = Blueprint("dashboard", __name__)

WEARABLE_API_BASE = "https://aetab8pjmb.us-east-1.awsapprunner.com/table/wearable_vitals"


@bp.route("/")
@login_required
def dashboard():
    latest_vital = Vital.query.filter_by(user_id=current_user.id).order_by(Vital.timestamp.desc()).first()
    latest_fall = FallEvent.query.filter_by(user_id=current_user.id, deleted=False).order_by(FallEvent.timestamp.desc()).first()
    meds_count = MedReminder.query.filter_by(user_id=current_user.id, enabled=True).count()

    return render_template(
        "dashboard.html",
        latest_vital=latest_vital,
        latest_fall=latest_fall,
        meds_count=meds_count
    )

def to_iso_utc(dt):
    if dt is None:
        return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    else:
        dt = dt.astimezone(timezone.utc)
    return dt.isoformat()

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


def normalize_external_wearable(item: dict):
    pid = item.get("patient_id")
    try:
        pid = int(pid) if pid is not None else None
    except Exception:
        pid = None

    return {
        "id": item.get("id") or item.get("vital_id"),
        "timestamp": item.get("timestamp"),
        "patient_id": pid,
        "source": item.get("source", "wearable"),
        "heart_rate": item.get("heart_rate"),
        "steps": item.get("steps"),
        "calories": item.get("calories"),
        "sleep": item.get("sleep"),
        "notes": "",
    }


def normalize_manual_vital(v: Vital):
    return {
        "id": v.id,
        "timestamp": to_iso_utc(v.timestamp),
        "patient_id": v.patient_id,
        "source": "manual",
        "heart_rate": v.heart_rate,
        "steps": v.steps,
        "calories": v.calories,
        "sleep": v.sleep,
        "notes": v.notes or "",
    }

def _parse_iso_for_sorting(value):
    if not value:
        return 0.0

    try:
        normalized = str(value).replace("Z", "+00:00")
        dt = datetime.fromisoformat(normalized)

        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        else:
            dt = dt.astimezone(timezone.utc)

        return dt.timestamp()
    except Exception:
        return 0.0

def _latest_vital_for_user(user):
    latest_manual_row = (
        Vital.query
        .filter_by(user_id=user.id)
        .order_by(Vital.timestamp.desc())
        .first()
    )
    latest_manual = normalize_manual_vital(latest_manual_row) if latest_manual_row else None

    latest_wearable = None

    if user.patient_id is not None:
        try:
            wearable_rows = fetch_wearable_records_from_api(user.patient_id)
            wearable_records = [normalize_external_wearable(x) for x in wearable_rows]

            wearable_records = [
                x for x in wearable_records
                if x.get("patient_id") == user.patient_id
            ]

            wearable_records.sort(
                key=lambda x: _parse_iso_for_sorting(x.get("timestamp")),
                reverse=True,
            )

            if wearable_records:
                latest_wearable = wearable_records[0]
        except Exception:
            latest_wearable = None

    candidates = [x for x in [latest_manual, latest_wearable] if x is not None]
    if not candidates:
        return None

    candidates.sort(
        key=lambda x: _parse_iso_for_sorting(x.get("timestamp")),
        reverse=True,
    )
    return candidates[0]


def _next_med_for_user(user_id: int):
    meds = MedReminder.query.filter_by(user_id=user_id, enabled=True).all()
    if not meds:
        return None

    now = datetime.now()
    candidates = []

    for med in meds:
        time_str = (med.time_of_day or "").strip()
        if not time_str or ":" not in time_str:
            continue

        try:
            hh, mm = time_str.split(":")
            hour = int(hh)
            minute = int(mm)
        except Exception:
            continue

        candidate = now.replace(hour=hour, minute=minute, second=0, microsecond=0)
        if candidate < now:
            candidate = candidate + timedelta(days=1)

        candidates.append((candidate, med))

    if not candidates:
        return None

    candidates.sort(key=lambda x: x[0])
    next_dt, med = candidates[0]

    return {
        "id": med.id,
        "name": med.name,
        "dosage": med.dosage,
        "time_of_day": med.time_of_day,
        "next_at": to_iso_utc(next_dt),
    }


@bp.route("/api/dashboard/summary")
def dashboard_summary():
    user = get_api_user_from_request()
    if not user:
        return jsonify({"ok": False, "error": "unauthorized"}), 401

    latest_fall = (
        FallEvent.query
        .filter_by(user_id=user.id, deleted=False)
        .order_by(FallEvent.timestamp.desc())
        .first()
    )

    latest_vital = _latest_vital_for_user(user)
    next_med = _next_med_for_user(user.id)

    return jsonify({
        "ok": True,
        "latest_fall": None if not latest_fall else {
            "id": latest_fall.id,
            "timestamp": latest_fall.timestamp.isoformat() if latest_fall.timestamp else None,
            "reason": getattr(latest_fall, "reason", None) or "Fall detected",
        },
        "latest_vital": latest_vital,
        "next_med": next_med,
    })