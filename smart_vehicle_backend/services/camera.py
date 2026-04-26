import threading
import time
from dataclasses import dataclass
from typing import Optional, Callable, Any, Dict

import cv2
import numpy as np
import requests

from pose_fall_pipeline import PoseFallPipeline


@dataclass
class SharedState:
    jpeg: Optional[bytes] = None
    fall: bool = False
    fall_confirmed: bool = False
    last_msg: str = ""
    fps: float = 0.0
    posture: str = "Unknown"

    last_event_ts: float = 0.0
    event_id: int = 0

    person_cx: float = 0.5
    person_bh: float = 0.0
    score: float = 0.0


_camera_instance = None


def set_camera_instance(cam):
    global _camera_instance
    _camera_instance = cam


def get_camera():
    return _camera_instance


class CameraService:
    def __init__(
        self,
        cam_index: int = 0,
        camera_index: Optional[int] = None,
        model_path: Optional[str] = None,
        stream_url: Optional[str] = None,
        **_kwargs
    ):
        if camera_index is not None:
            cam_index = int(camera_index)

        self.cam_index = cam_index
        self.stream_url = stream_url
        self.model_path = model_path

        self.state = SharedState()
        self._lock = threading.Lock()
        self._running = False
        self._thread: Optional[threading.Thread] = None

        self._on_fall_confirmed: Optional[Callable[[Dict[str, Any]], None]] = None
        self._on_frame: Optional[Callable[[np.ndarray], None]] = None

        self._jpeg_quality = 85
        self._pipeline: Optional[PoseFallPipeline] = None

        self._alarm_cooldown = 2.0
        self._last_alarm_wall = -1e9

        self._src_desc: str = ""
        self._latest_frame_bgr: Optional[np.ndarray] = None

    def start(self):
        if self._running:
            return
        self._running = True
        self._thread = threading.Thread(target=self._loop, daemon=True)
        self._thread.start()

    def stop(self):
        self._running = False

    def set_on_fall_confirmed(self, cb: Callable[[Dict[str, Any]], None]):
        self._on_fall_confirmed = cb

    def set_on_frame(self, cb: Callable[[np.ndarray], None]):
        self._on_frame = cb

    def _emit_fall_confirmed(self, event: Dict[str, Any]):
        cb = self._on_fall_confirmed
        if cb is None:
            return
        try:
            cb(event)
        except Exception as e:
            print(f"[CameraService] fall callback error: {e!r}", flush=True)

    def _emit_frame(self, frame_bgr: np.ndarray):
        cb = self._on_frame
        if cb is None:
            return
        try:
            cb(frame_bgr)
        except Exception as e:
            print(f"[CameraService] frame callback error: {e!r}", flush=True)

    def _open_local_capture(self, src):
        return cv2.VideoCapture(src)

    def _read_remote_snapshot(self, url: str):
        try:
            r = requests.get(url, timeout=0.8)
            if r.status_code != 200 or not r.content:
                return None
            data = np.frombuffer(r.content, dtype=np.uint8)
            frame = cv2.imdecode(data, cv2.IMREAD_COLOR)
            return frame
        except Exception:
            return None

    def _loop(self):
        use_remote_snapshot = False
        cap = None

        if self.stream_url and str(self.stream_url).strip():
            src = str(self.stream_url).strip()
            self._src_desc = src

            if "/api/snapshot" in src:
                use_remote_snapshot = True
                with self._lock:
                    self.state.last_msg = f"Using remote snapshot source: {src}"
            else:
                cap = self._open_local_capture(src)
                with self._lock:
                    self.state.last_msg = f"Opening stream source: {src}"
        else:
            src = self.cam_index
            self._src_desc = str(src)
            cap = self._open_local_capture(src)
            with self._lock:
                self.state.last_msg = f"Opening local camera: {src}"

        if not use_remote_snapshot:
            if cap is None or not cap.isOpened():
                with self._lock:
                    self.state.last_msg = f"Camera open failed. src={self._src_desc}"
                    self.state.jpeg = None
                self._running = False
                return

        try:
            self._pipeline = PoseFallPipeline(model_path=self.model_path)
            with self._lock:
                self.state.last_msg = f"Pose pipeline initialized. src={self._src_desc}"
        except Exception as e:
            with self._lock:
                self.state.last_msg = f"Pose pipeline init failed: {e} | src={self._src_desc}"
            self._pipeline = None

        last_fps_t = time.time()
        frames = 0
        start_wall = time.time()
        bad_reads = 0

        while self._running:
            if use_remote_snapshot:
                frame = self._read_remote_snapshot(self.stream_url)
                ok = frame is not None
            else:
                ok, frame = cap.read()

            if not ok or frame is None:
                bad_reads += 1
                time.sleep(0.08)

                if bad_reads % 20 == 0:
                    with self._lock:
                        self.state.last_msg = f"Read failed x{bad_reads} | src={self._src_desc}"
                continue

            bad_reads = 0

            raw_frame = frame.copy()
            with self._lock:
                self._latest_frame_bgr = raw_frame.copy()

            self._emit_frame(raw_frame)

            now_wall = time.time()
            t_sec = now_wall - start_wall
            ts_ms = int(t_sec * 1000)

            annotated = frame
            status = {
                "fall_event": False,
                "fall": False,
                "posture": "Unknown",
                "dropY": 0.0,
                "dropTorsoV": 0.0,
                "dropHeadY": 0.0,
                "msg": "OK (no pipeline)",
                "person_cx": 0.5,
                "person_bh": 0.0,
                "score": 0.0,
            }

            if self._pipeline is not None:
                try:
                    annotated, status = self._pipeline.process(frame_bgr=frame, ts_ms=ts_ms)
                except Exception as e:
                    status["msg"] = f"pipeline error: {e}"
                    annotated = frame

            fall_event = bool(status.get("fall_event", False))
            posture = str(status.get("posture", "Unknown"))
            fall_like = (posture == "Lying") or bool(status.get("fall", False))

            pcx = float(status.get("person_cx", 0.5))
            pbh = float(status.get("person_bh", 0.0))
            score = float(status.get("score", 0.0))

            ok2, buf = cv2.imencode(
                ".jpg", annotated, [int(cv2.IMWRITE_JPEG_QUALITY), self._jpeg_quality]
            )
            jpeg = buf.tobytes() if ok2 else None

            frames += 1
            fps_now = None
            if now_wall - last_fps_t >= 1.0:
                fps_now = frames / (now_wall - last_fps_t)
                frames = 0
                last_fps_t = now_wall

            with self._lock:
                self.state.jpeg = jpeg
                self.state.fall = fall_like
                self.state.posture = posture
                self.state.last_msg = f"{status.get('msg', 'OK')} | src={self._src_desc}"
                self.state.person_cx = pcx
                self.state.person_bh = pbh
                self.state.score = score
                if fps_now is not None:
                    self.state.fps = fps_now

            if fall_event and (now_wall - self._last_alarm_wall) >= self._alarm_cooldown:
                self._last_alarm_wall = now_wall

                event = {
                    "ts": now_wall,
                    "t_sec": t_sec,
                    "camera_index": self.cam_index,
                    "posture": posture,
                    "dropY": float(status.get("dropY", 0.0)),
                    "dropTorsoV": float(status.get("dropTorsoV", 0.0)),
                    "dropHeadY": float(status.get("dropHeadY", 0.0)),
                }

                with self._lock:
                    self.state.fall_confirmed = True
                    self.state.last_event_ts = now_wall
                    self.state.event_id += 1

                print(f"[FALL EVENT] t={t_sec:.2f}s posture={posture}", flush=True)
                self._emit_fall_confirmed(event)

            if use_remote_snapshot:
                time.sleep(0.12)

        if cap is not None:
            cap.release()

    def get_jpeg(self) -> Optional[bytes]:
        with self._lock:
            return self.state.jpeg

    def get_frame_bgr(self) -> Optional[np.ndarray]:
        with self._lock:
            if self._latest_frame_bgr is None:
                return None
            return self._latest_frame_bgr.copy()

    def get_status(self) -> Dict[str, Any]:
        with self._lock:
            return {
                "online": self.state.jpeg is not None,
                "fall": self.state.fall,
                "fall_confirmed": self.state.fall_confirmed,
                "msg": self.state.last_msg,
                "fps": round(self.state.fps, 1),
                "camera_index": self.cam_index,
                "posture": self.state.posture,
                "last_event_ts": self.state.last_event_ts,
                "event_id": self.state.event_id,
                "person_cx": self.state.person_cx,
                "person_bh": self.state.person_bh,
                "score": self.state.score,
            }