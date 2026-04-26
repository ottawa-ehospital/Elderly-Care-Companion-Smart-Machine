#!/usr/bin/python3
# coding=utf8

import sys
sys.path.append('/home/pi/TurboPi/')

import os
import json
import cv2
import time
import signal
import threading
import numpy as np

import Camera
import yaml_handle
import HiwonderSDK.Board as Board
import HiwonderSDK.PID as PID
import HiwonderSDK.Sonar as Sonar
import HiwonderSDK.mecanum as mecanum

from pose_fall_pipeline import PoseFallPipeline


if sys.version_info.major == 2:
    print('Please run this program with python3!')
    sys.exit(0)


HEADLESS = not bool(os.environ.get("DISPLAY"))

latest_frame_jpg = None
frame_lock = threading.Lock()

FOLLOW_STATE_PATH = "/home/pi/TurboPi/follow_state.json"
RUNTIME_STATUS_PATH = "/home/pi/TurboPi/follow_runtime.json"
SNAPSHOT_PATH = "/home/pi/TurboPi/latest_frame.jpg"
last_runtime_write_ts = 0.0

manual_mode = True
follow_mode = "full_follow"


def atomic_write_json(path, data):
    try:
        tmp = path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(data, f)
        os.replace(tmp, path)
    except Exception:
        pass


def ensure_follow_state_file():
    try:
        if not os.path.exists(FOLLOW_STATE_PATH):
            with open(FOLLOW_STATE_PATH, "w", encoding="utf-8") as f:
                json.dump({
                    "follow_enabled": False,
                    "follow_mode": "full_follow",
                    "manual_mode": True,
                    "last_cmd": "stop",
                    "updated_at": time.time(),
                }, f)
    except Exception:
        pass


def ensure_runtime_files():
    global servo_x, servo_y
    try:
        if not os.path.exists(RUNTIME_STATUS_PATH):
            atomic_write_json(RUNTIME_STATUS_PATH, {
                "target_visible": False,
                "target_locked": False,
                "target_lost": False,
                "posture": "Unknown",
                "score": 0.0,
                "servo_x": int(servo_x) if 'servo_x' in globals() else 0,
                "servo_y": int(servo_y) if 'servo_y' in globals() else 0,
                "distance_cm": None,
                "battery_voltage": None,
                "last_cmd": "stop",
                "manual_mode": True,
                "follow_mode": "full_follow",
                "follow_enabled": False,
                "fall_confirmed": False,
                "updated_at": time.time(),
            })
    except Exception:
        pass


def read_follow_state():
    global manual_mode, follow_mode

    try:
        if not os.path.exists(FOLLOW_STATE_PATH):
            return

        with open(FOLLOW_STATE_PATH, "r", encoding="utf-8") as f:
            st = json.load(f)

        manual_mode = bool(st.get("manual_mode", True))
        follow_mode = str(st.get("follow_mode", "full_follow")).strip()
        if follow_mode not in ("full_follow", "gimbal_only"):
            follow_mode = "full_follow"
    except Exception:
        pass


def read_runtime_file():
    try:
        if not os.path.exists(RUNTIME_STATUS_PATH):
            return None
        with open(RUNTIME_STATUS_PATH, "r", encoding="utf-8") as f:
            data = json.load(f)
        if isinstance(data, dict):
            return data
    except Exception:
        pass
    return None


def write_runtime_status():
    data = {
        "target_visible": bool(target_visible),
        "target_locked": bool(target_locked),
        "target_lost": bool(target_lost),
        "posture": str(last_posture),
        "score": float(last_person_score),
        "servo_x": int(servo_x),
        "servo_y": int(servo_y),
        "distance_cm": float(obstacle_distance) if obstacle_distance is not None else None,
        "battery_voltage": float(battery_voltage) if battery_voltage is not None else None,
        "last_cmd": str(last_move_cmd),
        "manual_mode": bool(manual_mode),
        "follow_mode": str(follow_mode),
        "follow_enabled": (not manual_mode),
        "fall_confirmed": bool(fall_confirmed),
        "updated_at": time.time(),
    }
    atomic_write_json(RUNTIME_STATUS_PATH, data)


