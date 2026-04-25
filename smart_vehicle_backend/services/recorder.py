import os
import time
from collections import deque
from typing import Optional, Deque, Any, Dict, Callable
from datetime import datetime

import cv2
import numpy as np


class RecorderService:
    def __init__(
        self,
        base_dir: str,
        fps: float = 8.0,
        pre_sec: float = 5.0,
        post_sec: float = 5.0,
        user_id_getter: Optional[Callable[[], Optional[int]]] = None,
        flask_app=None,
    ):
        self.base_dir = base_dir
        self.fps = float(fps) if fps and fps > 1 else 8.0
        self.pre_sec = float(pre_sec)
        self.post_sec = float(post_sec)
        self.user_id_getter = user_id_getter
        self.flask_app = flask_app

        self.max_pre = int(self.fps * self.pre_sec) + 2
        self._pre_buf: Deque[np.ndarray] = deque(maxlen=self.max_pre)

        self._pending = False
        self._pending_until = 0.0
        self._event_meta: Dict[str, Any] = {}
        self._capture_frames: list[np.ndarray] = []

        self._last_saved_path: Optional[str] = None

        self._sample_interval = 1.0 / self.fps
        self._last_sample_ts = 0.0

    def push(self, frame_bgr: np.ndarray):
        if frame_bgr is None:
            return

        now = time.time()
        if self._last_sample_ts > 0 and (now - self._last_sample_ts) < self._sample_interval:
            return

        self._last_sample_ts = now

        frame_copy = frame_bgr.copy()
        self._pre_buf.append(frame_copy)

        if self._pending:
            self._capture_frames.append(frame_copy)
            if now >= self._pending_until:
                self._finalize_and_save()

    def on_fall_confirmed(self, event: Dict[str, Any]):
        if self._pending:
            return

        now = time.time()
        self._pending = True
        self._pending_until = now + self.post_sec
        self._event_meta = dict(event)
        self._capture_frames = list(self._pre_buf)

        print(
            f"[Recorder] fall confirmed, start capture. "
            f"pre_frames={len(self._capture_frames)} "
            f"post_sec={self.post_sec} fps={self.fps}",
            flush=True,
        )

    def last_saved_path(self) -> Optional[str]:
        return self._last_saved_path

    def _get_uid(self) -> int:
        uid = None
        if self.user_id_getter is not None:
            try:
                uid = self.user_id_getter()
            except Exception:
                uid = None
        return int(uid) if uid else 1

    def _get_user_dir(self, uid: int) -> str:
        out_dir = os.path.join(self.base_dir, "falls", f"u{uid}")
        os.makedirs(out_dir, exist_ok=True)
        return out_dir

    @staticmethod
    def _safe_float(x, default=0.0) -> float:
        try:
            return float(x)
        except Exception:
            return float(default)

    def _build_reason(self, meta: Dict[str, Any]) -> str:
        posture = str(meta.get("posture", "Unknown"))
        dropY = self._safe_float(meta.get("dropY", 0.0))
        dropTorsoV = self._safe_float(meta.get("dropTorsoV", 0.0))
        dropHeadY = self._safe_float(meta.get("dropHeadY", 0.0))
        return (
            f"posture={posture} "
            f"dropY={dropY:.3f} "
            f"dropTorsoV={dropTorsoV:.3f} "
            f"dropHeadY={dropHeadY:.3f}"
        )

    def _write_video(self, frames: list[np.ndarray], out_path: str) -> bool:
        if not frames:
            print("[Recorder] no frames to write", flush=True)
            return False

        first = frames[0]
        if first is None or len(first.shape) != 3 or first.shape[2] != 3:
            print("[Recorder] invalid first frame shape", flush=True)
            return False

        h, w = first.shape[:2]

        norm_frames = []
        for f in frames:
            if f is None:
                continue
            if len(f.shape) != 3 or f.shape[2] != 3:
                continue
            if f.shape[0] != h or f.shape[1] != w:
                f = cv2.resize(f, (w, h))
            norm_frames.append(f)

        if not norm_frames:
            print("[Recorder] no valid normalized frames", flush=True)
            return False

        fourcc = cv2.VideoWriter_fourcc(*"avc1")
        writer = cv2.VideoWriter(out_path, fourcc, self.fps, (w, h))

        if not writer.isOpened():
            fourcc = cv2.VideoWriter_fourcc(*"mp4v")
            writer = cv2.VideoWriter(out_path, fourcc, self.fps, (w, h))

        if not writer.isOpened():
            print("[Recorder] mp4 writer failed (avc1/mp4v)", flush=True)
            return False

        try:
            for f in norm_frames:
                writer.write(f)
        finally:
            writer.release()

        return True

    def _insert_db_event(self, uid: int, event_dt: datetime, reason: str, filename: str):
        if self.flask_app is None:
            print("[Recorder] flask_app is None, skip DB insert", flush=True)
            return

        with self.flask_app.app_context():
            from extensions import db
            from models import FallEvent

            ev = FallEvent(
                user_id=uid,
                timestamp=event_dt,
                reason=reason,
                video_name=filename,
                deleted=False,
            )
            db.session.add(ev)
            db.session.commit()

    def _finalize_and_save(self):
        frames = self._capture_frames
        meta = dict(self._event_meta)

        self._pending = False
        self._capture_frames = []
        self._event_meta = {}

        if not frames:
            print("[Recorder] finalize but no frames", flush=True)
            return

        uid = self._get_uid()
        out_dir = self._get_user_dir(uid)

        ts_str = time.strftime("%Y%m%d_%H%M%S", time.localtime(time.time()))
        filename = f"{ts_str}.mp4"
        out_path = os.path.join(out_dir, filename)

        expected_duration = len(frames) / float(self.fps)

        print(
            f"[Recorder] finalize: frames={len(frames)} fps={self.fps} "
            f"expected_duration={expected_duration:.2f}s file={filename}",
            flush=True,
        )

        ok = self._write_video(frames, out_path)
        if not ok:
            print("[Recorder] write video failed", flush=True)
            return

        self._last_saved_path = out_path

        reason = self._build_reason(meta)
        wall_ts = self._safe_float(meta.get("ts", time.time()), default=time.time())
        event_dt = datetime.fromtimestamp(float(wall_ts))

        try:
            self._insert_db_event(
                uid=uid,
                event_dt=event_dt,
                reason=reason,
                filename=filename,
            )
            print(f"[Recorder] DB inserted FallEvent uid={uid} video={filename}", flush=True)
        except Exception as e:
            print(f"[Recorder] DB insert failed: {e!r}", flush=True)