import 'package:flutter/material.dart';
import '../../core/api/api_client.dart';

class MedsPage extends StatefulWidget {
  const MedsPage({super.key});

  @override
  State<MedsPage> createState() => _MedsPageState();
}

class _MedsPageState extends State<MedsPage> {
  bool loading = true;
  String error = '';
  int count = 0;
  List<dynamic> items = [];

  @override
  void initState() {
    super.initState();
    loadMeds();
  }

  Future<void> loadMeds() async {
    setState(() {
      loading = true;
      error = '';
    });

    try {
      final data = await ApiClient.instance.getMeds();
      if (!mounted) return;

      setState(() {
        count = (data['count'] ?? 0) as int;
        items = (data['items'] as List<dynamic>? ?? []);
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

  Future<void> openMedEditor({Map<String, dynamic>? item}) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => MedEditorPage(item: item),
      ),
    );

    if (changed == true) {
      await loadMeds();
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(item == null ? 'Reminder added' : 'Reminder updated'),
        ),
      );
    }
  }

  Future<void> deleteMed(int id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete Reminder'),
          content: const Text('Are you sure you want to delete this reminder?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      await ApiClient.instance.deleteMed(id);
      await loadMeds();
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reminder deleted')),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: $e')),
      );
    }
  }

  Future<void> toggleMed(int id) async {
    try {
      await ApiClient.instance.toggleMed(id);
      await loadMeds();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Toggle failed: $e')),
      );
    }
  }

  Widget summaryCard({
    required String title,
    required String value,
    required String sub,
    required IconData icon,
    Color color = const Color(0xFFC4B0EA),
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
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 6),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  sub,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget pill(String text, {Color color = const Color(0xFFC4B0EA)}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
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
          fontSize: 12,
        ),
      ),
    );
  }

  Widget medCard(dynamic item) {
    final enabled = item['enabled'] == true;
    final name = item['name']?.toString() ?? 'Unnamed';
    final dosage = item['dosage']?.toString() ?? '';
    final time = item['time_of_day']?.toString() ?? '—';

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
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: const Color(0xFFC4B0EA).withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.medication_outlined,
                  color: Color(0xFFC4B0EA),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Switch(
                value: enabled,
                onChanged: (_) => toggleMed(item['id'] as int),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              pill('Time: $time'),
              if (dosage.isNotEmpty) pill('Dosage: $dosage'),
              pill(
                enabled ? 'Enabled' : 'Disabled',
                color: enabled ? Colors.greenAccent : Colors.white70,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: () => openMedEditor(item: Map<String, dynamic>.from(item)),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Edit'),
              ),
              OutlinedButton.icon(
                onPressed: () => deleteMed(item['id'] as int),
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
    final enabledCount = items.where((e) => e['enabled'] == true).length;
    final disabledCount = items.where((e) => e['enabled'] != true).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Med Reminders'),
        actions: [
          IconButton(
            onPressed: () => openMedEditor(),
            icon: const Icon(Icons.add),
          ),
          IconButton(
            onPressed: loadMeds,
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
                              childAspectRatio: crossAxisCount == 1 ? 3.2 : 2.15,
                              children: [
                                summaryCard(
                                  title: 'Total Reminders',
                                  value: '$count',
                                  sub: 'All medication reminders',
                                  icon: Icons.list_alt_rounded,
                                  color: const Color(0xFFC4B0EA),
                                ),
                                summaryCard(
                                  title: 'Disabled',
                                  value: '$disabledCount',
                                  sub: 'Currently paused reminders',
                                  icon: Icons.notifications_off_outlined,
                                  color: Colors.orangeAccent,
                                ),
                                summaryCard(
                                  title: 'Enabled',
                                  value: '$enabledCount',
                                  sub: 'Currently active reminders',
                                  icon: Icons.notifications_active_outlined,
                                  color: Colors.greenAccent,
                                ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'Medication Schedule',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (items.isEmpty)
                          const Text('No medication reminders')
                        else
                          ...items.map((item) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: medCard(item),
                            );
                          }),
                      ],
                    ),
            ),
    );
  }
}

