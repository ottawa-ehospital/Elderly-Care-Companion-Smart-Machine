#!/usr/bin/python3
# coding=utf8

import sys
sys.path.append('/home/pi/TurboPi/')

import os
import json
import time
from flask import Flask, request, jsonify, send_file, Response
import HiwonderSDK.mecanum as mecanum
import HiwonderSDK.Board as Board
import HiwonderSDK.Sonar as Sonar
import yaml_handle

app = Flask(__name__)

car = mecanum.MecanumChassis()
sonar = Sonar.Sonar()
servo_data = yaml_handle.get_yaml_data(yaml_handle.servo_file_path)

SERVO1_CENTER = int(servo_data['servo1'])
SERVO2_CENTER = int(servo_data['servo2'])

# 左右手动范围
SERVO1_MIN = SERVO1_CENTER - 500
SERVO1_MAX = SERVO1_CENTER + 500

# 上下手动范围：放宽到 center
SERVO2_MIN = SERVO2_CENTER - 450
SERVO2_MAX = SERVO2_CENTER

servo_x = SERVO1_CENTER
servo_y = SERVO2_CENTER - 300

FOLLOW_STATE_PATH = "/home/pi/TurboPi/follow_state.json"
RUNTIME_STATUS_PATH = "/home/pi/TurboPi/follow_runtime.json"
SNAPSHOT_PATH = "/home/pi/TurboPi/latest_frame.jpg"


def clamp(v, lo, hi):
    return max(lo, min(hi, int(v)))


def stop_car():
    car.set_velocity(0, 90, 0)


def read_battery_voltage():
    candidates = [
        "getBatteryVoltage",
        "getBattery",
        "getBatteryLevel",
        "getVin",
        "getVcc",
    ]
    for name in candidates:
        fn = getattr(Board, name, None)
        if callable(fn):
            try:
                v = fn()
                if v is None:
                    continue
                v = float(v)
                if v > 100:
                    v = v / 1000.0
                return v
            except Exception:
                pass
    return None


def default_follow_state():
    return {
        "follow_enabled": False,
        "follow_mode": "full_follow",
        "manual_mode": True,
        "last_cmd": "stop",
        "updated_at": time.time(),
    }


def default_runtime_status():
    return {
        "target_visible": False,
        "target_locked": False,
        "target_lost": False,
        "posture": "Unknown",
        "score": 0.0,
        "servo_x": servo_x,
        "servo_y": servo_y,
        "distance_cm": None,
        "battery_voltage": None,
        "last_cmd": "stop",
        "manual_mode": True,
        "follow_mode": "full_follow",
        "follow_enabled": False,
        "fall_confirmed": False,
        "updated_at": time.time(),
    }


def atomic_write_json(path, data):
    tmp_path = path + ".tmp"
    with open(tmp_path, "w", encoding="utf-8") as f:
        json.dump(data, f)
    os.replace(tmp_path, path)


def read_follow_state():
    if not os.path.exists(FOLLOW_STATE_PATH):
        st = default_follow_state()
        write_follow_state(st)
        return st

    try:
        with open(FOLLOW_STATE_PATH, "r", encoding="utf-8") as f:
            data = json.load(f)
        if not isinstance(data, dict):
            raise ValueError("state is not dict")
        return data
    except Exception:
        st = default_follow_state()
        write_follow_state(st)
        return st


def write_follow_state(state):
    state["updated_at"] = time.time()
    atomic_write_json(FOLLOW_STATE_PATH, state)


def read_runtime_status():
    if not os.path.exists(RUNTIME_STATUS_PATH):
        rt = default_runtime_status()
        write_runtime_status(rt)
        return rt

    try:
        with open(RUNTIME_STATUS_PATH, "r", encoding="utf-8") as f:
            data = json.load(f)
        if not isinstance(data, dict):
            raise ValueError("runtime is not dict")
        return data
    except Exception:
        rt = default_runtime_status()
        write_runtime_status(rt)
        return rt


def write_runtime_status(state):
    state["updated_at"] = time.time()
    atomic_write_json(RUNTIME_STATUS_PATH, state)


