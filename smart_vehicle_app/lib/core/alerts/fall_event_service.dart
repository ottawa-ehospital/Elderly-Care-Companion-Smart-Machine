import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../api/api_client.dart';
import '../auth/session_store.dart';

class FallEventService {
  FallEventService._();
  static final instance = FallEventService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  Timer? _timer;

  bool _primed = false;
  int _lastSeenId = 0;

  Future<void> init() async {
    // Flutter Web does not support dart:io Platform checks or native local
    // notifications in the same way as mobile/desktop. For Web, skip native
    // notification initialization and only keep polling logic.
    if (kIsWeb) {
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        checkNewFallEvents();
      });
      return;
    }

    const darwin = DarwinInitializationSettings();

    const settings = InitializationSettings(
      iOS: darwin,
      macOS: darwin,
    );

    await _plugin.initialize(
      settings: settings,
    );

    if (Platform.isIOS) {
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
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      checkNewFallEvents();
    });
  }

  void resetSessionState() {
    _primed = false;
    _lastSeenId = 0;
  }

  Future<void> checkNewFallEvents() async {
    if (!SessionStore.isLoggedIn) {
      resetSessionState();
      return;
    }

    try {
      final data = await ApiClient.instance.getFalls();
      if (data.isEmpty) return;

      final ids = <int>[];
      for (final item in data) {
        final id = item['id'];
        if (id is int) {
          ids.add(id);
        }
      }

      if (ids.isEmpty) return;

      final latestId = ids.reduce((a, b) => a > b ? a : b);

      if (!_primed) {
        _lastSeenId = latestId;
        _primed = true;
        return;
      }

      if (latestId <= _lastSeenId) return;

      final newItems = data.where((item) {
        final id = item['id'];
        return id is int && id > _lastSeenId;
      }).toList();

      _lastSeenId = latestId;

      if (newItems.isEmpty) return;

      final newest = newItems.first;
      final newestId = newest['id'] is int ? newest['id'] as int : latestId;
      final reason = newest['reason']?.toString() ?? 'Fall detected';
      final count = newItems.length;

      final title = count == 1
          ? 'New Fall Event Detected'
          : '$count New Fall Events Detected';

      final body =
          count == 1 ? reason : 'Open the app to review the latest events';

      // Native local notifications are skipped on Flutter Web.
      if (!kIsWeb) {
        await _plugin.show(
          id: 900000 + newestId,
          title: title,
          body: body,
          notificationDetails: const NotificationDetails(
            iOS: DarwinNotificationDetails(),
            macOS: DarwinNotificationDetails(),
          ),
        );
      }
    } catch (_) {}
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}