class MedEditorPage extends StatefulWidget {
  final Map<String, dynamic>? item;

  const MedEditorPage({super.key, this.item});

  @override
  State<MedEditorPage> createState() => _MedEditorPageState();
}

class _MedEditorPageState extends State<MedEditorPage> {
  late final TextEditingController nameController;
  late final TextEditingController dosageController;

  late TimeOfDay selectedTime;
  late bool enabled;

  bool saving = false;
  String error = '';

  bool get editing => widget.item != null;

  @override
  void initState() {
    super.initState();

    nameController =
        TextEditingController(text: widget.item?['name']?.toString() ?? '');
    dosageController =
        TextEditingController(text: widget.item?['dosage']?.toString() ?? '');

    final initialTime = widget.item?['time_of_day']?.toString() ?? '08:00';
    final parts = initialTime.split(':');
    final hour = int.tryParse(parts.isNotEmpty ? parts[0] : '08') ?? 8;
    final minute = int.tryParse(parts.length > 1 ? parts[1] : '00') ?? 0;

    selectedTime = TimeOfDay(hour: hour, minute: minute);
    enabled = widget.item?['enabled'] == true;
  }

  @override
  void dispose() {
    nameController.dispose();
    dosageController.dispose();
    super.dispose();
  }

  String get selectedTimeText {
    final hh = selectedTime.hour.toString().padLeft(2, '0');
    final mm = selectedTime.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  Future<void> pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: selectedTime,
    );

    if (picked == null || !mounted) return;

    setState(() {
      selectedTime = picked;
    });
  }

  Future<void> save() async {
    final name = nameController.text.trim();
    final dosage = dosageController.text.trim();

    if (name.isEmpty) {
      setState(() {
        error = 'Medication name is required';
      });
      return;
    }

    final hh = selectedTime.hour.toString().padLeft(2, '0');
    final mm = selectedTime.minute.toString().padLeft(2, '0');
    final timeOfDay = '$hh:$mm';

    setState(() {
      saving = true;
      error = '';
    });

    try {
      if (editing) {
        await ApiClient.instance.updateMed(
          id: widget.item!['id'] as int,
          name: name,
          dosage: dosage,
          timeOfDay: timeOfDay,
          enabled: enabled,
        );
      } else {
        await ApiClient.instance.createMed(
          name: name,
          dosage: dosage,
          timeOfDay: timeOfDay,
          enabled: enabled,
        );
      }

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        saving = false;
        error = 'Failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? 'Edit Reminder' : 'Add Reminder'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF111827),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: const Color(0xFF1F2937)),
                ),
                child: Column(
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Medication Name',
                        hintText: 'e.g. Vitamin D',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: dosageController,
                      decoration: const InputDecoration(
                        labelText: 'Dosage',
                        hintText: 'e.g. 1 tablet',
                      ),
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: saving ? null : pickTime,
                      borderRadius: BorderRadius.circular(12),
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Time',
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.schedule_outlined, size: 18),
                            const SizedBox(width: 8),
                            Text(
                              selectedTimeText,
                              style: const TextStyle(fontSize: 16),
                            ),
                            const Spacer(),
                            const Text(
                              'Choose',
                              style: TextStyle(color: Colors.white54),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      value: enabled,
                      onChanged: saving
                          ? null
                          : (v) {
                              setState(() {
                                enabled = v;
                              });
                            },
                      title: const Text('Enabled'),
                      contentPadding: EdgeInsets.zero,
                    ),
                    if (error.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          error,
                          style: const TextStyle(
                            color: Colors.redAccent,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: saving ? null : () => Navigator.pop(context, false),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: saving ? null : save,
                            child: Text(saving ? 'Saving...' : 'Save'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}