try:
    def _quiet_buzzer(*args, **kwargs):
        return
    Board.setBuzzer = _quiet_buzzer
except Exception:
    pass


car = mecanum.MecanumChassis()
sonar = Sonar.Sonar()
servo_data = yaml_handle.get_yaml_data(yaml_handle.servo_file_path)

# servo1 = 左右
# servo2 = 上下
SERVO1_CENTER = int(servo_data['servo1'])
SERVO1_START = SERVO1_CENTER
SERVO1_MIN = SERVO1_CENTER - 500
SERVO1_MAX = SERVO1_CENTER + 500

SERVO2_CENTER = int(servo_data['servo2'])
SERVO2_START = SERVO2_CENTER - 300

# 自动跟随用的上下范围：保持原逻辑
SERVO2_MIN = SERVO2_CENTER - 450
SERVO2_MAX = SERVO2_CENTER - 300

# 手动云台同步用的上下范围：放宽，不影响自动跟随
MANUAL_SERVO2_MIN = SERVO2_CENTER - 450
MANUAL_SERVO2_MAX = SERVO2_CENTER

servo_x = SERVO1_START
servo_y = SERVO2_START

size = (320, 240)
IMG_W, IMG_H = size
DISPLAY_SIZE = (480, 360)

__isRunning = False

target_locked = False
target_lost = False
target_visible = False
track_box = None

center_x = -1
center_y = -1
box_w = 0
box_h = 0

aim_x = -1
aim_y = -1

last_seen_cx = 0.5
last_seen_cy = 0.5
last_seen_h = 0
last_seen_ts = 0.0

startup_wait_until = 0.0
search_mode = False
search_direction = -0.30

TARGET_HOLD_SEC = 0.80
SEARCH_DELAY_AFTER_LOST_SEC = 1.00

fall_pipeline = None
fall_confirmed = False
last_fall_ts = 0.0
last_posture = "Unknown"
last_person_score = 0.0

distance_data = []
obstacle_distance = 999.0

OBSTACLE_THRESHOLD = 30.0

car_en = False
last_move_cmd = "stop"

recover_until = 0.0

avoid_stage = 0
avoid_side = "left"
avoid_until = 0.0

servo_x_pid = PID.PID(P=0.060, I=0.0001, D=0.0005)
servo_y_pid = PID.PID(P=0.055, I=0.0001, D=0.0005)

smooth_cx = None
smooth_aim_y = None
smooth_h = None

TARGET_H = 200
SERVO_X_DEAD = 10
SERVO_Y_DEAD = 8

CHASSIS_X_DEAD = 28
CHASSIS_H_DEAD = 12
CHASSIS_TURN_X = 70

FORWARD_SPEED_MIN = 45
FORWARD_SPEED_MAX = 65

BACKWARD_SPEED_MIN = 45
BACKWARD_SPEED_MAX = 60

STRAFE_SPEED_MIN = 50
STRAFE_SPEED_MAX = 65

SEARCH_TURN_Z = 0.30
TRACK_TURN_Z_MIN = 0.35
TRACK_TURN_Z_MAX = 0.42

H_ERR_CLAMP = 30.0
X_ERR_CLAMP = 100.0

CTRL_DT = 0.03

debug_counter = 0

battery_voltage = None
battery_last_read_ts = 0.0

forward_cmd_start_ts = None
forward_cmd_ref_h = None
backward_cmd_start_ts = None
backward_cmd_ref_h = None

backward_escape_toggle = 1

POSE_INTERVAL = 3
last_overlay = None
last_status = None


def clamp(v, lo, hi):
    return max(lo, min(hi, int(v)))


