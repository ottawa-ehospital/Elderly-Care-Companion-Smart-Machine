import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../live/live_page.dart';
import '../falls/falls_page.dart';
import '../vitals/vitals_page.dart';
import '../meds/meds_page.dart';
import '../robot/robot_page.dart';
import '../profile/profile_page.dart';
import '../../core/auth/session_store.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  bool loadingSummary = true;
  Map<String, dynamic>? summary;

  @override
  void initState() {
    super.initState();
    loadSummary();
  }

  Future<void> loadSummary({bool silent = false}) async {
    if (!silent) {
      setState(() {
        loadingSummary = true;
      });
    }

    try {
      final data = await ApiClient.instance.getDashboardSummary();
      if (!mounted) return;

      setState(() {
        summary = data;
        loadingSummary = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        loadingSummary = false;
      });

      final msg = e.toString().toLowerCase();

      if (msg.contains('401') || msg.contains('unauthorized')) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Refresh failed: $e')),
      );
    }
  }

  Future<void> _open(BuildContext context, Widget page) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => page),
    );

    if (!mounted) return;
    if (!SessionStore.isLoggedIn) return;

    await loadSummary();
  }

  Future<void> _logoutNow() async {
    await ApiClient.instance.logout();
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  String formatApiTime(String? iso) {
    if (iso == null || iso.isEmpty) return '—';
    try {
      final dt = DateTime.parse(iso).toLocal();
      final y = dt.year.toString().padLeft(4, '0');
      final m = dt.month.toString().padLeft(2, '0');
      final d = dt.day.toString().padLeft(2, '0');
      final hh = dt.hour.toString().padLeft(2, '0');
      final mm = dt.minute.toString().padLeft(2, '0');
      return '$y-$m-$d  $hh:$mm';
    } catch (_) {
      return iso;
    }
  }

  String latestFallTitle() {
    final item = summary?['latest_fall'] as Map<String, dynamic>?;
    if (item == null) return 'No recent fall';
    final reason = item['reason']?.toString() ?? 'Fall detected';
    return reason;
  }

  String latestFallTime() {
    final item = summary?['latest_fall'] as Map<String, dynamic>?;
    if (item == null) return '—';
    return formatApiTime(item['timestamp']?.toString());
  }

  String latestVitalTitle() {
    final item = summary?['latest_vital'] as Map<String, dynamic>?;
    if (item == null) return 'No recent vital';

    final source = item['source']?.toString() ?? 'vital';
    final heartRate = item['heart_rate']?.toString() ?? '—';
    final steps = item['steps']?.toString() ?? '—';
    final calories = item['calories']?.toString() ?? '—';
    final sleep = item['sleep']?.toString() ?? '—';

    return '${source.toUpperCase()} · HR $heartRate · Steps $steps · Cal $calories · Sleep $sleep';
  }

  String latestVitalTime() {
    final item = summary?['latest_vital'] as Map<String, dynamic>?;
    if (item == null) return '—';
    return formatApiTime(item['timestamp']?.toString());
  }

  String nextMedTitle() {
    final item = summary?['next_med'] as Map<String, dynamic>?;
    if (item == null) return 'No enabled reminder';
    final name = item['name']?.toString() ?? 'Medication';
    final dosage = item['dosage']?.toString() ?? '';
    if (dosage.isEmpty) return name;
    return '$name · $dosage';
  }

  String nextMedTime() {
    final item = summary?['next_med'] as Map<String, dynamic>?;
    if (item == null) return '—';
    final time = item['time_of_day']?.toString() ?? '—';
    return 'Next at $time';
  }

  @override
  Widget build(BuildContext context) {
    final cards = <_DashboardCardData>[
      _DashboardCardData(
        title: 'Live Monitoring',
        subtitle: 'Watch the camera feed and current posture status',
        icon: Icons.videocam_outlined,
        badge: 'Live',
        detailTitle: 'Open live page',
        detailTime: '',
        onTap: () => _open(context, const LivePage()),
      ),
      _DashboardCardData(
        title: 'Robot Manager',
        subtitle: 'Drive the robot, move the gimbal, and control follow mode',
        icon: Icons.smart_toy_outlined,
        badge: 'Control',
        detailTitle: 'Open robot controls',
        detailTime: '',
        onTap: () => _open(context, const RobotPage()),
      ),
      _DashboardCardData(
        title: 'Fall Events',
        subtitle: 'Review saved fall records and playback video clips',
        icon: Icons.warning_amber_rounded,
        badge: 'Events',
        detailTitle: loadingSummary ? 'Loading...' : latestFallTitle(),
        detailTime: loadingSummary ? '' : latestFallTime(),
        detailTitleColor: Colors.redAccent,
        detailTimeColor: const Color(0xFFFFB4B4),
        onTap: () => _open(context, const FallsPage()),
      ),
      _DashboardCardData(
        title: 'Vitals',
        subtitle: 'Check recent health metrics and wearable data',
        icon: Icons.favorite_border_rounded,
        badge: 'Health',
        detailTitle: loadingSummary ? 'Loading...' : latestVitalTitle(),
        detailTime: loadingSummary ? '' : latestVitalTime(),
        detailTitleColor: Colors.white,
        detailTimeColor: Colors.cyanAccent,
        onTap: () => _open(context, const VitalsPage()),
      ),
      _DashboardCardData(
        title: 'Med Reminders',
        subtitle: 'Manage medication reminders and schedules',
        icon: Icons.medication_outlined,
        badge: 'Reminder',
        detailTitle: loadingSummary ? 'Loading...' : nextMedTitle(),
        detailTime: loadingSummary ? '' : nextMedTime(),
        detailTitleColor: Colors.white,
        detailTimeColor: Colors.greenAccent,
        onTap: () => _open(context, const MedsPage()),
      ),
      _DashboardCardData(
        title: 'Profile',
        subtitle: 'View account info and bind your patient ID',
        icon: Icons.person_outline_rounded,
        badge: 'Account',
        detailTitle: 'Manage account settings',
        detailTime: '',
        onTap: () => _open(context, const ProfilePage()),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart Vehicle Dashboard'),
        actions: [
          IconButton(
            onPressed: () => loadSummary(),
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            onPressed: () => _open(context, const ProfilePage()),
            icon: const Icon(Icons.person_outline_rounded),
          ),
          IconButton(
            onPressed: _logoutNow,
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 980;
          final crossAxisCount = isWide ? 2 : 1;
          final aspectRatio = isWide ? 2.15 : 1.9;

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const _HeroSection(),
              const SizedBox(height: 18),
              const _QuickStatusRow(),
              const SizedBox(height: 22),
              const Text(
                'Main Features',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              GridView.builder(
                itemCount: cards.length,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 14,
                  childAspectRatio: aspectRatio,
                ),
                itemBuilder: (_, i) {
                  final item = cards[i];
                  return _DashboardCard(item: item);
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

class _HeroSection extends StatelessWidget {
  const _HeroSection();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFF1F2937)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: const Color(0xFF8B5CF6).withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.directions_car_filled_rounded,
              size: 34,
              color: Color(0xFFC4B0EA),
            ),
          ),
          const SizedBox(width: 18),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Smart Vehicle',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Monitor falls, review videos, track vitals, manage reminders, control the robot, and bind patient identity from one place.',
                  style: TextStyle(
                    color: Colors.white70,
                    height: 1.45,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickStatusRow extends StatelessWidget {
  const _QuickStatusRow();

  Widget _chip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.26)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _chip(
          icon: Icons.check_circle_outline,
          label: 'Desktop App Ready',
          color: Colors.greenAccent,
        ),
        _chip(
          icon: Icons.movie_outlined,
          label: 'Fall Video Playback',
          color: const Color(0xFFC4B0EA),
        ),
        _chip(
          icon: Icons.settings_remote_outlined,
          label: 'Robot Control Connected',
          color: Colors.orangeAccent,
        ),
      ],
    );
  }
}

class _DashboardCardData {
  final String title;
  final String subtitle;
  final String detailTitle;
  final String detailTime;
  final IconData icon;
  final String badge;
  final VoidCallback onTap;
  final Color detailTitleColor;
  final Color detailTimeColor;

  _DashboardCardData({
    required this.title,
    required this.subtitle,
    required this.detailTitle,
    required this.detailTime,
    required this.icon,
    required this.badge,
    required this.onTap,
    this.detailTitleColor = Colors.white,
    this.detailTimeColor = const Color(0xFFC4B0EA),
  });
}

class _DashboardCard extends StatefulWidget {
  final _DashboardCardData item;

  const _DashboardCard({required this.item});

  @override
  State<_DashboardCard> createState() => _DashboardCardState();
}

class _DashboardCardState extends State<_DashboardCard> {
  bool hovering = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;

    return MouseRegion(
      onEnter: (_) => setState(() => hovering = true),
      onExit: (_) => setState(() => hovering = false),
      child: AnimatedScale(
        duration: const Duration(milliseconds: 120),
        scale: hovering ? 1.01 : 1,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: item.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF111827),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: hovering
                    ? const Color(0xFF8B5CF6).withValues(alpha: 0.55)
                    : const Color(0xFF1F2937),
              ),
              boxShadow: hovering
                  ? const [
                      BoxShadow(
                        color: Color(0x1A8B5CF6),
                        blurRadius: 18,
                        offset: Offset(0, 8),
                      ),
                    ]
                  : const [],
            ),
            child: Row(
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: const Color(0xFF8B5CF6).withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(
                    item.icon,
                    size: 30,
                    color: const Color(0xFFC4B0EA),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          item.badge,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        item.title,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        item.subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white70,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (item.detailTitle.isNotEmpty)
                        Text(
                          item.detailTitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: item.detailTitleColor,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            height: 1.35,
                          ),
                        ),
                      if (item.detailTime.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          item.detailTime,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: item.detailTimeColor,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            height: 1.25,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.white54,
                  size: 30,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}