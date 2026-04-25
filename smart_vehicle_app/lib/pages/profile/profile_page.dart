import 'package:flutter/material.dart';
import '../../core/api/api_client.dart';
import '../../core/auth/session_store.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  bool loading = true;
  bool savingPatientId = false;
  bool savingEmail = false;
  bool savingPassword = false;
  bool deletingAccount = false;
  String error = '';

  Map<String, dynamic>? user;

  final TextEditingController patientIdController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController emailPasswordController = TextEditingController();

  final TextEditingController currentPasswordController = TextEditingController();
  final TextEditingController newPasswordController = TextEditingController();
  final TextEditingController deletePasswordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    loadProfile();
  }

  @override
  void dispose() {
    patientIdController.dispose();
    emailController.dispose();
    emailPasswordController.dispose();
    currentPasswordController.dispose();
    newPasswordController.dispose();
    deletePasswordController.dispose();
    super.dispose();
  }

  Future<void> loadProfile() async {
    setState(() {
      loading = true;
      error = '';
    });

    try {
      final data = await ApiClient.instance.getProfile();
      final profileUser = data['user'] as Map<String, dynamic>?;

      setState(() {
        user = profileUser;
        patientIdController.text = profileUser?['patient_id']?.toString() ?? '';
        emailController.text = profileUser?['email']?.toString() ?? '';
        loading = false;
      });
    } catch (e) {
      setState(() {
        error = '$e';
        loading = false;
      });
    }
  }

  Future<void> savePatientId() async {
    final text = patientIdController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a patient ID')),
      );
      return;
    }

    final parsed = int.tryParse(text);
    if (parsed == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Patient ID must be an integer')),
      );
      return;
    }

    setState(() {
      savingPatientId = true;
      error = '';
    });

    try {
      final result = await ApiClient.instance.setPatientId(parsed);
      final updatedUser = result['user'] as Map<String, dynamic>?;

      setState(() {
        user = updatedUser;
        patientIdController.text = updatedUser?['patient_id']?.toString() ?? '';
        savingPatientId = false;
      });

      SessionStore.userNotifier.value = updatedUser;

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Patient ID updated successfully')),
      );
    } catch (e) {
      setState(() {
        savingPatientId = false;
        error = '$e';
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update patient ID: $e')),
      );
    }
  }

  Future<void> saveEmail() async {
    final newEmail = emailController.text.trim();
    final password = emailPasswordController.text;

    if (newEmail.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a new email')),
      );
      return;
    }
    if (password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your current password')),
      );
      return;
    }

    setState(() {
      savingEmail = true;
      error = '';
    });

    try {
      final result = await ApiClient.instance.updateEmail(
        newEmail: newEmail,
        currentPassword: password,
      );
      final updatedUser = result['user'] as Map<String, dynamic>?;

      setState(() {
        user = updatedUser;
        emailController.text = updatedUser?['email']?.toString() ?? '';
        emailPasswordController.clear();
        savingEmail = false;
      });

      SessionStore.userNotifier.value = updatedUser;

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Email updated successfully')),
      );
    } catch (e) {
      setState(() {
        savingEmail = false;
        error = '$e';
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update email: $e')),
      );
    }
  }

  Future<void> savePassword() async {
    final currentPassword = currentPasswordController.text;
    final newPassword = newPasswordController.text;

    if (currentPassword.isEmpty || newPassword.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill both password fields')),
      );
      return;
    }

    setState(() {
      savingPassword = true;
      error = '';
    });

    try {
      await ApiClient.instance.updatePassword(
        currentPassword: currentPassword,
        newPassword: newPassword,
      );

      setState(() {
        currentPasswordController.clear();
        newPasswordController.clear();
        savingPassword = false;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password updated successfully')),
      );
    } catch (e) {
      setState(() {
        savingPassword = false;
        error = '$e';
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update password: $e')),
      );
    }
  }

  Future<void> deleteAccount() async {
    final password = deletePasswordController.text;
    if (password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your current password')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete Account'),
          content: const Text(
            'Are you sure you want to permanently delete this account?\n\n'
            'This will delete your profile, manual vitals, fall events, and medication reminders.\n\n'
            'This action cannot be undone.',
          ),
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

    setState(() {
      deletingAccount = true;
      error = '';
    });

    try {
      await ApiClient.instance.deleteAccount(currentPassword: password);
      deletePasswordController.clear();

      if (!mounted) return;
      await ApiClient.instance.logout();

      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
        final friendly = _friendlyError(e);

        setState(() {
          deletingAccount = false;
        });

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendly)),
        );
      }
  }

  Future<void> _logoutNow() async {
    await ApiClient.instance.logout();
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  String fmt(String? value) {
    if (value == null || value.isEmpty) return '—';
    return value;
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

  String _friendlyError(Object e) {
    final msg = e.toString().toLowerCase();

    if (msg.contains('current password is incorrect')) {
      return 'Current password is incorrect';
    }
    if (msg.contains('unauthorized') || msg.contains('401')) {
      return 'Authentication failed';
    }
    if (msg.contains('network') || msg.contains('socket')) {
      return 'Network error. Please try again';
    }
    return 'Something went wrong. Please try again';
  }

  Widget infoCard({
    required String title,
    required String value,
    required String subtitle,
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
                Text(title, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 6),
                Text(
                  value,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget sectionCard({
    required String title,
    required String subtitle,
    required List<Widget> children,
    Color borderColor = const Color(0xFF1F2937),
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: const TextStyle(color: Colors.white70, height: 1.45),
          ),
          const SizedBox(height: 18),
          ...children,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final email = user?['email']?.toString() ?? '—';
    final userId = user?['id']?.toString() ?? '—';
    final patientId = user?['patient_id']?.toString() ?? 'Not set';
    final createdAt = formatApiTime(user?['created_at']?.toString());

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            onPressed: loadProfile,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            onPressed: _logoutNow,
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: ListView(
                children: [
                  if (error.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        error,
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                    ),
                  GridView.count(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    childAspectRatio: 2.3,
                    children: [
                      infoCard(
                        title: 'Email',
                        value: fmt(email),
                        subtitle: 'Current account email',
                        icon: Icons.mail_outline,
                      ),
                      infoCard(
                        title: 'User ID',
                        value: fmt(userId),
                        subtitle: 'Internal account id',
                        icon: Icons.badge_outlined,
                        color: Colors.orangeAccent,
                      ),
                      infoCard(
                        title: 'Patient ID',
                        value: fmt(patientId),
                        subtitle: 'Linked patient identity',
                        icon: Icons.local_hospital_outlined,
                        color: Colors.greenAccent,
                      ),
                      infoCard(
                        title: 'Created At',
                        value: createdAt,
                        subtitle: 'Account creation time',
                        icon: Icons.schedule_outlined,
                        color: Colors.cyanAccent,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  sectionCard(
                    title: 'Bind Patient ID',
                    subtitle: 'Link this account to your patient ID so wearable vitals, fall events, and related records can be associated correctly.',
                    children: [
                      TextField(
                        controller: patientIdController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Patient ID',
                          hintText: 'Enter patient ID, e.g. 1001',
                          filled: true,
                          fillColor: const Color(0xFF0B1220),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: savingPatientId ? null : savePatientId,
                          icon: savingPatientId
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.save_outlined),
                          label: Text(savingPatientId ? 'Saving...' : 'Save Patient ID'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  sectionCard(
                    title: 'Change Email',
                    subtitle: 'Update the login email for this account.',
                    children: [
                      TextField(
                        controller: emailController,
                        decoration: InputDecoration(
                          labelText: 'New Email',
                          filled: true,
                          fillColor: const Color(0xFF0B1220),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: emailPasswordController,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: 'Current Password',
                          filled: true,
                          fillColor: const Color(0xFF0B1220),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: savingEmail ? null : saveEmail,
                          icon: savingEmail
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.alternate_email),
                          label: Text(savingEmail ? 'Saving...' : 'Save Email'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  sectionCard(
                    title: 'Change Password',
                    subtitle: 'Use your current password to set a new one.',
                    children: [
                      TextField(
                        controller: currentPasswordController,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: 'Current Password',
                          filled: true,
                          fillColor: const Color(0xFF0B1220),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: newPasswordController,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: 'New Password',
                          filled: true,
                          fillColor: const Color(0xFF0B1220),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: savingPassword ? null : savePassword,
                          icon: savingPassword
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.lock_reset),
                          label: Text(savingPassword ? 'Saving...' : 'Save Password'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  sectionCard(
                    title: 'Delete Account',
                    subtitle: 'Permanently delete this account and all locally stored account data. This action cannot be undone.',
                    borderColor: Colors.redAccent.withValues(alpha: 0.5),
                    children: [
                      TextField(
                        controller: deletePasswordController,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: 'Current Password',
                          hintText: 'Enter password to confirm deletion',
                          filled: true,
                          fillColor: const Color(0xFF0B1220),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: deletingAccount ? null : deleteAccount,
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.redAccent,
                            foregroundColor: Colors.white,
                          ),
                          icon: deletingAccount
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.delete_forever_rounded),
                          label: Text(deletingAccount ? 'Deleting...' : 'Delete Account'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }
}