def lowpass(prev, cur, alpha=0.18):
    if prev is None:
        return float(cur)
    return (1.0 - alpha) * float(prev) + alpha * float(cur)


def initMove():
    global servo_x, servo_y
    servo_x = SERVO1_START
    servo_y = SERVO2_START
    Board.setPWMServoPulse(1, servo_x, 800)
    Board.setPWMServoPulse(2, servo_y, 800)


def car_stop():
    global last_move_cmd
    car.set_velocity(0, 90, 0)
    last_move_cmd = "stop"


def norm01(v, vmax):
    x = abs(v) / float(vmax)
    if x > 1.0:
        x = 1.0
    return x


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


def sync_manual_gimbal_from_runtime():
    global servo_x, servo_y, last_move_cmd

    rt = read_runtime_file()
    if not rt:
        return

    cmd = str(rt.get("last_cmd", "")).strip()
    if cmd not in {"manual_gimbal", "gimbal_center"}:
        return

    rx = rt.get("servo_x")
    ry = rt.get("servo_y")

    changed = False

    try:
        if rx is not None:
            rx = clamp(int(rx), SERVO1_MIN, SERVO1_MAX)
            if rx != servo_x:
                servo_x = rx
                changed = True
    except Exception:
        pass

    try:
        if ry is not None:
            ry = clamp(int(ry), MANUAL_SERVO2_MIN, MANUAL_SERVO2_MAX)
            if ry != servo_y:
                servo_y = ry
                changed = True
    except Exception:
        pass

    if changed:
        Board.setPWMServoPulse(1, servo_x, 50)
        Board.setPWMServoPulse(2, servo_y, 50)
        last_move_cmd = cmd


def reset_state():
    global target_locked, target_lost, target_visible, track_box
    global center_x, center_y, box_w, box_h, aim_x, aim_y
    global last_seen_cx, last_seen_cy, last_seen_h, last_seen_ts
    global search_mode
    global fall_confirmed, last_fall_ts, last_posture, last_person_score
    global distance_data, obstacle_distance
    global recover_until, startup_wait_until
    global avoid_stage, avoid_side, avoid_until
    global smooth_cx, smooth_aim_y, smooth_h
    global forward_cmd_start_ts, forward_cmd_ref_h
    global backward_cmd_start_ts, backward_cmd_ref_h

    target_locked = False
    target_lost = False
    target_visible = False
    track_box = None

    center_x = -1
    center_y = -1
    box_w = 0
    box_h = 0
    aim_x = -1
    aim_y = -1

    last_seen_cx = 0.5
    last_seen_cy = 0.5
    last_seen_h = 0
    last_seen_ts = 0.0

    search_mode = False

    fall_confirmed = False
    last_fall_ts = 0.0
    last_posture = "Unknown"
    last_person_score = 0.0

    distance_data = []
    obstacle_distance = 999.0

    recover_until = 0.0
    startup_wait_until = 0.0

    avoid_stage = 0
    avoid_side = "left"
    avoid_until = 0.0

    smooth_cx = None
    smooth_aim_y = None
    smooth_h = None

    forward_cmd_start_ts = None
    forward_cmd_ref_h = None
    backward_cmd_start_ts = None
    backward_cmd_ref_h = None

    servo_x_pid.clear()
    servo_y_pid.clear()


