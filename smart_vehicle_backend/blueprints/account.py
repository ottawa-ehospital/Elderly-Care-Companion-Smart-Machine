from flask import Blueprint, render_template, request, redirect, url_for, flash
from flask_login import login_user, logout_user, login_required
from werkzeug.security import generate_password_hash, check_password_hash

from extensions import db, login_manager
from models import User

bp = Blueprint("auth", __name__)

@login_manager.user_loader
def load_user(user_id):
    return User.query.get(int(user_id))

@bp.route("/login", methods=["GET", "POST"])
def login():
    if request.method == "GET":
        return render_template("login.html")

    email = request.form.get("email", "").strip().lower()
    password = request.form.get("password", "")

    user = User.query.filter_by(email=email).first()
    if not user or not check_password_hash(user.password_hash, password):
        flash("Invalid email or password.", "error")
        return redirect(url_for("auth.login"))

    login_user(user)
    return redirect(url_for("dashboard.dashboard"))

@bp.route("/register", methods=["GET", "POST"])
def register():
    if request.method == "GET":
        return render_template("register.html")

    email = request.form.get("email", "").strip().lower()
    password = request.form.get("password", "")
    if not email or not password:
        flash("Email and password are required.", "error")
        return redirect(url_for("auth.register"))

    if User.query.filter_by(email=email).first():
        flash("Email already exists.", "error")
        return redirect(url_for("auth.register"))

    user = User(
        email=email,
        password_hash=generate_password_hash(password, method="pbkdf2:sha256", salt_length=16)
    )
    db.session.add(user)
    db.session.commit()
    login_user(user)
    return redirect(url_for("dashboard.dashboard"))

@bp.route("/logout", methods=["POST"])
@login_required
def logout():
    logout_user()
    return redirect(url_for("auth.login"))