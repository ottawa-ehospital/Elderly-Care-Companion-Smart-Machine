# pose_fall_pipeline.py
import os
import math
import urllib.request
from collections import deque

import cv2
import mediapipe as mp
from mediapipe.tasks import python
from mediapipe.tasks.python import vision

# heavy model
# MODEL_URL = "https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_heavy/float16/latest/pose_landmarker_heavy.task"
# full model
MODEL_URL = "https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_full/float16/1/pose_landmarker_full.task"
# lite model
# MODEL_URL = "https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_lite/float16/1/pose_landmarker_lite.task"


def _ensure_model(model_path: str):
    if os.path.exists(model_path) and os.path.getsize(model_path) > 0:
        return
    os.makedirs(os.path.dirname(model_path) or ".", exist_ok=True)
    print("Downloading pose model to:", model_path, flush=True)
    urllib.request.urlretrieve(MODEL_URL, model_path)
    print("Done.", flush=True)


def _create_landmarker(model_path: str):
    base_options = python.BaseOptions(model_asset_path=model_path)
    options = vision.PoseLandmarkerOptions(
        base_options=base_options,
        running_mode=vision.RunningMode.VIDEO,
        num_poses=1,
        min_pose_detection_confidence=0.3,
        min_pose_presence_confidence=0.3,
        min_tracking_confidence=0.3,
        output_segmentation_masks=False,
    )
    return vision.PoseLandmarker.create_from_options(options)


LINE_COLOR = (255, 255, 255)
POINT_COLOR = (0, 255, 255)

POSE_CONNECTIONS = [
    (0,1),(1,2),(2,3),(3,7),
    (0,4),(4,5),(5,6),(6,8),
    (9,10),
    (11,12),
    (11,13),(13,15),(15,17),(15,19),(15,21),(17,19),
    (12,14),(14,16),(16,18),(16,20),(16,22),(18,20),
    (11,23),(12,24),(23,24),
    (23,25),(25,27),(27,29),(29,31),
    (24,26),(26,28),(28,30),(30,32),
    (27,31),(28,32),
]


def _draw_skeleton(image_bgr, lms):
    h, w = image_bgr.shape[:2]
    pts = {}
    for i, lm in enumerate(lms):
        vis = getattr(lm, "visibility", 1.0)
        if vis is not None and vis < 0.2:
            continue
        pts[i] = (int(lm.x * w), int(lm.y * h))

    for a, b in POSE_CONNECTIONS:
        if a in pts and b in pts:
            cv2.line(image_bgr, pts[a], pts[b], LINE_COLOR, 2, cv2.LINE_AA)

    for _, (x, y) in pts.items():
        cv2.circle(image_bgr, (x, y), 3, POINT_COLOR, -1, cv2.LINE_AA)


L_SHOULDER = 11
R_SHOULDER = 12
L_HIP = 23
R_HIP = 24
L_KNEE = 25
R_KNEE = 26
L_ANKLE = 27
R_ANKLE = 28
NOSE = 0

ANKLE_VIS_MIN = 0.25


def _angle_deg(a, b, c):
    bax, bay = a[0] - b[0], a[1] - b[1]
    bcx, bcy = c[0] - b[0], c[1] - b[1]
    dot = bax * bcx + bay * bcy
    na = math.hypot(bax, bay) + 1e-6
    nc = math.hypot(bcx, bcy) + 1e-6
    cosv = max(-1.0, min(1.0, dot / (na * nc)))
    return math.degrees(math.acos(cosv))


def _ankles_available(lms):
    lv = getattr(lms[L_ANKLE], "visibility", 1.0) or 1.0
    rv = getattr(lms[R_ANKLE], "visibility", 1.0) or 1.0
    return (lv >= ANKLE_VIS_MIN) or (rv >= ANKLE_VIS_MIN)


def _avg_person_score(lms):
    idxs = [L_SHOULDER, R_SHOULDER, L_HIP, R_HIP, L_KNEE, R_KNEE]
    vals = []
    for i in idxs:
        v = getattr(lms[i], "visibility", 1.0)
        if v is None:
            v = 1.0
        vals.append(float(v))
    if not vals:
        return 0.0
    return sum(vals) / len(vals)


