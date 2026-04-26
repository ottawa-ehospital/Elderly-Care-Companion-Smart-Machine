import threading
from typing import Dict, Any
import requests


class RobotController:
    def __init__(self):
        self._lock = threading.Lock()

        self.pi_base_url = "http://192.168.149.1:8000"   # Direct Connection
        # self.pi_base_url = "http://192.168.2.80:8000"  # LAN

        self.mode = "stopped"
        self.follow_enabled = False
        self.follow_mode = "full_follow"

        self.last_cmd = "stop"
        self.last_msg = "idle"

        self.online = False
        self.obstacle = None
        self.distance_cm = None
        self.battery_voltage = None

        self.pan_pulse = None
        self.tilt_pulse = None

        self.person_visible = None
        self.posture = "Unknown"
        self.score = 0.0

    def _post(self, path: str, payload: Dict[str, Any] | None = None, timeout: float = 1.2):
        url = f"{self.pi_base_url}{path}"
        if payload is None:
            r = requests.post(url, timeout=timeout)
        else:
            r = requests.post(url, json=payload, timeout=timeout)
        r.raise_for_status()
        return r.json()

    def _get(self, path: str, timeout: float = 1.2):
        url = f"{self.pi_base_url}{path}"
        r = requests.get(url, timeout=timeout)
        r.raise_for_status()
        return r.json()

    def _clear_remote_state(self, msg: str):
        with self._lock:
            self.online = False
            self.mode = "stopped"
            self.follow_enabled = False
            self.follow_mode = "full_follow"
            self.obstacle = None
            self.distance_cm = None
            self.battery_voltage = None
            self.pan_pulse = None
            self.tilt_pulse = None
            self.person_visible = None
            self.posture = "Unknown"
            self.score = 0.0
            self.last_msg = msg

    def refresh_remote_status(self):
        try:
            follow = self._get("/api/follow/status", timeout=1.0)
            sensors = self._get("/api/sensors", timeout=1.0)

            with self._lock:
                self.online = True
                self.follow_enabled = bool(follow.get("follow_enabled", False))
                self.follow_mode = str(follow.get("follow_mode", "full_follow"))
                self.last_cmd = str(follow.get("last_cmd", self.last_cmd))

                self.distance_cm = sensors.get("distance_cm")
                self.battery_voltage = sensors.get("battery_voltage")

                self.pan_pulse = follow.get("servo_x")
                self.tilt_pulse = follow.get("servo_y")

                self.person_visible = follow.get("target_visible")
                self.posture = str(follow.get("posture", "Unknown"))

                try:
                    self.score = float(follow.get("score", 0.0))
                except Exception:
                    self.score = 0.0

                try:
                    if self.distance_cm is not None:
                        self.obstacle = float(self.distance_cm) < 30.0
                    else:
                        self.obstacle = None
                except Exception:
                    self.obstacle = None

                if self.follow_enabled:
                    self.mode = "follow"
                elif self.last_cmd == "stop":
                    self.mode = "stopped"
                else:
                    self.mode = "manual"

                self.last_msg = (
                    f"follow={self.follow_enabled} "
                    f"mode={self.follow_mode} "
                    f"dist={self.distance_cm} "
                    f"posture={self.posture}"
                )

            return {"ok": True}

        except Exception as e:
            self._clear_remote_state(f"refresh failed: {e}")
            return {"ok": False, "error": str(e)}

    def update_from_camera_status(self, cam_status: Dict[str, Any]):
        with self._lock:
            if self.posture == "Unknown":
                self.posture = str(cam_status.get("posture", "Unknown"))
            try:
                if self.score == 0.0:
                    self.score = float(cam_status.get("score", 0.0))
            except Exception:
                pass

    def get_status(self) -> Dict[str, Any]:
        with self._lock:
            return {
                "online": self.online,
                "mode": self.mode,
                "follow_enabled": self.follow_enabled,
                "follow_mode": self.follow_mode,
                "obstacle": self.obstacle,
                "distance_cm": self.distance_cm,
                "battery_voltage": self.battery_voltage,
                "last_cmd": self.last_cmd,
                "last_msg": self.last_msg,
                "pan_pulse": self.pan_pulse,
                "tilt_pulse": self.tilt_pulse,
                "person_visible": self.person_visible,
                "posture": self.posture,
                "score": self.score,
            }

    def move(self, cmd: str) -> Dict[str, Any]:
        cmd = (cmd or "").strip().lower()
        allowed = {
            "forward", "backward", "left", "right",
            "front_left", "front_right", "back_left", "back_right",
            "turn_left", "turn_right", "stop"
        }
        if cmd not in allowed:
            return {"ok": False, "error": f"unknown cmd: {cmd}"}

        try:
            if cmd == "stop":
                data = self._post("/api/stop")
            else:
                data = self._post("/api/control", {"cmd": cmd})

            with self._lock:
                self.last_cmd = cmd
                self.last_msg = f"manual: {cmd}"
                self.follow_enabled = False
                self.mode = "stopped" if cmd == "stop" else "manual"

            self.refresh_remote_status()
            return {"ok": True, "remote": data}

        except Exception as e:
            self._clear_remote_state(f"move failed: {e}")
            return {"ok": False, "error": str(e)}

    def stop(self) -> Dict[str, Any]:
        try:
            data = self._post("/api/stop")

            with self._lock:
                self.last_cmd = "stop"
                self.last_msg = "stopped"
                self.mode = "stopped"
                self.follow_enabled = False

            self.refresh_remote_status()
            return {"ok": True, "remote": data}

        except Exception as e:
            self._clear_remote_state(f"stop failed: {e}")
            return {"ok": False, "error": str(e)}

    def start_follow(self, mode: str = "full_follow") -> Dict[str, Any]:
        mode = (mode or "full_follow").strip()
        if mode not in ("full_follow", "gimbal_only"):
            return {"ok": False, "error": "invalid mode"}

        try:
            data = self._post("/api/follow/start", {"mode": mode})

            with self._lock:
                self.follow_enabled = True
                self.follow_mode = mode
                self.mode = "follow"
                self.last_cmd = "follow_start"
                self.last_msg = f"follow started: {mode}"

            self.refresh_remote_status()
            return {"ok": True, "remote": data}

        except Exception as e:
            self._clear_remote_state(f"follow start failed: {e}")
            return {"ok": False, "error": str(e)}

    def set_follow_mode(self, mode: str) -> Dict[str, Any]:
        mode = (mode or "").strip()
        if mode not in ("full_follow", "gimbal_only"):
            return {"ok": False, "error": "invalid mode"}

        try:
            data = self._post("/api/follow/mode", {"mode": mode})

            with self._lock:
                self.follow_mode = mode
                self.last_cmd = "follow_mode"
                self.last_msg = f"follow mode: {mode}"

            self.refresh_remote_status()
            return {"ok": True, "remote": data}

        except Exception as e:
            self._clear_remote_state(f"follow mode failed: {e}")
            return {"ok": False, "error": str(e)}

    def stop_follow(self) -> Dict[str, Any]:
        try:
            data = self._post("/api/follow/stop")

            with self._lock:
                self.follow_enabled = False
                self.mode = "stopped"
                self.last_cmd = "follow_stop"
                self.last_msg = "follow stopped"

            self.refresh_remote_status()
            return {"ok": True, "remote": data}

        except Exception as e:
            self._clear_remote_state(f"follow stop failed: {e}")
            return {"ok": False, "error": str(e)}

    def gimbal_move(self, direction: str) -> Dict[str, Any]:
        direction = (direction or "").strip().lower()
        if direction not in {"up", "down", "left", "right"}:
            return {"ok": False, "error": f"unknown gimbal direction: {direction}"}

        try:
            self.refresh_remote_status()

            with self._lock:
                pan = self.pan_pulse
                tilt = self.tilt_pulse

            if pan is None:
                pan = 1464
            if tilt is None:
                tilt = 1164

            step = 20
            payload = {}

            if direction == "left":
                pan = max(964, int(pan) + step)
                payload["pan"] = pan
            elif direction == "right":
                pan = min(1964, int(pan) - step)
                payload["pan"] = pan
            elif direction == "up":
                tilt = min(1464, int(tilt) - step)
                payload["tilt"] = tilt
            elif direction == "down":
                tilt = max(714, int(tilt) + step)
                payload["tilt"] = tilt

            data = self._post("/api/gimbal", payload)

            with self._lock:
                if "pan" in data:
                    self.pan_pulse = data.get("pan")
                else:
                    self.pan_pulse = pan

                if "tilt" in data:
                    self.tilt_pulse = data.get("tilt")
                else:
                    self.tilt_pulse = tilt

                self.last_msg = f"manual gimbal: {direction}"
                self.follow_enabled = False
                self.mode = "manual"
                self.last_cmd = "manual_gimbal"

            return {"ok": True, "remote": data}

        except Exception as e:
            self._clear_remote_state(f"gimbal move failed: {e}")
            return {"ok": False, "error": str(e)}

    def gimbal_center(self) -> Dict[str, Any]:
        try:
            data = self._post("/api/gimbal/center")

            with self._lock:
                self.pan_pulse = data.get("pan")
                self.tilt_pulse = data.get("tilt")
                self.last_msg = "gimbal centered"
                self.follow_enabled = False
                self.mode = "manual"
                self.last_cmd = "gimbal_center"

            return {"ok": True, "remote": data}

        except Exception as e:
            self._clear_remote_state(f"gimbal center failed: {e}")
            return {"ok": False, "error": str(e)}


robot_controller = RobotController()