@app.route("/api/control", methods=["POST"])
def api_control():
    data = request.get_json(force=True, silent=True) or {}
    cmd = str(data.get("cmd", "")).strip().lower()

    speed = 60
    turn_z = 0.40

    if cmd == "forward":
        car.set_velocity(speed, 90, 0)
    elif cmd == "backward":
        car.set_velocity(speed, 270, 0)
    elif cmd == "left":
        car.set_velocity(speed, 180, 0)
    elif cmd == "right":
        car.set_velocity(speed, 0, 0)
    elif cmd == "front_left":
        car.set_velocity(speed, 135, 0)
    elif cmd == "front_right":
        car.set_velocity(speed, 45, 0)
    elif cmd == "back_left":
        car.set_velocity(speed, 225, 0)
    elif cmd == "back_right":
        car.set_velocity(speed, 315, 0)
    elif cmd == "turn_left":
        car.set_velocity(0, 90, -turn_z)
    elif cmd == "turn_right":
        car.set_velocity(0, 90, turn_z)
    elif cmd == "stop":
        stop_car()
    else:
        return jsonify({"ok": False, "error": f"unknown cmd: {cmd}"}), 400

    st = read_follow_state()
    st["manual_mode"] = True
    st["follow_enabled"] = False
    st["last_cmd"] = cmd
    write_follow_state(st)

    rt = read_runtime_status()
    rt["manual_mode"] = True
    rt["follow_enabled"] = False
    rt["last_cmd"] = cmd
    write_runtime_status(rt)

    return jsonify({"ok": True, "cmd": cmd})


@app.route("/api/stop", methods=["POST"])
def api_stop():
    stop_car()

    st = read_follow_state()
    st["manual_mode"] = True
    st["follow_enabled"] = False
    st["last_cmd"] = "stop"
    write_follow_state(st)

    rt = read_runtime_status()
    rt["manual_mode"] = True
    rt["follow_enabled"] = False
    rt["last_cmd"] = "stop"
    write_runtime_status(rt)

    return jsonify({"ok": True})


@app.route("/api/gimbal", methods=["POST"])
def api_gimbal():
    global servo_x, servo_y

    data = request.get_json(force=True, silent=True) or {}
    pan = data.get("pan", None)
    tilt = data.get("tilt", None)

    if pan is not None:
        servo_x = clamp(int(pan), SERVO1_MIN, SERVO1_MAX)
        Board.setPWMServoPulse(1, servo_x, 80)

    if tilt is not None:
        servo_y = clamp(int(tilt), SERVO2_MIN, SERVO2_MAX)
        Board.setPWMServoPulse(2, servo_y, 80)

    st = read_follow_state()
    st["manual_mode"] = True
    st["follow_enabled"] = False
    st["last_cmd"] = "manual_gimbal"
    write_follow_state(st)

    rt = read_runtime_status()
    rt["manual_mode"] = True
    rt["follow_enabled"] = False
    rt["servo_x"] = servo_x
    rt["servo_y"] = servo_y
    rt["last_cmd"] = "manual_gimbal"
    write_runtime_status(rt)

    return jsonify({
        "ok": True,
        "pan": servo_x,
        "tilt": servo_y,
    })


@app.route("/api/gimbal/center", methods=["POST"])
def api_gimbal_center():
    global servo_x, servo_y

    servo_x = SERVO1_CENTER
    servo_y = SERVO2_CENTER - 150

    Board.setPWMServoPulse(1, servo_x, 300)
    Board.setPWMServoPulse(2, servo_y, 300)

    st = read_follow_state()
    st["manual_mode"] = True
    st["follow_enabled"] = False
    st["last_cmd"] = "gimbal_center"
    write_follow_state(st)

    rt = read_runtime_status()
    rt["manual_mode"] = True
    rt["follow_enabled"] = False
    rt["servo_x"] = servo_x
    rt["servo_y"] = servo_y
    rt["last_cmd"] = "gimbal_center"
    write_runtime_status(rt)

    return jsonify({
        "ok": True,
        "pan": servo_x,
        "tilt": servo_y,
    })


@app.route("/api/sensors", methods=["GET"])
def api_sensors():
    try:
        distance_cm = sonar.getDistance() / 10.0
    except Exception:
        distance_cm = None

    battery_voltage = read_battery_voltage()

    return jsonify({
        "ok": True,
        "distance_cm": distance_cm,
        "battery_voltage": battery_voltage,
    })


