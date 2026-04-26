import time
import requests
from flask import Blueprint, render_template, Response, jsonify, make_response
from flask_login import login_required

from services.camera import get_camera

bp = Blueprint("live", __name__)

# PI_BASE_URL = "http://192.168.2.80:8000" # LAN
PI_BASE_URL = "http://192.168.149.1:8000" # Direct Connection


# original html website
@bp.route("/live")
@login_required
def live_page():
    return render_template("live.html")


def gen_frames():
    cam = get_camera()
    while True:
        jpeg = cam.get_jpeg()
        if jpeg is None:
            time.sleep(0.05)
            continue
        yield (
            b"--frame\r\n"
            b"Content-Type: image/jpeg\r\n"
            b"Cache-Control: no-store\r\n\r\n" + jpeg + b"\r\n"
        )


@bp.route("/video_feed")
@login_required
def video_feed():
    return Response(gen_frames(), mimetype="multipart/x-mixed-replace; boundary=frame")


@bp.route("/snapshot")
@login_required
def snapshot():
    cam = get_camera()
    jpeg = cam.get_jpeg()
    if jpeg is None:
        return ("", 204)

    resp = make_response(jpeg)
    resp.headers["Content-Type"] = "image/jpeg"
    resp.headers["Cache-Control"] = "no-store, no-cache, must-revalidate, max-age=0"
    resp.headers["Pragma"] = "no-cache"
    return resp


@bp.route("/status")
@login_required
def status():
    cam = get_camera()
    return jsonify(cam.get_status())


# Flutter
@bp.route("/api/live/status")
def api_live_status():
    try:
        r = requests.get(f"{PI_BASE_URL}/api/follow/status", timeout=1.0)
        follow = r.json()
    except Exception as e:
        return jsonify({
            "online": False,
            "msg": f"follow status failed: {e}",
            "posture": "Unknown",
            "score": 0.0,
        })

    return jsonify({
        "online": True,
        "msg": "pi snapshot proxy ok",
        "posture": follow.get("posture", "Unknown"),
        "score": follow.get("score", 0.0),
        "follow_enabled": follow.get("follow_enabled", False),
        "follow_mode": follow.get("follow_mode", "full_follow"),
        "target_visible": follow.get("target_visible", False),
        "last_cmd": follow.get("last_cmd", "stop"),
    })


@bp.route("/api/live/snapshot")
def api_live_snapshot():
    try:
        r = requests.get(f"{PI_BASE_URL}/api/snapshot", timeout=1.5)
        if r.status_code != 200 or not r.content:
            return ("", 204)

        resp = make_response(r.content)
        resp.headers["Content-Type"] = "image/jpeg"
        resp.headers["Cache-Control"] = "no-store, no-cache, must-revalidate, max-age=0"
        resp.headers["Pragma"] = "no-cache"
        return resp
    except Exception:
        return ("", 204)
    

@bp.route("/api/live/stream")
def api_live_stream():
    return Response(gen_frames(), mimetype="multipart/x-mixed-replace; boundary=frame")