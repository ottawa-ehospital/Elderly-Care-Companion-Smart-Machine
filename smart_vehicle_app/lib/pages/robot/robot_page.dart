import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/api/api_client.dart';

class RobotPage extends StatefulWidget {
  const RobotPage({super.key});

  @override
  State<RobotPage> createState() => _RobotPageState();
}

class _RobotPageState extends State<RobotPage> {
  bool loading = true;
  String error = '';
  Map<String, dynamic> status = {};
  String selectedFollowMode = 'full_follow';

  Timer? _pollTimer;
  Timer? _snapshotTimer;

  @override
  void initState() {
    super.initState();

    refreshStatus();

    _pollTimer = Timer.periodic(const Duration(milliseconds: 800), (_) async {
      await refreshStatus(silent: true);
    });

    _snapshotTimer = Timer.periodic(const Duration(milliseconds: 120), (_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _snapshotTimer?.cancel();
    super.dispose();
  }

  Future<void> refreshStatus({bool silent = false}) async {
    try {
      final data = await ApiClient.instance.getRobotStatus();
      if (!mounted) return;

      setState(() {
        status = data;
        loading = false;
        if (!silent) error = '';

        final serverMode = data['follow_mode']?.toString();
        if (serverMode == 'full_follow' || serverMode == 'gimbal_only') {
          selectedFollowMode = serverMode!;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = '$e';
      });
    }
  }

  Future<void> _sendMove(String cmd) async {
    try {
      await ApiClient.instance.robotMove(cmd);
      await refreshStatus(silent: true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = '$e';
      });
    }
  }

  Future<void> _sendGimbal(String direction) async {
    try {
      await ApiClient.instance.robotGimbalMove(direction);
      await refreshStatus(silent: true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = '$e';
      });
    }
  }

  Future<void> stopRobot() async {
    try {
      await ApiClient.instance.robotStop();
      await refreshStatus(silent: true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = '$e';
      });
    }
  }