@app.route("/api/follow/start", methods=["POST"])
def api_follow_start():
    data = request.get_json(force=True, silent=True) or {}
    mode = str(data.get("mode", "full_follow")).strip()

    if mode not in ("full_follow", "gimbal_only"):
        return jsonify({"ok": False, "error": "invalid mode"}), 400

    st = read_follow_state()
    st["manual_mode"] = False
    st["follow_enabled"] = True
    st["follow_mode"] = mode
    st["last_cmd"] = "follow_start"
    write_follow_state(st)

    rt = read_runtime_status()
    rt["manual_mode"] = False
    rt["follow_enabled"] = True
    rt["follow_mode"] = mode
    rt["last_cmd"] = "follow_start"
    write_runtime_status(rt)

    return jsonify({
        "ok": True,
        "follow_enabled": True,
        "follow_mode": mode,
    })


@app.route("/api/follow/mode", methods=["POST"])
def api_follow_mode():
    data = request.get_json(force=True, silent=True) or {}
    mode = str(data.get("mode", "full_follow")).strip()

    if mode not in ("full_follow", "gimbal_only"):
        return jsonify({"ok": False, "error": "invalid mode"}), 400

    st = read_follow_state()
    st["follow_mode"] = mode
    st["last_cmd"] = "follow_mode"
    write_follow_state(st)

    rt = read_runtime_status()
    rt["follow_mode"] = mode
    rt["last_cmd"] = "follow_mode"
    write_runtime_status(rt)

    return jsonify({
        "ok": True,
        "follow_enabled": bool(st.get("follow_enabled", False)),
        "follow_mode": mode,
    })


@app.route("/api/follow/stop", methods=["POST"])
def api_follow_stop():
    stop_car()

    st = read_follow_state()
    st["manual_mode"] = True
    st["follow_enabled"] = False
    st["last_cmd"] = "follow_stop"
    write_follow_state(st)

    rt = read_runtime_status()
    rt["manual_mode"] = True
    rt["follow_enabled"] = False
    rt["last_cmd"] = "follow_stop"
    write_runtime_status(rt)

    return jsonify({
        "ok": True,
        "follow_enabled": False,
        "follow_mode": st.get("follow_mode", "full_follow"),
    })


@app.route("/api/follow/status", methods=["GET"])
def api_follow_status():
    st = read_follow_state()
    rt = read_runtime_status()

    try:
        distance_cm = sonar.getDistance() / 10.0
    except Exception:
        distance_cm = rt.get("distance_cm")

    battery_voltage = read_battery_voltage()
    if battery_voltage is None:
        battery_voltage = rt.get("battery_voltage")

    return jsonify({
        "ok": True,
        "follow_enabled": bool(st.get("follow_enabled", False)),
        "manual_mode": bool(st.get("manual_mode", True)),
        "follow_mode": st.get("follow_mode", "full_follow"),
        "last_cmd": rt.get("last_cmd", st.get("last_cmd", "stop")),
        "updated_at": max(
            float(st.get("updated_at", 0) or 0),
            float(rt.get("updated_at", 0) or 0),
        ),
        "target_visible": bool(rt.get("target_visible", False)),
        "target_locked": bool(rt.get("target_locked", False)),
        "target_lost": bool(rt.get("target_lost", False)),
        "posture": rt.get("posture", "Unknown"),
        "score": float(rt.get("score", 0.0) or 0.0),
        "servo_x": rt.get("servo_x", servo_x),
        "servo_y": rt.get("servo_y", servo_y),
        "distance_cm": distance_cm,
        "battery_voltage": battery_voltage,
        "fall_confirmed": bool(rt.get("fall_confirmed", False)),
    })


@app.route("/api/snapshot", methods=["GET"])
def api_snapshot():
    if not os.path.exists(SNAPSHOT_PATH):
        return ("no snapshot", 404)
    return send_file(SNAPSHOT_PATH, mimetype="image/jpeg")


def mjpeg_generator():
    while True:
        try:
            if os.path.exists(SNAPSHOT_PATH):
                with open(SNAPSHOT_PATH, "rb") as f:
                    jpg = f.read()
                if jpg:
                    yield (
                        b"--frame\r\n"
                        b"Content-Type: image/jpeg\r\n"
                        b"Cache-Control: no-store\r\n\r\n" + jpg + b"\r\n"
                    )
        except Exception:
            pass

        time.sleep(0.06)


@app.route("/api/stream", methods=["GET"])
def api_stream():
    return Response(
        mjpeg_generator(),
        mimetype="multipart/x-mixed-replace; boundary=frame"
    )


@app.route("/api/ping", methods=["GET"])
def api_ping():
    return jsonify({"ok": True, "service": "pi_robot_api"})


if __name__ == "__main__":
    print("Starting pi_robot_api on 0.0.0.0:8000", flush=True)
    app.run(host="0.0.0.0", port=8000, threaded=True)