def update_target_from_bbox(bbox):
    global track_box, center_x, center_y, box_w, box_h
    global aim_x, aim_y, target_visible, target_locked, target_lost
    global last_seen_cx, last_seen_cy, last_seen_h, last_seen_ts
    global smooth_cx, smooth_aim_y, smooth_h

    x1, y1, x2, y2 = bbox
    w = max(1, x2 - x1)
    h = max(1, y2 - y1)

    cx = x1 + w // 2
    cy = y1 + h // 2
    butt_y = y1 + int(h * 0.58)

    smooth_cx = lowpass(smooth_cx, cx, alpha=0.18)
    smooth_aim_y = lowpass(smooth_aim_y, butt_y, alpha=0.18)
    smooth_h = lowpass(smooth_h, h, alpha=0.15)

    cx_s = int(smooth_cx)
    butt_y_s = int(smooth_aim_y)
    h_s = int(smooth_h)

    track_box = (x1, y1, x2, y2)
    center_x = cx_s
    center_y = cy
    box_w = w
    box_h = h_s
    aim_x = cx_s
    aim_y = butt_y_s

    target_visible = True
    target_locked = True
    target_lost = False

    last_seen_cx = cx_s / float(IMG_W)
    last_seen_cy = butt_y_s / float(IMG_H)
    last_seen_h = h_s
    last_seen_ts = time.time()


def read_sonar_distance():
    global distance_data, obstacle_distance
    try:
        dist = sonar.getDistance() / 10.0
    except Exception:
        return obstacle_distance

    if dist <= 0 or dist > 500:
        return obstacle_distance

    distance_data.append(dist)
    if len(distance_data) > 5:
        distance_data.pop(0)

    obstacle_distance = float(np.median(np.array(distance_data, dtype=np.float32)))
    return obstacle_distance


def choose_avoid_side():
    if last_seen_cx < 0.48:
        return "left"
    elif last_seen_cx > 0.52:
        return "right"
    return "left"


def begin_avoid():
    global avoid_stage, avoid_side, avoid_until
    avoid_side = choose_avoid_side()
    avoid_stage = 1
    avoid_until = time.time() + 0.28


def begin_backward_escape():
    global avoid_stage, avoid_side, avoid_until, backward_escape_toggle
    avoid_side = "left" if backward_escape_toggle > 0 else "right"
    backward_escape_toggle *= -1
    avoid_stage = 11
    avoid_until = time.time() + 0.24


def run_avoidance(now):
    global avoid_stage, avoid_until, last_move_cmd

    if avoid_stage == 0:
        return False

    if avoid_stage == 1:
        if avoid_side == "left":
            car.set_velocity(0, 90, -0.40)
            last_move_cmd = "avoid_turn_left"
        else:
            car.set_velocity(0, 90, 0.40)
            last_move_cmd = "avoid_turn_right"

        if now >= avoid_until:
            avoid_stage = 2
            avoid_until = now + 0.32
        return True

    if avoid_stage == 2:
        if avoid_side == "left":
            car.set_velocity(60, 180, 0)
            last_move_cmd = "avoid_shift_left"
        else:
            car.set_velocity(60, 0, 0)
            last_move_cmd = "avoid_shift_right"

        if now >= avoid_until:
            avoid_stage = 3
            avoid_until = now + 0.36
        return True

    if avoid_stage == 3:
        if avoid_side == "left":
            car.set_velocity(55, 135, 0)
            last_move_cmd = "avoid_left_front"
        else:
            car.set_velocity(55, 45, 0)
            last_move_cmd = "avoid_right_front"

        if now >= avoid_until:
            avoid_stage = 0
            car_stop()
        return True

    if avoid_stage == 11:
        if avoid_side == "left":
            car.set_velocity(0, 90, -0.35)
            last_move_cmd = "back_escape_turn_left"
        else:
            car.set_velocity(0, 90, 0.35)
            last_move_cmd = "back_escape_turn_right"

        if now >= avoid_until:
            avoid_stage = 12
            avoid_until = now + 0.25
        return True

    if avoid_stage == 12:
        if avoid_side == "left":
            car.set_velocity(55, 180, 0)
            last_move_cmd = "back_escape_shift_left"
        else:
            car.set_velocity(55, 0, 0)
            last_move_cmd = "back_escape_shift_right"

        if now >= avoid_until:
            avoid_stage = 0
            car_stop()
        return True

    avoid_stage = 0
    return False


