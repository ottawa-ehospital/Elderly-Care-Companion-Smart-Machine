import os
from typing import Optional

from services.camera import CameraService, set_camera_instance
from services.recorder import RecorderService


camera: Optional[CameraService] = None
recorder: Optional[RecorderService] = None

RASPI_STREAM_URL = "http://192.168.149.1:8000/api/snapshot"  # Direct Connection
# RASPI_STREAM_URL = "http://192.168.2.80:8000/api/snapshot"  # LAN
# RASPI_STREAM_URL = None


def init_runtime(app):
    global camera, recorder

    base_dir = os.path.dirname(os.path.abspath(__file__))
    storage_dir = os.path.join(base_dir, "storage")
    os.makedirs(storage_dir, exist_ok=True)

    def get_uid():
        return getattr(app, "last_active_user_id", None)

    camera = CameraService(
        camera_index=0,
        stream_url=RASPI_STREAM_URL,
    )
    set_camera_instance(camera)

    recorder = RecorderService(
        base_dir=storage_dir,
        fps=8.0,
        pre_sec=5.0,
        post_sec=10.0,
        user_id_getter=get_uid,
        flask_app=app,
    )

    camera.set_on_fall_confirmed(recorder.on_fall_confirmed)
    camera.set_on_frame(recorder.push)
    camera.start()