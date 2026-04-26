import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/api/api_client.dart';

class VitalsPage extends StatefulWidget {
  const VitalsPage({super.key});

  @override
  State<VitalsPage> createState() => _VitalsPageState();
}

class _VitalsPageState extends State<VitalsPage> {
  bool loading = true;
  String error = '';

  Map<String, dynamic>? latestManual;
  Map<String, dynamic>? latestWearable;
  List<dynamic> manualRecords = [];
  List<dynamic> wearableRecords = [];
  int? patientId;

  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    loadVitals();
    _refreshTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      loadVitals(silent: true);
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> loadVitals({bool silent = false}) async {
    if (!silent) {
      setState(() {
        loading = true;
        error = '';
      });
    }

    try {
      final data = await ApiClient.instance.getVitals();
      if (!mounted) return;

      setState(() {
        patientId = data['patient_id'] as int?;
        latestManual = data['latest_manual'] as Map<String, dynamic>?;
        latestWearable = data['latest_wearable'] as Map<String, dynamic>?;
        manualRecords = (data['manual_records'] as List<dynamic>? ?? []);
        wearableRecords = (data['wearable_records'] as List<dynamic>? ?? []);
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

  Future<void> createManualVital() async {
    final heartRateController = TextEditingController();
    final stepsController = TextEditingController();
    final caloriesController = TextEditingController();
    final sleepController = TextEditingController();
    final notesController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        bool saving = false;
        String dialogError = '';

        return StatefulBuilder(
          builder: (dialogContext2, setLocalState) {
            Future<void> save() async {
              final heartRateText = heartRateController.text.trim();
              final stepsText = stepsController.text.trim();
              final caloriesText = caloriesController.text.trim();
              final sleepText = sleepController.text.trim();
              final notesText = notesController.text.trim();

              if (heartRateText.isEmpty &&
                  stepsText.isEmpty &&
                  caloriesText.isEmpty &&
                  sleepText.isEmpty &&
                  notesText.isEmpty) {
                setLocalState(() {
                  dialogError = 'Please enter at least one value';
                });
                return;
              }

              final int? heartRate =
                  heartRateText.isEmpty ? null : int.tryParse(heartRateText);
              final int? steps =
                  stepsText.isEmpty ? null : int.tryParse(stepsText);
              final int? calories =
                  caloriesText.isEmpty ? null : int.tryParse(caloriesText);
              final double? sleep =
                  sleepText.isEmpty ? null : double.tryParse(sleepText);

              if (heartRateText.isNotEmpty && heartRate == null) {
                setLocalState(() {
                  dialogError = 'Heart Rate must be a number';
                });
                return;
              }
              if (stepsText.isNotEmpty && steps == null) {
                setLocalState(() {
                  dialogError = 'Steps must be a number';
                });
                return;
              }
              if (caloriesText.isNotEmpty && calories == null) {
                setLocalState(() {
                  dialogError = 'Calories must be a number';
                });
                return;
              }
              if (sleepText.isNotEmpty && sleep == null) {
                setLocalState(() {
                  dialogError = 'Sleep must be a number';
                });
                return;
              }

              setLocalState(() {
                saving = true;
                dialogError = '';
              });

              try {
                await ApiClient.instance.createManualVital(
                  heartRate: heartRate,
                  steps: steps,
                  calories: calories,
                  sleep: sleep,
                  notes: notesText,
                );

                if (!dialogContext.mounted) return;
                Navigator.of(dialogContext).pop(true);
              } catch (e) {
                if (!dialogContext.mounted) return;
                setLocalState(() {
                  saving = false;
                  dialogError = 'Failed: $e';
                });
              }
            }

            return AlertDialog(
              title: const Text('Add Manual Vital'),
              content: SizedBox(
                width: 440,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: heartRateController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Heart Rate',
                          hintText: 'Optional',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: stepsController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Steps',
                          hintText: 'Optional',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: caloriesController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Calories',
                          hintText: 'Optional',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: sleepController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Sleep',
                          hintText: 'Optional, e.g. 7.5',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: notesController,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Notes',
                          hintText: 'Optional notes',
                        ),
                      ),
                      if (dialogError.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            dialogError,
                            style: const TextStyle(
                              color: Colors.redAccent,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving
                      ? null
                      : () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: saving ? null : save,
                  child: Text(saving ? 'Saving...' : 'Save'),
                ),
              ],
            );
          },
        );
      },
    );

    heartRateController.dispose();
    stepsController.dispose();
    caloriesController.dispose();
    sleepController.dispose();
    notesController.dispose();

    if (result == true) {
      await loadVitals();
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Manual vital added')),
      );
    }
  }

  String val(dynamic v, {String suffix = ''}) {
    if (v == null) return '—';
    return '$v$suffix';
  }

