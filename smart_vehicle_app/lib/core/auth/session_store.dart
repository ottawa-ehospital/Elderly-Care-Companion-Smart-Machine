import 'package:flutter/foundation.dart';

class SessionStore {
  static final ValueNotifier<String?> tokenNotifier = ValueNotifier<String?>(null);
  static final ValueNotifier<Map<String, dynamic>?> userNotifier =
      ValueNotifier<Map<String, dynamic>?>(null);

  static String? get token => tokenNotifier.value;
  static Map<String, dynamic>? get user => userNotifier.value;

  static bool get isLoggedIn => token != null && token!.isNotEmpty;

  static void setSession({
    required String token,
    required Map<String, dynamic> user,
  }) {
    tokenNotifier.value = token;
    userNotifier.value = user;
  }

  static void clear() {
    tokenNotifier.value = null;
    userNotifier.value = null;
  }
}