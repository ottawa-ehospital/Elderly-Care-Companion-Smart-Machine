import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/api/api_client.dart';
import '../falls/falls_page.dart';
import '../robot/robot_page.dart';

class LivePage extends StatefulWidget {
  const LivePage({super.key});

  @override
  State<LivePage> createState() => _LivePageState();
}

class _LivePageState extends State<LivePage> {
  bool loading = true;
  String error = '';

  Map<String, dynamic>? vitalsData;
  Map<String, dynamic> robotStatus = {};
  List<dynamic> falls = [];

  DateTime? lastRefreshAt;

  Timer? _pollTimer;
  Timer? _snapshotTimer;


  @override
  void initState() {
    super.initState();

    refreshAll();

    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      await refreshAll(silent: true);
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

  Future<void> refreshAll({bool silent = false}) async {
    if (!silent) {
      setState(() {
        loading = true;
        error = '';
      });
    }

    try {
      final vitals = await ApiClient.instance.getVitals();
      final robot = await ApiClient.instance.getRobotStatus();
      final fallList = await ApiClient.instance.getFalls();

      if (!mounted) return;

      setState(() {
        vitalsData = vitals;
        robotStatus = robot;
        falls = fallList;
        lastRefreshAt = DateTime.now();
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = '$e';
        loading = false;
      });
    }
  }

  String fmtDateTime(DateTime? dt) {
    if (dt == null) return '—';
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    final ss = dt.second.toString().padLeft(2, '0');
    return '$y-$m-$d  $hh:$mm:$ss';
  }

  String fmtIso(String? iso) {
    if (iso == null || iso.isEmpty) return '—';
    try {
      final dt = DateTime.parse(iso).toLocal();
      return fmtDateTime(dt);
    } catch (_) {
      return iso;
    }
  }

  String boolLabel(dynamic v, {required String yes, required String no}) {
    if (v == true) return yes;
    if (v == false) return no;
    final s = v?.toString().toLowerCase();
    if (s == 'true') return yes;
    if (s == 'false') return no;
    return '—';
  }

  Color boolColor(
    dynamic v, {
    Color yesColor = Colors.greenAccent,
    Color noColor = Colors.white70,
  }) {
    if (v == true || v?.toString().toLowerCase() == 'true') return yesColor;
    if (v == false || v?.toString().toLowerCase() == 'false') return noColor;
    return Colors.white54;
  }

  Color modeColor(String mode) {
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

  String vitalSummary(Map<String, dynamic>? item) {
    if (item == null) return 'No vital record';

    final source = item['source']?.toString() ?? 'vital';
    final hr = item['heart_rate']?.toString() ?? '—';
    final steps = item['steps']?.toString() ?? '—';
    final calories = item['calories']?.toString() ?? '—';
    final sleep = item['sleep']?.toString() ?? '—';

    return '${source.toUpperCase()} · HR $hr · Steps $steps · Cal $calories · Sleep $sleep';
  }

  Widget infoCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    Color color = const Color(0xFFC4B0EA),
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF1F2937)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      height: 1.3,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget pill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget actionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
    Color color = const Color(0xFFC4B0EA),
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF111827),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF1F2937)),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(color: Colors.white60),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Colors.white54),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final latestOverall =
        vitalsData?['latest_overall'] as Map<String, dynamic>?;
    final overallVitalText = vitalSummary(latestOverall);

    final robotOnline = robotStatus['online'] == true;
    final robotMode = robotStatus['mode']?.toString() ?? '—';
    final lastCmd = robotStatus['last_cmd']?.toString() ?? '—';
    final personVisible = robotStatus['person_visible'];
    final followEnabled = robotStatus['follow_enabled'];
    final obstacle = robotStatus['obstacle'];

    final latestFall =
        falls.isNotEmpty ? falls.first as Map<String, dynamic> : null;
    final latestFallReason =
        latestFall?['reason']?.toString() ?? 'No recent fall event';
    final latestFallTime = fmtIso(latestFall?['timestamp']?.toString());

    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Monitoring'),
        actions: [
          IconButton(
            onPressed: () => refreshAll(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: error.isNotEmpty
                  ? Center(
                      child: Text(
                        error,
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(22),
                          child: AspectRatio(
                            aspectRatio: 16 / 9,
                            child: Image.network(
                              ApiClient.instance.liveSnapshotUrl,
                              fit: BoxFit.contain,
                              gaplessPlayback: true,
                              filterQuality: FilterQuality.low,
                              errorBuilder: (context, error, stackTrace) {
                                return Container(
                                  color: const Color(0xFF111827),
                                  child: const Center(
                                    child: Text('Unable to load live snapshot'),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            int crossAxisCount;
                            if (constraints.maxWidth < 700) {
                              crossAxisCount = 1;
                            } else if (constraints.maxWidth < 1100) {
                              crossAxisCount = 2;
                            } else {
                              crossAxisCount = 3;
                            }

                            return GridView.count(
                              crossAxisCount: crossAxisCount,
                              mainAxisSpacing: 12,
                              crossAxisSpacing: 12,
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              childAspectRatio:
                                  crossAxisCount == 1 ? 3.0 : 1.75,
                              children: [
                                infoCard(
                                  title: 'Robot API',
                                  value: robotOnline ? 'Available' : 'Unavailable',
                                  subtitle: robotStatus['last_msg']?.toString() ?? 'Status endpoint connection',
                                  icon: Icons.wifi_tethering_rounded,
                                  color: robotOnline ? Colors.greenAccent : Colors.redAccent,
                                ),
                                infoCard(
                                  title: 'Robot Mode',
                                  value: robotMode,
                                  subtitle: 'Last command: $lastCmd',
                                  icon: Icons.smart_toy_outlined,
                                  color: modeColor(robotMode),
                                ),
                                infoCard(
                                  title: 'Last Refresh',
                                  value: fmtDateTime(lastRefreshAt),
                                  subtitle: overallVitalText,
                                  icon: Icons.update_rounded,
                                  color: const Color(0xFFC4B0EA),
                                ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 18),
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
                              const Text(
                                'Robot Summary',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: [
                                  pill(
                                    boolLabel(
                                      followEnabled,
                                      yes: 'Follow On',
                                      no: 'Follow Off',
                                    ),
                                    boolColor(
                                      followEnabled,
                                      yesColor: Colors.greenAccent,
                                      noColor: Colors.white70,
                                    ),
                                  ),
                                  pill(
                                    boolLabel(
                                      obstacle,
                                      yes: 'Obstacle Alert',
                                      no: 'Obstacle Clear',
                                    ),
                                    boolColor(
                                      obstacle,
                                      yesColor: Colors.orangeAccent,
                                      noColor: Colors.greenAccent,
                                    ),
                                  ),
                                  pill(
                                    boolLabel(
                                      personVisible,
                                      yes: 'Person Visible',
                                      no: 'Person Not Visible',
                                    ),
                                    boolColor(
                                      personVisible,
                                      yesColor: Colors.cyanAccent,
                                      noColor: Colors.white70,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
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
                              const Text(
                                'Latest Fall Event',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                latestFallReason,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                latestFallTime,
                                style: const TextStyle(color: Colors.white60),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        actionCard(
                          title: 'Open Robot Manager',
                          subtitle: 'Control the robot and view live preview',
                          icon: Icons.gamepad_rounded,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const RobotPage(),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 12),
                        actionCard(
                          title: 'Open Fall Events',
                          subtitle: 'Review fall videos and event history',
                          icon: Icons.warning_amber_rounded,
                          color: Colors.redAccent,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const FallsPage(),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
            ),
    );
  }
}