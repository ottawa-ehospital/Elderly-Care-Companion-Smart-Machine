from flask import Blueprint, render_template, jsonify, request
from flask_login import login_required

from services.robot_controller import robot_controller
from services.camera import get_camera

bp = Blueprint("robot", __name__)


@bp.route("/robot")
@login_required
def robot_page():
    return render_template("robot.html")


@bp.route("/api/robot/status")
def robot_status():
    cam = get_camera()
    cam_status = cam.get_status()
    robot_controller.update_from_camera_status(cam_status)
    robot_controller.refresh_remote_status()
    return jsonify(robot_controller.get_status())


@bp.route("/api/robot/move", methods=["POST"])
def robot_move():
    data = request.get_json(force=True, silent=True) or {}
    cmd = data.get("cmd", "")
    return jsonify(robot_controller.move(cmd))


@bp.route("/api/robot/stop", methods=["POST"])
def robot_stop():
    return jsonify(robot_controller.stop())


@bp.route("/api/robot/follow/start", methods=["POST"])
def robot_follow_start():
    data = request.get_json(force=True, silent=True) or {}
    mode = data.get("mode", "full_follow")
    return jsonify(robot_controller.start_follow(mode))


@bp.route("/api/robot/follow/mode", methods=["POST"])
def robot_follow_mode():
    data = request.get_json(force=True, silent=True) or {}
    mode = data.get("mode", "full_follow")
    return jsonify(robot_controller.set_follow_mode(mode))


@bp.route("/api/robot/follow/stop", methods=["POST"])
def robot_follow_stop():
    return jsonify(robot_controller.stop_follow())


@bp.route("/api/robot/gimbal/move", methods=["POST"])
def robot_gimbal_move():
    data = request.get_json(force=True, silent=True) or {}
    direction = data.get("direction", "")
    return jsonify(robot_controller.gimbal_move(direction))


@bp.route("/api/robot/gimbal/center", methods=["POST"])
def robot_gimbal_center():
    return jsonify(robot_controller.gimbal_center())