  String fmtTime(String? iso) {
    if (iso == null || iso.isEmpty) return '—';
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.year.toString().padLeft(4, '0')}-'
          '${dt.month.toString().padLeft(2, '0')}-'
          '${dt.day.toString().padLeft(2, '0')}  '
          '${dt.hour.toString().padLeft(2, '0')}:'
          '${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }

  Widget _metricLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        '$label: $value',
        style: const TextStyle(color: Colors.white70, height: 1.35),
      ),
    );
  }

  Widget latestCard({
    required String title,
    required Map<String, dynamic>? item,
    required VoidCallback onTap,
    required IconData icon,
    required Color color,
  }) {
    final time = fmtTime(item?['timestamp']?.toString());

    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFF111827),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFF1F2937)),
        ),
        child: Row(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: item == null
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          'No record',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                        ),
                        SizedBox(height: 6),
                        Text(
                          'Tap to open list',
                          style: TextStyle(color: Colors.white54),
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 8),
                        _metricLine('Time', time),
                        _metricLine('Heart Rate', val(item['heart_rate'], suffix: ' bpm')),
                        _metricLine('Steps', val(item['steps'])),
                        _metricLine('Calories', val(item['calories'])),
                        _metricLine('Sleep', val(item['sleep'])),
                      ],
                    ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right_rounded, color: Colors.white54),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vitals'),
        actions: [
          IconButton(
            onPressed: createManualVital,
            icon: const Icon(Icons.add),
          ),
          IconButton(
            onPressed: () => loadVitals(),
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
                  : ListView(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF111827),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFF1F2937)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.local_hospital_outlined, color: Colors.greenAccent),
                              const SizedBox(width: 10),
                              Text(
                                'Patient ID: ${patientId?.toString() ?? "Not set"}',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        latestCard(
                          title: 'Latest Manual Vital',
                          item: latestManual,
                          icon: Icons.edit_note_rounded,
                          color: Colors.orangeAccent,
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => VitalsSourceListPage(
                                  title: 'Manual Vitals',
                                  records: manualRecords,
                                  allowDelete: true,
                                ),
                              ),
                            );
                            await loadVitals(silent: true);
                          },
                        ),
                        const SizedBox(height: 14),
                        latestCard(
                          title: 'Latest API / Wearable Vital',
                          item: latestWearable,
                          icon: Icons.wifi_tethering_rounded,
                          color: Colors.cyanAccent,
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => VitalsSourceListPage(
                                  title: 'API / Wearable Vitals',
                                  records: wearableRecords,
                                  allowDelete: false,
                                ),
                              ),
                            );
                            await loadVitals(silent: true);
                          },
                        ),
                      ],
                    ),
            ),
    );
  }
}

class VitalsSourceListPage extends StatefulWidget {
  final String title;
  final List<dynamic> records;
  final bool allowDelete;

  const VitalsSourceListPage({
    super.key,
    required this.title,
    required this.records,
    required this.allowDelete,
  });

  @override
  State<VitalsSourceListPage> createState() => _VitalsSourceListPageState();
}

class _VitalsSourceListPageState extends State<VitalsSourceListPage> {
  late List<dynamic> records;

  @override
  void initState() {
    super.initState();
    records = List<dynamic>.from(widget.records);
  }

  String val(dynamic v, {String suffix = ''}) {
    if (v == null) return '—';
    return '$v$suffix';
  }

  String fmtTime(String? iso) {
    if (iso == null || iso.isEmpty) return '—';
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.year.toString().padLeft(4, '0')}-'
          '${dt.month.toString().padLeft(2, '0')}-'
          '${dt.day.toString().padLeft(2, '0')}  '
          '${dt.hour.toString().padLeft(2, '0')}:'
          '${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }

  Future<void> deleteManualVital(int id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete Manual Vital'),
          content: const Text('Are you sure you want to delete this manual record?'),
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
      await ApiClient.instance.deleteManualVital(id);
      setState(() {
        records.removeWhere((e) => e['id'] == id);
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Manual vital deleted')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: $e')),
      );
    }
  }

  Widget chip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1220),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF243041)),
      ),
      child: Text(
        '$label: $value',
        style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: records.isEmpty
            ? const Center(child: Text('No records'))
            : ListView.builder(
                itemCount: records.length,
                itemBuilder: (context, index) {
                  final item = records[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: const Color(0xFF111827),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: const Color(0xFF1F2937)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  fmtTime(item['timestamp']?.toString()),
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              if (widget.allowDelete && item['id'] != null)
                                IconButton(
                                  onPressed: () => deleteManualVital(item['id'] as int),
                                  icon: const Icon(Icons.delete_outline),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              chip('Heart Rate', val(item['heart_rate'], suffix: ' bpm')),
                              chip('Steps', val(item['steps'])),
                              chip('Calories', val(item['calories'])),
                              chip('Sleep', val(item['sleep'])),
                              chip('Source', val(item['source'])),
                              if ((item['notes']?.toString() ?? '').isNotEmpty)
                                chip('Notes', item['notes'].toString()),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}