def _posture_classify(lms):
    sh = (
        (lms[L_SHOULDER].x + lms[R_SHOULDER].x) / 2,
        (lms[L_SHOULDER].y + lms[R_SHOULDER].y) / 2
    )
    hip = (
        (lms[L_HIP].x + lms[R_HIP].x) / 2,
        (lms[L_HIP].y + lms[R_HIP].y) / 2
    )

    dx = sh[0] - hip[0]
    dy = sh[1] - hip[1]
    torsoV = abs(dy) / (abs(dx) + abs(dy) + 1e-6)

    xs = [lm.x for lm in lms]
    ys = [lm.y for lm in lms]
    bw = (max(xs) - min(xs)) + 1e-6
    bh = (max(ys) - min(ys)) + 1e-6
    aspect = bw / bh

    lh = (lms[L_HIP].x, lms[L_HIP].y)
    lk = (lms[L_KNEE].x, lms[L_KNEE].y)
    la = (lms[L_ANKLE].x, lms[L_ANKLE].y)
    rh = (lms[R_HIP].x, lms[R_HIP].y)
    rk = (lms[R_KNEE].x, lms[R_KNEE].y)
    ra = (lms[R_ANKLE].x, lms[R_ANKLE].y)
    knee = (_angle_deg(lh, lk, la) + _angle_deg(rh, rk, ra)) / 2

    y_hip = hip[1]
    y_knee = (lms[L_KNEE].y + lms[R_KNEE].y) / 2
    hipAboveKnee = (y_knee - y_hip)

    LYING_TORSOV_MAX = 0.50
    LYING_ASPECT_MIN = 1.20
    SITTING_KNEE_MAX = 150
    SITTING_TORSOV_MIN = 0.55
    STANDING_KNEE_MIN = 155
    STANDING_HIP_ABOVE_KNEE_MIN = 0.06

    is_lying = (torsoV < LYING_TORSOV_MAX) or (aspect > LYING_ASPECT_MIN)

    ankleOK = _ankles_available(lms)
    if not ankleOK:
        label = "Lying" if is_lying else "Unknown"
    else:
        is_sitting = (knee < SITTING_KNEE_MAX) and (torsoV > SITTING_TORSOV_MIN) and (not is_lying)
        is_standing = (knee > STANDING_KNEE_MIN) and (hipAboveKnee > STANDING_HIP_ABOVE_KNEE_MIN) and (not is_lying)

        if is_lying:
            label = "Lying"
        elif is_sitting:
            label = "Sitting"
        elif is_standing:
            label = "Standing"
        else:
            label = "Standing" if torsoV > 0.6 else "Sitting"

    debug = {"torsoV": torsoV, "aspect": aspect, "knee": knee, "ankleOK": ankleOK}
    return label, debug


WINDOW_SEC = 0.7
LYING_CONFIRM_SEC = 0.45
FALL_COOLDOWN = 2.0

DROP_Y_THRESH = 0.10
TORSOV_DROP_THRESH = 0.45
HEAD_DROP_THRESH = 0.10


class _FallEventDetector:
    def __init__(self):
        self.hist = deque()
        self.pending_t = None
        self.last_fire_t = -1e9

    def update(self, t_sec, hip_y, torsoV, head_y, posture):
        self.hist.append((t_sec, hip_y, torsoV, head_y, posture))
        while self.hist and (t_sec - self.hist[0][0]) > WINDOW_SEC:
            self.hist.popleft()

        dropY = dropTorsoV = dropHeadY = 0.0
        if len(self.hist) >= 2:
            _, hy0, tv0, hd0, _ = self.hist[0]
            _, hy1, tv1, hd1, _ = self.hist[-1]
            dropY = hy1 - hy0
            dropTorsoV = tv0 - tv1
            dropHeadY = hd1 - hd0

        triggered = (dropY > DROP_Y_THRESH) or (dropTorsoV > TORSOV_DROP_THRESH) or (dropHeadY > HEAD_DROP_THRESH)
        pending = False
        if triggered and self.pending_t is None:
            self.pending_t = t_sec
            pending = True

        fall_event = False
        if self.pending_t is not None:
            if (t_sec - self.pending_t) <= LYING_CONFIRM_SEC:
                if posture == "Lying":
                    fall_event = True
                    self.pending_t = None
            else:
                self.pending_t = None

        do_fire = False
        if fall_event and (t_sec - self.last_fire_t) >= FALL_COOLDOWN:
            self.last_fire_t = t_sec
            do_fire = True

        return fall_event, do_fire, pending, dropY, dropTorsoV, dropHeadY


def _clamp01(x: float) -> float:
    return 0.0 if x < 0.0 else (1.0 if x > 1.0 else x)