def draw_status(frame):
    if track_box is not None:
        x1, y1, x2, y2 = track_box
        cv2.rectangle(frame, (x1, y1), (x2, y2), (0, 255, 0), 2)
        cv2.circle(frame, (center_x, center_y), 4, (0, 255, 255), -1)
        if aim_x != -1 and aim_y != -1:
            cv2.circle(frame, (aim_x, aim_y), 5, (255, 0, 255), -1)

    err_h_show = TARGET_H - box_h if box_h > 0 else 0
    batt_text = f"{battery_voltage:.2f}V" if battery_voltage is not None else "N/A"

    txt1 = f"locked={target_locked} lost={target_lost} visible={target_visible} search={search_mode}"
    txt2 = f"h={box_h} target_h={TARGET_H} err_h={err_h_show}"
    txt3 = f"score={last_person_score:.2f} posture={last_posture} battery={batt_text}"
    txt4 = f"dist={obstacle_distance:.1f}cm obstacle_th={OBSTACLE_THRESHOLD:.1f}"
    txt5 = f"cmd={last_move_cmd} mode={'MANUAL' if manual_mode else follow_mode} servo1={servo_x} servo2={servo_y}"

    cv2.putText(frame, txt1, (8, 18), cv2.FONT_HERSHEY_SIMPLEX, 0.45, (0, 255, 0), 1)
    cv2.putText(frame, txt2, (8, 38), cv2.FONT_HERSHEY_SIMPLEX, 0.45, (0, 255, 0), 1)
    cv2.putText(frame, txt3, (8, 58), cv2.FONT_HERSHEY_SIMPLEX, 0.45, (0, 255, 0), 1)
    cv2.putText(frame, txt4, (8, 78), cv2.FONT_HERSHEY_SIMPLEX, 0.45, (0, 255, 0), 1)
    cv2.putText(frame, txt5, (8, 98), cv2.FONT_HERSHEY_SIMPLEX, 0.45, (0, 255, 0), 1)

    if target_lost:
        cv2.putText(frame, "TARGET LOST", (8, 122),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 0, 255), 2)

    if fall_confirmed:
        cv2.putText(frame, "FALL DETECTED", (8, 146),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 0, 255), 2)

    return frame


def init_fall_pipeline():
    global fall_pipeline
    fall_pipeline = PoseFallPipeline(
        model_path='/home/pi/TurboPi/pose_landmarker_full.task',
        person_score_thresh=0.60
    )
    print("[INFO] PoseFallPipeline loaded.", flush=True)


