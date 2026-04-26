import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../core/api/api_client.dart';

class FallsPage extends StatefulWidget {
  const FallsPage({super.key});

  @override
  State<FallsPage> createState() => _FallsPageState();
}

class _FallsPageState extends State<FallsPage> {
  bool loading = true;
  String error = '';
  List<dynamic> items = [];

  @override
  void initState() {
    super.initState();
    loadFalls();
  }

  Future<void> loadFalls() async {
    setState(() {
      loading = true;
      error = '';
    });

    try {
      final data = await ApiClient.instance.getFalls();
      setState(() {
        items = data;
        loading = false;
      });
    } catch (e) {
      setState(() {
        error = '$e';
        loading = false;
      });
    }
  }

  String fmtTime(String? iso) {
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

  Future<void> deleteItem(int id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete Fall Event'),
          content: const Text('Delete this fall event and its video?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      await ApiClient.instance.deleteFall(id);
      await loadFalls();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fall event deleted')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: $e')),
      );
    }
  }

  Widget eventCard(dynamic item) {
    final id = item['id'] as int?;
    final timestamp = fmtTime(item['timestamp']?.toString());
    final reason = item['reason']?.toString() ?? 'Fall event';
    final videoUrl = item['video_url']?.toString();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF1F2937)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            reason,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            timestamp,
            style: const TextStyle(color: Colors.white60),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              if (videoUrl != null && videoUrl.isNotEmpty)
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => FallVideoPage(videoUrl: videoUrl),
                      ),
                    );
                  },
                  icon: const Icon(Icons.play_circle_outline),
                  label: const Text('Open Video'),
                ),
              if (videoUrl != null && videoUrl.isNotEmpty)
                const SizedBox(width: 10),
              if (id != null)
                OutlinedButton.icon(
                  onPressed: () => deleteItem(id),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Delete'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fall Events'),
        actions: [
          IconButton(
            onPressed: loadFalls,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: error.isNotEmpty
                  ? Center(child: Text(error, textAlign: TextAlign.center))
                  : items.isEmpty
                      ? const Center(child: Text('No fall events'))
                      : ListView.separated(
                          itemCount: items.length,
                          separatorBuilder: (context, index) => const SizedBox(height: 12),
                          itemBuilder: (_, i) => eventCard(items[i]),
                        ),
            ),
    );
  }
}

class FallVideoPage extends StatefulWidget {
  final String videoUrl;

  const FallVideoPage({super.key, required this.videoUrl});

  @override
  State<FallVideoPage> createState() => _FallVideoPageState();
}

class _FallVideoPageState extends State<FallVideoPage> {
  VideoPlayerController? controller;
  bool loading = true;
  String error = '';

  @override
  void initState() {
    super.initState();
    initVideo();
  }

  Future<void> initVideo() async {
    try {
      final c = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
      await c.initialize();

      setState(() {
        controller = c;
        loading = false;
      });
    } catch (e) {
      setState(() {
        error = '$e';
        loading = false;
      });
    }
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (h > 0) {
      return '$h:$m:$s';
    }
    return '${d.inMinutes}:$s';
  }

  @override
  Widget build(BuildContext context) {
    final c = controller;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fall Video'),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error.isNotEmpty
              ? Center(child: Text(error))
              : c == null
                  ? const Center(child: Text('Video unavailable'))
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final maxVideoHeight = constraints.maxHeight * 0.62;

                        return SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxHeight: maxVideoHeight,
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(18),
                                  child: AspectRatio(
                                    aspectRatio: c.value.aspectRatio,
                                    child: VideoPlayer(c),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              VideoProgressIndicator(
                                c,
                                allowScrubbing: true,
                                padding: const EdgeInsets.symmetric(vertical: 8),
                              ),
                              const SizedBox(height: 8),
                              ValueListenableBuilder(
                                valueListenable: c,
                                builder: (context, value, child) {
                                  final pos = value.position;
                                  final dur = value.duration;

                                  return Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        _fmt(pos),
                                        style: const TextStyle(
                                          color: Colors.white70,
                                        ),
                                      ),
                                      Text(
                                        _fmt(dur),
                                        style: const TextStyle(
                                          color: Colors.white70,
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                              const SizedBox(height: 16),
                              Wrap(
                                spacing: 12,
                                runSpacing: 12,
                                alignment: WrapAlignment.center,
                                children: [
                                  FilledButton.icon(
                                    onPressed: () async {
                                      if (c.value.isPlaying) {
                                        await c.pause();
                                      } else {
                                        await c.play();
                                      }
                                      setState(() {});
                                    },
                                    icon: Icon(
                                      c.value.isPlaying
                                          ? Icons.pause
                                          : Icons.play_arrow,
                                    ),
                                    label: Text(
                                      c.value.isPlaying ? 'Pause' : 'Play',
                                    ),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: () async {
                                      await c.seekTo(Duration.zero);
                                      await c.pause();
                                      setState(() {});
                                    },
                                    icon: const Icon(Icons.restart_alt),
                                    label: const Text('Restart'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
    );
  }
}