class PoseFallPipeline:
    def __init__(self, model_path=None, person_score_thresh=0.60):
        if model_path is None or str(model_path).strip() == "":
            model_path = os.path.join(os.getcwd(), "pose_landmarker_full.task")
        self.model_path = model_path
        self.person_score_thresh = float(person_score_thresh)

        _ensure_model(self.model_path)
        self.landmarker = _create_landmarker(self.model_path)
        self.detector = _FallEventDetector()

    def process(self, frame_bgr, ts_ms: int):
        t_sec = float(ts_ms) / 1000.0

        rgb = cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2RGB)
        mp_img = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
        result = self.landmarker.detect_for_video(mp_img, int(ts_ms))

        overlay = frame_bgr.copy()

        status = {
            "fall_event": False,
            "fall": False,
            "posture": "Unknown",
            "dropY": 0.0,
            "dropTorsoV": 0.0,
            "dropHeadY": 0.0,
            "msg": "No pose",
            "person_cx": 0.5,
            "person_bh": 0.0,
            "has_person": False,
            "bbox": None,
            "score": 0.0,
        }

        if not (result.pose_landmarks and len(result.pose_landmarks) > 0):
            return overlay, status

        lms = result.pose_landmarks[0]
        person_score = _avg_person_score(lms)

        if person_score < self.person_score_thresh:
            cv2.putText(
                overlay,
                f"low score={person_score:.2f}",
                (10, 24),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.6,
                (0, 0, 255),
                2,
                cv2.LINE_AA
            )
            status["msg"] = f"Low pose score: {person_score:.2f}"
            status["score"] = float(person_score)
            return overlay, status

        _draw_skeleton(overlay, lms)

        posture, dbg = _posture_classify(lms)

        hip_y = (lms[L_HIP].y + lms[R_HIP].y) / 2
        head_y = lms[NOSE].y
        torsoV = dbg["torsoV"]

        fall_event, do_fire, pending, dropY, dropTorsoV, dropHeadY = self.detector.update(
            t_sec=t_sec,
            hip_y=hip_y,
            torsoV=torsoV,
            head_y=head_y,
            posture=posture,
        )

        show_posture = (dbg["ankleOK"] or posture == "Lying")

        xs = [lm.x for lm in lms]
        ys = [lm.y for lm in lms]
        H, W = overlay.shape[:2]

        x_min = _clamp01(min(xs))
        x_max = _clamp01(max(xs))
        y_min = _clamp01(min(ys))
        y_max = _clamp01(max(ys))

        x1 = max(0, min(W - 1, int(x_min * W)))
        y1 = max(0, min(H - 1, int(y_min * H)))
        x2 = max(0, min(W - 1, int(x_max * W)))
        y2 = max(0, min(H - 1, int(y_max * H)))

        cv2.rectangle(overlay, (x1, y1), (x2, y2), (255, 255, 255), 2)

        if show_posture:
            cv2.rectangle(overlay, (x1, max(0, y1 - 34)), (x1 + 260, y1), (0, 0, 0), -1)
            cv2.putText(
                overlay,
                f"{posture} score={person_score:.2f}",
                (x1 + 8, y1 - 10),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.75,
                (255, 255, 255),
                2,
                cv2.LINE_AA
            )

        person_cx = _clamp01((x_min + x_max) / 2.0)
        person_bh = _clamp01(max(1e-6, (y_max - y_min)))

        if fall_event:
            text = "FALL EVENT!"
            font = cv2.FONT_HERSHEY_SIMPLEX
            scale = 1.6
            thick = 4
            (tw, th), baseline = cv2.getTextSize(text, font, scale, thick)
            x = (W - tw) // 2
            y = (H + th) // 2
            pad = 12
            cv2.rectangle(
                overlay,
                (x - pad, y - th - pad),
                (x + tw + pad, y + baseline + pad),
                (0, 0, 0),
                -1
            )
            cv2.putText(overlay, text, (x, y), font, scale, (0, 0, 255), thick, cv2.LINE_AA)

        status = {
            "fall_event": bool(fall_event),
            "fall": bool(posture == "Lying"),
            "posture": posture,
            "dropY": float(dropY),
            "dropTorsoV": float(dropTorsoV),
            "dropHeadY": float(dropHeadY),
            "msg": "OK",
            "pending": bool(pending),
            "person_cx": float(person_cx),
            "person_bh": float(person_bh),
            "has_person": True,
            "bbox": (int(x1), int(y1), int(x2), int(y2)),
            "score": float(person_score),
        }
        return overlay, status