def move():
    global servo_x, servo_y, car_en, search_mode, last_move_cmd
    global target_locked, target_visible, startup_wait_until, recover_until
    global debug_counter
    global battery_voltage, battery_last_read_ts
    global forward_cmd_start_ts, forward_cmd_ref_h
    global backward_cmd_start_ts, backward_cmd_ref_h

    while True:
        read_follow_state()

        if not __isRunning:
            if car_en:
                car_stop()
                car_en = False
            time.sleep(CTRL_DT)
            continue

        now = time.time()

        if now < recover_until:
            time.sleep(CTRL_DT)
            continue

        if now - battery_last_read_ts > 1.0:
            battery_last_read_ts = now
            battery_voltage = read_battery_voltage()

        dist_cm = read_sonar_distance()

        if now < startup_wait_until:
            car_stop()
            last_move_cmd = "startup_freeze"
            time.sleep(CTRL_DT)
            continue

        if avoid_stage != 0:
            run_avoidance(now)
            car_en = True
            time.sleep(CTRL_DT)
            continue

        if manual_mode:
            sync_manual_gimbal_from_runtime()

            if car_en:
                car_stop()
                car_en = False

            last_move_cmd = "manual_mode_wait"
            time.sleep(CTRL_DT)
            continue

        if (not target_locked) or (not target_visible):
            search_mode = True

            if follow_mode == "gimbal_only":
                car_stop()
                last_move_cmd = "gimbal_only_wait_target"
                car_en = False
                time.sleep(CTRL_DT)
                continue

            if last_seen_ts > 0 and (now - last_seen_ts) < SEARCH_DELAY_AFTER_LOST_SEC:
                car_stop()
                last_move_cmd = "wait_target_return"
                car_en = False
                time.sleep(CTRL_DT)
                continue

            if dist_cm < OBSTACLE_THRESHOLD:
                begin_avoid()
                time.sleep(CTRL_DT)
                continue

            car.set_velocity(0, 90, search_direction)
            last_move_cmd = "search"
            car_en = True
            time.sleep(CTRL_DT)
            continue

        search_mode = False

        tx = aim_x if aim_x != -1 else center_x
        ty = aim_y if aim_y != -1 else center_y
        h = box_h

        if tx == -1 or ty == -1 or h <= 0:
            car_stop()
            time.sleep(CTRL_DT)
            continue

        tx_servo = tx
        ty_servo = ty

        if abs(tx_servo - IMG_W / 2.0) < SERVO_X_DEAD:
            tx_servo = IMG_W / 2.0
        if abs(ty_servo - IMG_H / 2.0) < SERVO_Y_DEAD:
            ty_servo = IMG_H / 2.0

        servo_x_pid.SetPoint = IMG_W / 2.0
        servo_x_pid.update(tx_servo)
        servo_x += int(servo_x_pid.output)
        servo_x = clamp(servo_x, SERVO1_MIN, SERVO1_MAX)

        servo_y_pid.SetPoint = IMG_H / 2.0
        servo_y_pid.update(ty_servo)
        servo_y -= int(servo_y_pid.output)
        servo_y = clamp(servo_y, SERVO2_MIN, SERVO2_MAX)

        Board.setPWMServoPulse(1, servo_x, 20)
        Board.setPWMServoPulse(2, servo_y, 20)

        if follow_mode == "gimbal_only":
            car_stop()
            last_move_cmd = "gimbal_only"
            car_en = False
            time.sleep(CTRL_DT)
            continue

        if last_posture == "Sitting":
            car_stop()
            last_move_cmd = "servo_only_sitting"
            car_en = False
            time.sleep(CTRL_DT)
            continue

        if dist_cm < OBSTACLE_THRESHOLD:
            begin_avoid()
            time.sleep(CTRL_DT)
            continue

        err_x = tx - IMG_W / 2.0
        err_h = TARGET_H - h

        nx = norm01(err_x, X_ERR_CLAMP)
        nh = norm01(err_h, H_ERR_CLAMP)

        linear_speed = 0
        direction = 90

        if err_h > CHASSIS_H_DEAD:
            linear_speed = int(FORWARD_SPEED_MIN + (FORWARD_SPEED_MAX - FORWARD_SPEED_MIN) * nh)
            direction = 90
        elif err_h < -CHASSIS_H_DEAD:
            linear_speed = int(BACKWARD_SPEED_MIN + (BACKWARD_SPEED_MAX - BACKWARD_SPEED_MIN) * nh)
            direction = 270

        strafe_speed = 0
        strafe_angle = None
        angular_z = 0.0

        if err_x < -CHASSIS_X_DEAD:
            if abs(err_x) < CHASSIS_TURN_X:
                strafe_speed = int(STRAFE_SPEED_MIN + (STRAFE_SPEED_MAX - STRAFE_SPEED_MIN) * nx)
                strafe_angle = 180
            else:
                angular_z = -(TRACK_TURN_Z_MIN + (TRACK_TURN_Z_MAX - TRACK_TURN_Z_MIN) * nx)

        elif err_x > CHASSIS_X_DEAD:
            if abs(err_x) < CHASSIS_TURN_X:
                strafe_speed = int(STRAFE_SPEED_MIN + (STRAFE_SPEED_MAX - STRAFE_SPEED_MIN) * nx)
                strafe_angle = 0
            else:
                angular_z = (TRACK_TURN_Z_MIN + (TRACK_TURN_Z_MAX - TRACK_TURN_Z_MIN) * nx)

        if abs(angular_z) > 0.01 and linear_speed > 0:
            car.set_velocity(linear_speed, direction, angular_z)
            last_move_cmd = "forward_turn_track" if direction == 90 else "backward_turn_track"
            car_en = True

        elif abs(angular_z) > 0.01:
            car.set_velocity(0, 90, angular_z)
            last_move_cmd = "turn_track"
            car_en = True

        elif linear_speed > 0 and strafe_speed > 0:
            if direction == 90 and strafe_angle == 180:
                car.set_velocity(max(linear_speed, strafe_speed), 135, 0)
                last_move_cmd = "front_left_track"
            elif direction == 90 and strafe_angle == 0:
                car.set_velocity(max(linear_speed, strafe_speed), 45, 0)
                last_move_cmd = "front_right_track"
            elif direction == 270 and strafe_angle == 180:
                car.set_velocity(max(linear_speed, strafe_speed), 225, 0)
                last_move_cmd = "back_left_track"
            elif direction == 270 and strafe_angle == 0:
                car.set_velocity(max(linear_speed, strafe_speed), 315, 0)
                last_move_cmd = "back_right_track"
            car_en = True

        elif linear_speed > 0:
            car.set_velocity(linear_speed, direction, 0)
            last_move_cmd = "forward_track" if direction == 90 else "backward_track"
            car_en = True

        elif strafe_speed > 0:
            car.set_velocity(strafe_speed, strafe_angle, 0)
            last_move_cmd = "left_track" if strafe_angle == 180 else "right_track"
            car_en = True

        else:
            car_stop()
            car_en = False

        if car_en and linear_speed > 0 and direction == 90:
            if forward_cmd_start_ts is None:
                forward_cmd_start_ts = now
                forward_cmd_ref_h = h
            else:
                dt = now - forward_cmd_start_ts
                dh = abs(h - (forward_cmd_ref_h if forward_cmd_ref_h is not None else h))
                if dt > 0.9 and dh < 4:
                    print("[WARN] forward stuck -> avoid", flush=True)
                    begin_avoid()
                    recover_until = now + 0.3
                    forward_cmd_start_ts = None
                    forward_cmd_ref_h = None
            backward_cmd_start_ts = None
            backward_cmd_ref_h = None

        elif car_en and linear_speed > 0 and direction == 270:
            if backward_cmd_start_ts is None:
                backward_cmd_start_ts = now
                backward_cmd_ref_h = h
            else:
                dt = now - backward_cmd_start_ts
                dh = abs(h - (backward_cmd_ref_h if backward_cmd_ref_h is not None else h))
                if dt > 0.85 and dh < 3:
                    print("[WARN] backward stuck -> escape", flush=True)
                    begin_backward_escape()
                    recover_until = now + 0.25
                    backward_cmd_start_ts = None
                    backward_cmd_ref_h = None
            forward_cmd_start_ts = None
            forward_cmd_ref_h = None

        else:
            forward_cmd_start_ts = None
            forward_cmd_ref_h = None
            backward_cmd_start_ts = None
            backward_cmd_ref_h = None

        debug_counter += 1
        if debug_counter % 15 == 0:
            print(
                f"[DEBUG] h={h}, target={TARGET_H}, err_h={err_h}, "
                f"err_x={err_x:.1f}, dist={dist_cm:.1f}, posture={last_posture}, "
                f"manual={manual_mode}, follow_mode={follow_mode}, cmd={last_move_cmd}",
                flush=True
            )

        time.sleep(CTRL_DT)


