import time
import threading
import traceback
import os

import cv2
import numpy as np
from flask import Flask
from flask_login import current_user

from config import Config
from extensions import db, login_manager

import app_runtime as rt
from flask_cors import CORS

# blueprints
from blueprints.auth import bp as auth_bp
from blueprints.dashboard import bp as dashboard_bp
from blueprints.live import bp as live_bp
from blueprints.falls import bp as falls_bp
from blueprints.vitals import bp as vitals_bp
from blueprints.robot import bp as robot_bp
from blueprints.meds import bp as meds_bp
from blueprints.profile import bp as profile_bp
from blueprints.api_auth import bp as api_auth_bp

BASE_DIR = os.path.dirname(os.path.abspath(__file__))


def create_app():
    app = Flask(
        __name__,
        static_folder=os.path.join(BASE_DIR, "static"),
        template_folder=os.path.join(BASE_DIR, "templates"),
        static_url_path="/static",
    )
    app.config.from_object(Config)
    CORS(app, resources={r"/api/*": {"origins": "*"}})
    
    @app.route("/health")
    def health():
        return {"ok": True, "service": "flask_backend"}
    
    db.init_app(app)
    login_manager.init_app(app)

    app.register_blueprint(auth_bp)
    app.register_blueprint(dashboard_bp)
    app.register_blueprint(live_bp)
    app.register_blueprint(falls_bp)
    app.register_blueprint(vitals_bp)
    app.register_blueprint(robot_bp)
    app.register_blueprint(meds_bp)
    app.register_blueprint(profile_bp)
    app.register_blueprint(api_auth_bp)

    with app.app_context():
        db.create_all()

    @app.get("/_ping")
    def _ping():
        return {"ok": True, "ts": time.time()}

    @app.before_request
    def mark_active_user():
        if current_user.is_authenticated:
            app.last_active_user_id = current_user.id

    return app


app = create_app()

print(">>> before init_runtime")
rt.init_runtime(app)
print(">>> after init_runtime")


def recorder_pump():
    last_err_ts = 0.0
    while True:
        try:
            cam = getattr(rt, "camera", None)
            rec = getattr(rt, "recorder", None)

            if cam is None or rec is None:
                time.sleep(0.2)
                continue

            jpg = cam.get_jpeg()
            if jpg:
                arr = np.frombuffer(jpg, dtype=np.uint8)
                frame = cv2.imdecode(arr, cv2.IMREAD_COLOR)
                if frame is not None:
                    rec.push(frame)

        except Exception:
            now = time.time()
            if now - last_err_ts > 2.0:
                traceback.print_exc()
                last_err_ts = now
            time.sleep(0.2)

        time.sleep(0.01)


threading.Thread(target=recorder_pump, daemon=True).start()

if __name__ == "__main__":
    app.run(host="127.0.0.1", port=5050, threaded=True, use_reloader=False)