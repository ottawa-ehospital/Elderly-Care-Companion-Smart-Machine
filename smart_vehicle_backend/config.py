import os

BASE_DIR = os.path.dirname(os.path.abspath(__file__))

class Config:
    SECRET_KEY = os.environ.get("SECRET_KEY", "dev-secret-change-me")

    # SQLite DB in instance/
    INSTANCE_DIR = os.path.join(BASE_DIR, "instance")
    os.makedirs(INSTANCE_DIR, exist_ok=True)
    SQLALCHEMY_DATABASE_URI = "sqlite:///" + os.path.join(INSTANCE_DIR, "app.db")
    SQLALCHEMY_TRACK_MODIFICATIONS = False

    # MediaPipe model path
    MODEL_PATH = os.path.join(BASE_DIR, "models", "pose_landmarker_lite.task")

    # Storage
    STORAGE_DIR = os.path.join(BASE_DIR, "storage")
    FALLS_DIR = os.path.join(STORAGE_DIR, "falls")
    os.makedirs(FALLS_DIR, exist_ok=True)

    # Camera / server
    CAMERA_INDEX = int(os.environ.get("CAMERA_INDEX", "0"))
    PORT = int(os.environ.get("PORT", "5050"))