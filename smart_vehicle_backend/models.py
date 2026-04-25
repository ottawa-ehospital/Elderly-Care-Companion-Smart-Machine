from datetime import datetime
from extensions import db
from flask_login import UserMixin


class User(db.Model, UserMixin):
    __tablename__ = "users"

    id = db.Column(db.Integer, primary_key=True)
    email = db.Column(db.String(255), unique=True, nullable=False, index=True)
    password_hash = db.Column(db.String(255), nullable=False)

    patient_id = db.Column(db.Integer, unique=True, nullable=True, index=True)

    created_at = db.Column(db.DateTime, default=datetime.utcnow, nullable=False)

    vitals = db.relationship("Vital", backref="user", lazy=True, cascade="all, delete-orphan")
    meds = db.relationship("MedReminder", backref="user", lazy=True, cascade="all, delete-orphan")
    falls = db.relationship("FallEvent", backref="user", lazy=True, cascade="all, delete-orphan")
    wearable_vitals = db.relationship("WearableVital", backref="user", lazy=True, cascade="all, delete-orphan")


class Vital(db.Model):
    __tablename__ = "vitals"

    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)

    patient_id = db.Column(db.Integer, nullable=True, index=True)

    timestamp = db.Column(db.DateTime, default=datetime.utcnow, nullable=False, index=True)

    heart_rate = db.Column(db.Integer, nullable=True)
    steps = db.Column(db.Integer, nullable=True)
    calories = db.Column(db.Integer, nullable=True)
    sleep = db.Column(db.Float, nullable=True)

    spo2 = db.Column(db.Float, nullable=True)
    bp_sys = db.Column(db.Integer, nullable=True)
    bp_dia = db.Column(db.Integer, nullable=True)
    temperature = db.Column(db.Float, nullable=True)

    notes = db.Column(db.String(500), default="")


class MedReminder(db.Model):
    __tablename__ = "med_reminders"

    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)

    name = db.Column(db.String(200), nullable=False)
    dosage = db.Column(db.String(100), default="")
    time_of_day = db.Column(db.String(5), nullable=False)
    enabled = db.Column(db.Boolean, default=True, nullable=False)

    last_sent_at = db.Column(db.DateTime, nullable=True)

    last_confirmed_at = db.Column(db.DateTime, nullable=True)
    last_confirmed_by = db.Column(db.String(100), nullable=True)
    pending_today = db.Column(db.Boolean, default=False, nullable=False)
    pending_date = db.Column(db.String(10), nullable=True)  # YYYY-MM-DD


class FallEvent(db.Model):
    __tablename__ = "fall_event"

    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey("users.id", ondelete="CASCADE"), index=True, nullable=False)

    patient_id = db.Column(db.Integer, nullable=True, index=True)

    timestamp = db.Column(db.DateTime, default=datetime.utcnow, index=True, nullable=False)
    reason = db.Column(db.String(255), default="Fall event", nullable=False)

    video_name = db.Column(db.String(255), nullable=True)
    deleted = db.Column(db.Boolean, default=False, nullable=False)

    def to_dict(self):
        return {
            "id": self.id,
            "user_id": self.user_id,
            "patient_id": self.patient_id,
            "timestamp": self.timestamp.isoformat(),
            "reason": self.reason,
            "video_name": self.video_name,
            "deleted": bool(self.deleted),
        }


class WearableVital(db.Model):
    __tablename__ = "wearable_vitals_local"

    id = db.Column(db.Integer, primary_key=True)

    user_id = db.Column(db.Integer, db.ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)

    patient_id = db.Column(db.Integer, nullable=False, index=True)
    heart_rate = db.Column(db.Integer, default=0)
    steps = db.Column(db.Integer, default=0)
    calories = db.Column(db.Integer, default=0)
    sleep = db.Column(db.String(20), default="0.00")

    timestamp = db.Column(db.DateTime, nullable=False, index=True)
    recorded_on = db.Column(db.DateTime, default=datetime.utcnow, nullable=False)

    source = db.Column(db.String(50), default="manual")