import 'package:flutter/foundation.dart';
import 'dart:io' show Platform;

class ApiConfig {
  static String get baseUrl {
    // Chrome
    if (kIsWeb) {
      return 'http://127.0.0.1:5050';
    }

    // macOS
    if (Platform.isMacOS) {
      return 'http://127.0.0.1:5050';
    }

    // iOS
    if (Platform.isIOS) {
      return 'http://127.0.0.1:5050';
    }

    // Android / other
    return 'http://127.0.0.1:5050';
  }
}