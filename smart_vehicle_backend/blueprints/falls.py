import os
from flask import Blueprint, render_template, send_from_directory, redirect, url_for, jsonify
from flask_login import login_required, current_user

from extensions import db
from models import FallEvent
from api_auth import get_api_user_from_request, get_token_from_request

bp = Blueprint("falls", __name__)

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
APP_DIR = os.path.dirname(BASE_DIR)
STORAGE_DIR = os.path.join(APP_DIR, "storage")
FALLS_DIR = os.path.join(STORAGE_DIR, "falls")


def _user_dir(uid: int):
    d = os.path.join(FALLS_DIR, f"u{uid}")
    os.makedirs(d, exist_ok=True)
    return d


def _safe_video_delete(uid: int, video_name: str):
    if not video_name:
      return True, "no video name"

    d = _user_dir(uid)
    name = os.path.basename(video_name)
    p = os.path.join(d, name)

    try:
        if os.path.exists(p):
            os.remove(p)
            return True, f"deleted: {name}"
        return True, f"file not found: {name}"
    except Exception as e:
        return False, f"failed to delete {name}: {e}"


@bp.route("/falls")
@login_required
def falls_page():
    uid = getattr(current_user, "id", None) or 1

    events = (
        FallEvent.query
        .filter_by(user_id=uid, deleted=False)
        .order_by(FallEvent.timestamp.desc())
        .limit(200)
        .all()
    )

    out = []
    for e in events:
        out.append({
            "id": e.id,
            "timestamp": e.timestamp,
            "reason": e.reason or "",
            "video_name": e.video_name or "",
        })

    return render_template("falls.html", events=out)


@bp.route("/falls/video/<int:eid>")
@login_required
def falls_video(eid: int):
    uid = getattr(current_user, "id", None) or 1
    e = FallEvent.query.filter_by(id=eid, user_id=uid, deleted=False).first()
    if not e or not e.video_name:
        return ("not found", 404)

    d = _user_dir(uid)
    name = os.path.basename(e.video_name)
    return send_from_directory(d, name, mimetype="video/mp4", as_attachment=False)


@bp.route("/api/falls/video/<int:eid>")
def falls_video_api(eid: int):
    user = get_api_user_from_request()
    if not user:
        return ("unauthorized", 401)

    e = FallEvent.query.filter_by(id=eid, user_id=user.id, deleted=False).first()
    if not e or not e.video_name:
        return ("not found", 404)

    d = _user_dir(user.id)
    name = os.path.basename(e.video_name)
    return send_from_directory(d, name, mimetype="video/mp4", as_attachment=False)


@bp.route("/falls/delete/<int:eid>", methods=["POST"])
@login_required
def falls_delete(eid: int):
    uid = getattr(current_user, "id", None) or 1
    e = FallEvent.query.filter_by(id=eid, user_id=uid, deleted=False).first()
    if not e:
        return redirect(url_for("falls.falls_page"))

    if e.video_name:
        ok, msg = _safe_video_delete(uid, e.video_name)
        if not ok:
            return (f"video delete failed: {msg}", 500)

    e.deleted = True
    db.session.commit()

    return redirect(url_for("falls.falls_page"))


@bp.route("/falls/admin/sync_from_disk")
@login_required
def falls_sync_from_disk():
    uid = getattr(current_user, "id", None) or 1
    d = _user_dir(uid)

    files = [f for f in os.listdir(d) if f.lower().endswith(".mp4")]
    files.sort(reverse=True)

    added = 0
    for f in files:
        exists = FallEvent.query.filter_by(user_id=uid, video_name=f).first()
        if exists:
            continue

        ev = FallEvent(
            user_id=uid,
            patient_id=getattr(current_user, "patient_id", None),
            reason="Video recorded",
            video_name=f,
        )
        db.session.add(ev)
        added += 1

    db.session.commit()
    return jsonify({"ok": True, "added": added, "total_disk": len(files)})


@bp.route("/api/falls")
def falls_api():
    user = get_api_user_from_request()
    if not user:
        return jsonify({"ok": False, "error": "unauthorized"}), 401

    token = get_token_from_request() or ""

    events = (
        FallEvent.query
        .filter_by(user_id=user.id, deleted=False)
        .order_by(FallEvent.timestamp.desc())
        .limit(200)
        .all()
    )

    out = []
    for e in events:
        video_url = None
        if e.video_name:
            video_url = url_for(
                "falls.falls_video_api",
                eid=e.id,
                token=token,
                _external=True,
            )

        out.append({
            "id": e.id,
            "timestamp": e.timestamp.isoformat() if e.timestamp else None,
            "reason": e.reason or "",
            "video_name": e.video_name or "",
            "video_url": video_url,
        })

    return jsonify(out)


@bp.route("/api/falls/<int:eid>")
def falls_api_detail(eid: int):
    user = get_api_user_from_request()
    if not user:
        return jsonify({"ok": False, "error": "unauthorized"}), 401

    token = get_token_from_request() or ""

    e = FallEvent.query.filter_by(id=eid, user_id=user.id, deleted=False).first()
    if not e:
        return jsonify({"ok": False, "error": "not found"}), 404

    video_url = None
    if e.video_name:
        video_url = url_for(
            "falls.falls_video_api",
            eid=e.id,
            token=token,
            _external=True,
        )

    return jsonify({
        "ok": True,
        "id": e.id,
        "timestamp": e.timestamp.isoformat() if e.timestamp else None,
        "reason": e.reason or "",
        "video_name": e.video_name or "",
        "video_url": video_url,
    })


@bp.route("/api/falls/<int:eid>", methods=["DELETE"])
def falls_api_delete(eid: int):
    user = get_api_user_from_request()
    if not user:
        return jsonify({"ok": False, "error": "unauthorized"}), 401

    e = FallEvent.query.filter_by(id=eid, user_id=user.id, deleted=False).first()
    if not e:
        return jsonify({"ok": False, "error": "not found"}), 404

    if e.video_name:
        ok, msg = _safe_video_delete(user.id, e.video_name)
        if not ok:
            return jsonify({
                "ok": False,
                "error": "video delete failed",
                "detail": msg,
            }), 500

    e.deleted = True
    db.session.commit()

    return jsonify({
        "ok": True,
        "message": "fall event deleted",
        "id": eid,
    })