import 'package:flutter/material.dart';
import 'core/app/app_navigator.dart';
import 'core/auth/session_store.dart';
import 'core/reminders/reminder_service.dart';
import 'core/alerts/fall_event_service.dart';
import 'pages/auth/login_page.dart';
import 'pages/dashboard/dashboard_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ReminderService.instance.init();
  await FallEventService.instance.init();
  runApp(const SmartVehicleApp());
}

class SmartVehicleApp extends StatelessWidget {
  const SmartVehicleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: appNavigatorKey,
      title: 'Smart Vehicle',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: const Color(0xFF0B0F17),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF8B5CF6),
          brightness: Brightness.dark,
        ),
      ),
      home: ValueListenableBuilder<String?>(
        valueListenable: SessionStore.tokenNotifier,
        builder: (context, token, child) {
          if (token == null || token.isEmpty) {
            FallEventService.instance.resetSessionState();
            return const LoginPage();
          }
          return const DashboardPage();
        },
      ),
    );
  }
}