th = threading.Thread(target=move)
th.daemon = True
th.start()


def init():
    print("FollowPerson Init", flush=True)
    ensure_follow_state_file()
    ensure_runtime_files()
    reset_state()
    initMove()
    init_fall_pipeline()


def start():
    global __isRunning, startup_wait_until
    ensure_follow_state_file()
    ensure_runtime_files()
    reset_state()
    __isRunning = True
    startup_wait_until = time.time() + 6.0
    print("FollowPerson Start", flush=True)


def stop():
    global __isRunning
    __isRunning = False
    car_stop()
    initMove()
    print("FollowPerson Stop", flush=True)


def exit_app():
    global __isRunning
    __isRunning = False
    car_stop()
    initMove()
    print("FollowPerson Exit", flush=True)


def manual_stop(signum, frame):
    print('关闭中...', flush=True)
    exit_app()


if __name__ == '__main__':
    init()
    start()

    camera = Camera.Camera(resolution=size)
    camera.camera_open(correction=False)

    signal.signal(signal.SIGINT, manual_stop)

    frame_id = 0
    start_wall = time.time()

    while __isRunning:
        img = camera.frame
        if img is None:
            if target_locked and (time.time() - last_seen_ts) > TARGET_HOLD_SEC:
                target_visible = False
                target_lost = True
                target_locked = False
                track_box = None
                center_x, center_y = -1, -1
                aim_x, aim_y = -1, -1
            time.sleep(0.01)
            continue

        frame = img.copy()
        frame_id += 1
        ts_ms = int((time.time() - start_wall) * 1000)

        if frame_id % POSE_INTERVAL == 0 or last_overlay is None or last_status is None:
            overlay, status = fall_pipeline.process(frame, ts_ms)
            last_overlay = overlay.copy()
            last_status = status.copy()
        else:
            overlay = frame.copy()
            status = last_status.copy()

        last_posture = str(status.get("posture", "Unknown"))
        last_person_score = float(status.get("score", 0.0))

        has_person = bool(status.get("has_person", False))
        bbox = status.get("bbox", None)

        if has_person and bbox is not None:
            update_target_from_bbox(bbox)
            if track_box is not None:
                x1, y1, x2, y2 = track_box
                cv2.rectangle(overlay, (x1, y1), (x2, y2), (255, 255, 255), 2)
        else:
            if target_locked and (time.time() - last_seen_ts) > TARGET_HOLD_SEC:
                target_locked = False
                target_lost = True
                target_visible = False
                track_box = None
                center_x, center_y = -1, -1
                aim_x, aim_y = -1, -1
                print("[WARN] target lost", flush=True)

        new_fall = bool(status.get("fall_event", False)) or bool(status.get("fall", False))
        if new_fall:
            now = time.time()
            if now - last_fall_ts > 2.0:
                last_fall_ts = now
                fall_confirmed = True
                print("[FALL] fall detected", flush=True)
        else:
            fall_confirmed = False

        vis = draw_status(overlay)

        if DISPLAY_SIZE != size:
            vis = cv2.resize(vis, DISPLAY_SIZE)

        ret, buf = cv2.imencode('.jpg', vis, [int(cv2.IMWRITE_JPEG_QUALITY), 80])
        if ret:
            jpg_bytes = buf.tobytes()

            with frame_lock:
                latest_frame_jpg = jpg_bytes

            try:
                tmp_img = SNAPSHOT_PATH + ".tmp"
                with open(tmp_img, "wb") as f:
                    f.write(jpg_bytes)
                os.replace(tmp_img, SNAPSHOT_PATH)
            except Exception:
                pass

        now_ts = time.time()
        if now_ts - last_runtime_write_ts > 0.15:
            last_runtime_write_ts = now_ts
            write_runtime_status()

        if not HEADLESS:
            cv2.imshow('follow_person_pi', vis)

            key = cv2.waitKey(1) & 0xFF
            if key == ord('q') or key == 27:
                break
            if key == ord('r'):
                print("[INFO] reset tracking", flush=True)
                reset_state()
                startup_wait_until = time.time() + 6.0
            if key == ord('c'):
                initMove()
        else:
            time.sleep(0.001)

    camera.camera_close()
    if not HEADLESS:
        cv2.destroyAllWindows()
    exit_app()