  Future<void> startFollow(String mode) async {
    try {
      await ApiClient.instance.robotFollowStart(mode);
      await refreshStatus();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = '$e';
      });
    }
  }

  Future<void> stopFollow() async {
    try {
      await ApiClient.instance.robotFollowStop();
      await refreshStatus();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = '$e';
      });
    }
  }

  Future<void> setFollowMode(String mode) async {
    try {
      setState(() {
        selectedFollowMode = mode;
      });
      await ApiClient.instance.robotFollowMode(mode);
      await refreshStatus(silent: true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = '$e';
      });
    }
  }

  Future<void> gimbalCenter() async {
    try {
      await ApiClient.instance.robotGimbalCenter();
      await refreshStatus();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = '$e';
      });
    }
  }

  String _panLabel(int? pan) {
    if (pan == null) return '—';
    if (pan < 1300) return 'Left';
    if (pan > 1700) return 'Right';
    return 'Center';
  }

  String _tiltLabel(int? tilt) {
    if (tilt == null) return '—';
    if (tilt < 950) return 'Up';
    if (tilt > 1100) return 'Down';
    return 'Mid';
  }

  String _modeLabel(String mode) {
    switch (mode.toLowerCase()) {
      case 'stopped':
        return 'Stopped';
      case 'manual':
        return 'Manual';
      case 'follow':
        return 'Follow';
      default:
        return mode.isEmpty ? '—' : mode;
    }
  }

  String _followModeLabel(String mode) {
    switch (mode) {
      case 'full_follow':
        return 'Full Follow';
      case 'gimbal_only':
        return 'Gimbal Only';
      default:
        return mode.isEmpty ? '—' : mode;
    }
  }

  String _boolLabel(
    dynamic v, {
    required String trueText,
    required String falseText,
  }) {
    if (v == true) return trueText;
    if (v == false) return falseText;
    final s = v?.toString().toLowerCase();
    if (s == 'true') return trueText;
    if (s == 'false') return falseText;
    return '—';
  }

  Color _modeColor(String mode) {
    switch (mode.toLowerCase()) {
      case 'follow':
        return Colors.greenAccent;
      case 'manual':
        return Colors.orangeAccent;
      case 'stopped':
        return Colors.white70;
      default:
        return Colors.white54;
    }
  }

  Color _boolColor(
    dynamic v, {
    Color trueColor = Colors.greenAccent,
    Color falseColor = Colors.white70,
  }) {
    if (v == true || v?.toString().toLowerCase() == 'true') return trueColor;
    if (v == false || v?.toString().toLowerCase() == 'false') return falseColor;
    return Colors.white54;
  }

  String _commandLabel(String cmd) {
    switch (cmd.toLowerCase()) {
      case 'stop':
        return 'Stop';
      case 'forward':
        return 'Forward';
      case 'backward':
        return 'Backward';
      case 'left':
        return 'Strafe Left';
      case 'right':
        return 'Strafe Right';
      case 'front_left':
        return 'Front Left';
      case 'front_right':
        return 'Front Right';
      case 'back_left':
        return 'Back Left';
      case 'back_right':
        return 'Back Right';
      case 'turn_left':
        return 'Turn Left';
      case 'turn_right':
        return 'Turn Right';
      case 'follow_start':
        return 'Follow Start';
      case 'follow_stop':
        return 'Follow Stop';
      case 'follow_mode':
        return 'Follow Mode';
      case 'manual_mode_wait':
        return 'Manual Wait';
      case 'manual_gimbal':
        return 'Manual Gimbal';
      case 'gimbal_center':
        return 'Gimbal Center';
      default:
        return cmd.isEmpty ? '—' : cmd;
    }
  }

  Widget _statusCard(
    String title,
    String value,
    String sub,
    IconData icon, {
    Color valueColor = Colors.white,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF1F2937)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: Colors.white70),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: valueColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: valueColor,
                        ),
                      ),
                    ),
                  ],
                ),
                if (sub.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    sub,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        text,
        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
      ),
    );
  }

  Widget _ctrlBtn({
    required IconData icon,
    VoidCallback? onTap,
    VoidCallback? onPressDown,
    VoidCallback? onPressUp,
    double size = 76,
    Color bgColor = const Color(0xFFC4B0EA),
    Color fgColor = const Color(0xFF2A1F3D),
  }) {
    return GestureDetector(
      onTapDown: (_) {
        if (onPressDown != null) onPressDown();
      },
      onTapUp: (_) {
        if (onPressUp != null) onPressUp();
      },
      onTapCancel: () {
        if (onPressUp != null) onPressUp();
      },
      onTap: onTap,
      child: SizedBox(
        width: size,
        height: size,
        child: AbsorbPointer(
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: bgColor,
              foregroundColor: fgColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
              ),
              padding: EdgeInsets.zero,
              elevation: 0,
            ),
            onPressed: () {},
            child: Icon(icon, size: 30),
          ),
        ),
      ),
    );
  }

  Widget _buildDrivePad() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF1F2937)),
      ),
      child: Column(
        children: [
          const Text(
            'Drive',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _ctrlBtn(
                icon: Icons.north_west_rounded,
                onPressDown: () => _sendMove('front_left'),
                onPressUp: stopRobot,
                size: 64,
              ),
              const SizedBox(width: 8),
              _ctrlBtn(
                icon: Icons.keyboard_arrow_up_rounded,
                onPressDown: () => _sendMove('forward'),
                onPressUp: stopRobot,
                size: 72,
              ),
              const SizedBox(width: 8),
              _ctrlBtn(
                icon: Icons.north_east_rounded,
                onPressDown: () => _sendMove('front_right'),
                onPressUp: stopRobot,
                size: 64,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _ctrlBtn(
                icon: Icons.rotate_left_rounded,
                onPressDown: () => _sendMove('turn_left'),
                onPressUp: stopRobot,
                size: 62,
              ),
              const SizedBox(width: 8),
              _ctrlBtn(
                icon: Icons.keyboard_arrow_left_rounded,
                onPressDown: () => _sendMove('left'),
                onPressUp: stopRobot,
                size: 72,
              ),
              const SizedBox(width: 8),
              _ctrlBtn(
                icon: Icons.stop_rounded,
                onTap: stopRobot,
                size: 82,
                bgColor: const Color(0xFFEF4444),
                fgColor: Colors.white,
              ),
              const SizedBox(width: 8),
              _ctrlBtn(
                icon: Icons.keyboard_arrow_right_rounded,
                onPressDown: () => _sendMove('right'),
                onPressUp: stopRobot,
                size: 72,
              ),
              const SizedBox(width: 8),
              _ctrlBtn(
                icon: Icons.rotate_right_rounded,
                onPressDown: () => _sendMove('turn_right'),
                onPressUp: stopRobot,
                size: 62,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _ctrlBtn(
                icon: Icons.south_west_rounded,
                onPressDown: () => _sendMove('back_left'),
                onPressUp: stopRobot,
                size: 64,
              ),
              const SizedBox(width: 8),
              _ctrlBtn(
                icon: Icons.keyboard_arrow_down_rounded,
                onPressDown: () => _sendMove('backward'),
                onPressUp: stopRobot,
                size: 72,
              ),
              const SizedBox(width: 8),
              _ctrlBtn(
                icon: Icons.south_east_rounded,
                onPressDown: () => _sendMove('back_right'),
                onPressUp: stopRobot,
                size: 64,
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Press and hold to move',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildGimbalPad() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF1F2937)),
      ),
      child: Column(
        children: [
          const Text(
            'Gimbal',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _ctrlBtn(
                icon: Icons.keyboard_arrow_up_rounded,
                onTap: () => _sendGimbal('up'),
                size: 64,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _ctrlBtn(
                icon: Icons.keyboard_arrow_left_rounded,
                onTap: () => _sendGimbal('left'),
                size: 64,
              ),
              const SizedBox(width: 8),
              _ctrlBtn(
                icon: Icons.center_focus_strong_rounded,
                onTap: gimbalCenter,
                size: 76,
                bgColor: const Color(0xFF8B5CF6),
                fgColor: Colors.white,
              ),
              const SizedBox(width: 8),
              _ctrlBtn(
                icon: Icons.keyboard_arrow_right_rounded,
                onTap: () => _sendGimbal('right'),
                size: 64,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _ctrlBtn(
                icon: Icons.keyboard_arrow_down_rounded,
                onTap: () => _sendGimbal('down'),
                size: 64,
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Tap to nudge camera',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewAndControls(bool wideLayout) {
    final preview = Container(
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF1F2937)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Image.network(
            ApiClient.instance.robotSnapshotUrl,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            filterQuality: FilterQuality.low,
            errorBuilder: (context, error, stackTrace) {
              return Container(
                color: const Color(0xFF111827),
                child: const Center(
                  child: Text('Unable to load robot preview'),
                ),
              );
            },
          ),
        ),
      ),
    );

    final controls = Column(
      children: [
        _buildDrivePad(),
        const SizedBox(height: 14),
        _buildGimbalPad(),
      ],
    );

    if (!wideLayout) {
      return Column(
        children: [
          preview,
          const SizedBox(height: 16),
          controls,
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 7,
          child: preview,
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 4,
          child: controls,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final rawMode = status['mode']?.toString() ?? '';
    final rawLastCmd = status['last_cmd']?.toString() ?? '';
    final rawFollowEnabled = status['follow_enabled'];
    final rawObstacle = status['obstacle'];
    final rawFollowMode =
        status['follow_mode']?.toString() ?? selectedFollowMode;

    final mode = _modeLabel(rawMode);
    final followModeLabel = _followModeLabel(rawFollowMode);
    final lastCmd = _commandLabel(rawLastCmd);
    final lastMsg = status['last_msg']?.toString() ?? '—';
    final followEnabled = _boolLabel(
      rawFollowEnabled,
      trueText: 'Enabled',
      falseText: 'Disabled',
    );
    final obstacle = _boolLabel(
      rawObstacle,
      trueText: 'Detected',
      falseText: 'Clear',
    );

    final modeColor = _modeColor(rawMode);
    final followColor = _boolColor(rawFollowEnabled);
    final obstacleColor = _boolColor(
      rawObstacle,
      trueColor: Colors.redAccent,
      falseColor: Colors.greenAccent,
    );

    final pan = status['pan_pulse'] as int?;
    final tilt = status['tilt_pulse'] as int?;
    final distanceCm = status['distance_cm'];
    final batteryVoltage = status['battery_voltage'];
    final posture = status['posture']?.toString() ?? '—';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Robot Manager'),
        actions: [
          IconButton(
            onPressed: () => refreshStatus(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
              builder: (context, constraints) {
                final wideLayout = constraints.maxWidth >= 1100;

                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: ListView(
                    children: [
                      _buildPreviewAndControls(wideLayout),
                      const SizedBox(height: 18),
                      if (error.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            error,
                            style: const TextStyle(color: Colors.redAccent),
                          ),
                        ),
                      GridView.count(
                        crossAxisCount: constraints.maxWidth >= 1000 ? 3 : 2,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        childAspectRatio:
                            constraints.maxWidth >= 1000 ? 2.7 : 2.35,
                        children: [
                          _statusCard(
                            'Mode',
                            mode,
                            followModeLabel,
                            Icons.settings_suggest_outlined,
                            valueColor: modeColor,
                          ),
                          _statusCard(
                            'Last Command',
                            lastCmd,
                            '',
                            Icons.play_arrow_outlined,
                          ),
                          _statusCard(
                            'Follow',
                            followEnabled,
                            '',
                            Icons.person_search_outlined,
                            valueColor: followColor,
                          ),
                          _statusCard(
                            'Obstacle',
                            obstacle,
                            '',
                            Icons.warning_amber_rounded,
                            valueColor: obstacleColor,
                          ),
                          _statusCard(
                            'Pan',
                            pan?.toString() ?? '—',
                            _panLabel(pan),
                            Icons.swap_horiz_rounded,
                          ),
                          _statusCard(
                            'Tilt',
                            tilt?.toString() ?? '—',
                            _tiltLabel(tilt),
                            Icons.swap_vert_rounded,
                          ),
                          _statusCard(
                            'Distance',
                            distanceCm?.toString() ?? '—',
                            'cm',
                            Icons.straighten_rounded,
                          ),
                          _statusCard(
                            'Battery',
                            batteryVoltage?.toString() ?? '—',
                            'voltage',
                            Icons.battery_full_rounded,
                          ),
                          _statusCard(
                            'Posture',
                            posture,
                            '',
                            Icons.accessibility_new_rounded,
                          ),
                          _statusCard(
                            'Person In View',
                            _boolLabel(
                              status['person_visible'],
                              trueText: 'Visible',
                              falseText: 'Not Visible',
                            ),
                            '',
                            Icons.visibility_outlined,
                            valueColor: _boolColor(
                              status['person_visible'],
                              trueColor: Colors.cyanAccent,
                              falseColor: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      _sectionTitle('Auto Follow'),
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: const Color(0xFF111827),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: const Color(0xFF1F2937)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.track_changes_outlined,
                                    color: Colors.white70),
                                SizedBox(width: 10),
                                Text(
                                  'Follow Mode',
                                  style: TextStyle(
                                      fontSize: 18, fontWeight: FontWeight.w700),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            SegmentedButton<String>(
                              segments: const [
                                ButtonSegment<String>(
                                  value: 'full_follow',
                                  label: Text('Full Follow'),
                                  icon: Icon(Icons.directions_car_filled_rounded),
                                ),
                                ButtonSegment<String>(
                                  value: 'gimbal_only',
                                  label: Text('Gimbal Only'),
                                  icon: Icon(Icons.videocam_rounded),
                                ),
                              ],
                              selected: {selectedFollowMode},
                              onSelectionChanged: (values) async {
                                final mode = values.first;
                                await setFollowMode(mode);
                              },
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: FilledButton.icon(
                                    onPressed: () => startFollow(selectedFollowMode),
                                    icon: const Icon(Icons.play_arrow_rounded),
                                    label: const Text('Start'),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: FilledButton.icon(
                                    onPressed: stopFollow,
                                    icon: const Icon(Icons.pause_rounded),
                                    label: const Text('Stop'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      _sectionTitle('Last Message'),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF111827),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFF1F2937)),
                        ),
                        child: Text(
                          lastMsg,
                          style: const TextStyle(
                            color: Colors.white70,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}