import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../api/api_client.dart';
import '../auth/session_store.dart';
import '../app/app_navigator.dart';

class ReminderService {
  ReminderService._();
  static final instance = ReminderService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  Timer? _timer;
  final Set<String> _firedKeys = {};
  bool _dialogShowing = false;

  Future<void> init() async {
    // Flutter Web does not support dart:io Platform checks or native local
    // notification plugins in the same way as mobile/desktop. For web, we skip
    // plugin initialization and only keep the timer + foreground dialog logic.
    if (kIsWeb) {
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 30), (_) {
        checkDueReminders();
      });
      return;
    }

    const darwin = DarwinInitializationSettings(
      defaultPresentAlert: true,
      defaultPresentBadge: true,
      defaultPresentSound: true,
      defaultPresentBanner: true,
      defaultPresentList: true,
    );

    const settings = InitializationSettings(
      iOS: darwin,
      macOS: darwin,
    );

    await _plugin.initialize(
      settings: settings,
    );

    if (Platform.isIOS || Platform.isAndroid) {
      await _plugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          );
    } else if (Platform.isMacOS) {
      await _plugin
          .resolvePlatformSpecificImplementation<
              MacOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          );
    }

    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      checkDueReminders();
    });
  }

  Future<void> _showForegroundDialog({
    required String title,
    required String body,
  }) async {
    if (_dialogShowing) return;

    final context = appNavigatorKey.currentContext;
    if (context == null) return;

    _dialogShowing = true;

    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (dialogContext) {
          return AlertDialog(
            title: Text(title),
            content: Text(body),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('OK'),
              ),
            ],
          );
        },
      );
    } catch (_) {
      //
    } finally {
      _dialogShowing = false;
    }
  }

  Future<void> checkDueReminders() async {
    if (!SessionStore.isLoggedIn) return;

    try {
      final data = await ApiClient.instance.getMeds();
      final items = (data['items'] as List<dynamic>? ?? []);

      final now = DateTime.now();
      final hh = now.hour.toString().padLeft(2, '0');
      final mm = now.minute.toString().padLeft(2, '0');
      final current = '$hh:$mm';
      final dayKey =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      for (final item in items) {
        final enabled = item['enabled'] == true;
        final time = item['time_of_day']?.toString() ?? '';
        final id = item['id'];
        final name = item['name']?.toString() ?? 'Medication';
        final dosage = item['dosage']?.toString() ?? '';

        if (!enabled) continue;
        if (time != current) continue;

        final fireKey = '$dayKey-$id-$time';
        if (_firedKeys.contains(fireKey)) continue;

        _firedKeys.add(fireKey);

        final notifId = fireKey.hashCode & 0x7fffffff;
        const title = 'Medication Reminder';
        final body = dosage.isEmpty
            ? 'Time to take $name'
            : 'Time to take $name ($dosage)';

        // Native local notifications are skipped on Flutter Web.
        // The foreground dialog below can still appear on Web.
        if (!kIsWeb) {
          await _plugin.show(
            id: notifId,
            title: title,
            body: body,
            notificationDetails: const NotificationDetails(
              iOS: DarwinNotificationDetails(
                presentAlert: true,
                presentBadge: true,
                presentSound: true,
                presentBanner: true,
                presentList: true,
              ),
              macOS: DarwinNotificationDetails(
                presentAlert: true,
                presentBadge: true,
                presentSound: true,
                presentBanner: true,
                presentList: true,
              ),
            ),
          );
        }

        await _showForegroundDialog(
          title: title,
          body: body,
        );

        if (id is int) {
          try {
            await ApiClient.instance.markMedSent(id);
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}