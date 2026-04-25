import 'dart:convert';
import 'package:http/http.dart' as http;
import '../auth/session_store.dart';
import 'api_config.dart';

class ApiClient {
  ApiClient._();
  static final instance = ApiClient._();

  String get baseUrl => ApiConfig.baseUrl;

  Map<String, String> _headers({bool jsonBody = false}) {
    final headers = <String, String>{};
    if (jsonBody) {
      headers['Content-Type'] = 'application/json';
    }
    final token = SessionStore.token;
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  dynamic _tryDecodeBody(String body) {
    try {
      return jsonDecode(body);
    } catch (_) {
      return null;
    }
  }

  String _extractErrorMessage(http.Response resp, {String fallback = 'Request failed'}) {
    final decoded = _tryDecodeBody(resp.body);

    if (decoded is Map<String, dynamic>) {
      final error = decoded['error']?.toString();
      final message = decoded['message']?.toString();

      if (error != null && error.trim().isNotEmpty) return error.trim();
      if (message != null && message.trim().isNotEmpty) return message.trim();
    }

    final raw = resp.body.trim();
    if (raw.isNotEmpty && raw.length < 200) {
      return raw;
    }

    return fallback;
  }

  Exception _buildAuthException(http.Response resp, {required bool isRegister}) {
    final msg = _extractErrorMessage(
      resp,
      fallback: isRegister ? 'Unable to create account' : 'Unable to sign in',
    ).toLowerCase();

    if (isRegister) {
      if (msg.contains('email already exists') ||
          msg.contains('already exists') ||
          msg.contains('duplicate')) {
        return Exception('This email is already registered');
      }
      if (msg.contains('patient id')) {
        return Exception('Patient ID is invalid');
      }
      return Exception('Unable to create account');
    } else {
      if (msg.contains('invalid email or password') ||
          msg.contains('incorrect email or password') ||
          msg.contains('invalid password') ||
          msg.contains('invalid credentials')) {
        return Exception('Incorrect email or password');
      }
      return Exception('Unable to sign in');
    }
  }

  String snapshotUrl({bool bustCache = true}) {
    if (!bustCache) return '$baseUrl/api/live/snapshot';
    return '$baseUrl/api/live/snapshot?ts=${DateTime.now().millisecondsSinceEpoch}';
  }

  String get liveSnapshotUrl =>
      '$baseUrl/api/live/snapshot?ts=${DateTime.now().millisecondsSinceEpoch}';

  String get robotSnapshotUrl =>
      '$baseUrl/api/live/snapshot?ts=${DateTime.now().millisecondsSinceEpoch}';

  String get liveMjpegUrl => '$baseUrl/api/live/stream';
  String get robotMjpegUrl => '$baseUrl/api/live/stream';

  Future<Map<String, dynamic>> health() async {
    final resp = await http.get(Uri.parse('$baseUrl/health'));
    if (resp.statusCode != 200) {
      throw Exception('health failed: ${resp.statusCode}');
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final resp = await http.post(
      Uri.parse('$baseUrl/api/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'password': password,
      }),
    );

    if (resp.statusCode != 200) {
      throw _buildAuthException(resp, isRegister: false);
    }

    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> register({
    required String email,
    required String password,
    int? patientId,
  }) async {
    final body = <String, dynamic>{
      'email': email,
      'password': password,
    };
    if (patientId != null) {
      body['patient_id'] = patientId;
    }

    final resp = await http.post(
      Uri.parse('$baseUrl/api/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );

    if (resp.statusCode != 200) {
      throw _buildAuthException(resp, isRegister: true);
    }

    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> me() async {
    final resp = await http.get(
      Uri.parse('$baseUrl/api/auth/me'),
      headers: _headers(),
    );
    if (resp.statusCode != 200) {
      throw Exception('me failed: ${resp.statusCode}');
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<void> logout() async {
    try {
      await http.post(
        Uri.parse('$baseUrl/api/auth/logout'),
        headers: _headers(),
      );
    } catch (_) {}
    SessionStore.clear();
  }

  Future<Map<String, dynamic>> getFallDetail(int id) async {
    final resp = await http.get(
      Uri.parse('$baseUrl/api/falls/$id'),
      headers: _headers(),
    );
    if (resp.statusCode != 200) {
      throw Exception('getFallDetail failed: ${resp.statusCode}');
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getLiveStatus() async {
    final resp = await http.get(
      Uri.parse('$baseUrl/api/live/status'),
      headers: _headers(),
    );
    if (resp.statusCode != 200) {
      throw Exception('getLiveStatus failed: ${resp.statusCode}');
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> robotMove(String cmd) async {
    final resp = await http.post(
      Uri.parse('$baseUrl/api/robot/move'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'cmd': cmd}),
    );
    if (resp.statusCode != 200) {
      throw Exception('robotMove failed: ${resp.statusCode} ${resp.body}');
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> robotStop() async {
    final resp = await http.post(Uri.parse('$baseUrl/api/robot/stop'));
    if (resp.statusCode != 200) {
      throw Exception('robotStop failed: ${resp.statusCode}');
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> robotFollowStart(String mode) async {
    final resp = await http.post(
      Uri.parse('$baseUrl/api/robot/follow/start'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'mode': mode}),
    );
    if (resp.statusCode != 200) {
      throw Exception('robotFollowStart failed: ${resp.statusCode} ${resp.body}');
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> robotFollowMode(String mode) async {
    final resp = await http.post(
      Uri.parse('$baseUrl/api/robot/follow/mode'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'mode': mode}),
    );
    if (resp.statusCode != 200) {
      throw Exception('robotFollowMode failed: ${resp.statusCode} ${resp.body}');
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> robotFollowStop() async {
    final resp = await http.post(Uri.parse('$baseUrl/api/robot/follow/stop'));
    if (resp.statusCode != 200) {
      throw Exception('robotFollowStop failed: ${resp.statusCode}');
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> robotGimbalMove(String direction) async {
    final resp = await http.post(
      Uri.parse('$baseUrl/api/robot/gimbal/move'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'direction': direction}),
    );
    if (resp.statusCode != 200) {
      throw Exception('robotGimbalMove failed: ${resp.statusCode} ${resp.body}');
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> robotGimbalCenter() async {
    final resp = await http.post(Uri.parse('$baseUrl/api/robot/gimbal/center'));
    if (resp.statusCode != 200) {
      throw Exception('robotGimbalCenter failed: ${resp.statusCode}');
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<List<dynamic>> getFalls() async {
    final resp = await http.get(
      Uri.parse('$baseUrl/api/falls'),
      headers: _headers(),
    );
    if (resp.statusCode != 200) {
      throw Exception('getFalls failed: ${resp.statusCode} ${resp.body}');
    }
    return jsonDecode(resp.body) as List<dynamic>;
  }

  Future<Map<String, dynamic>> deleteFall(int id) async {
    final resp = await http.delete(
      Uri.parse('$baseUrl/api/falls/$id'),
      headers: _headers(),
    );
    if (resp.statusCode != 200) {
      throw Exception('deleteFall failed: ${resp.statusCode} ${resp.body}');
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getRobotStatus() async {
    final resp = await http.get(
      Uri.parse('$baseUrl/api/robot/status'),
      headers: _headers(),
    );
    if (resp.statusCode != 200) {
      throw Exception('getRobotStatus failed: ${resp.statusCode} ${resp.body}');
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getVitals() async {
    final resp = await http.get(
      Uri.parse('$baseUrl/api/vitals'),
      headers: _headers(),
    );
    if (resp.statusCode != 200) {
      throw Exception('getVitals failed: ${resp.statusCode}');
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getMeds() async {
    final resp = await http.get(
      Uri.parse('$baseUrl/api/meds'),
      headers: _headers(),
    );
    if (resp.statusCode != 200) {
      throw Exception('getMeds failed: ${resp.statusCode}');
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getDashboardSummary() async {
    final resp = await http.get(
      Uri.parse('$baseUrl/api/dashboard/summary'),
      headers: _headers(),
    );
    if (resp.statusCode != 200) {
      throw Exception('getDashboardSummary failed: ${resp.statusCode} ${resp.body}');
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getProfile() async {
    final resp = await http.get(
      Uri.parse('$baseUrl/api/profile'),
      headers: _headers(),
    );
    if (resp.statusCode != 200) {
      throw Exception('getProfile failed: ${resp.statusCode}');
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> setPatientId(int patientId) async {
    final resp = await http.put(
      Uri.parse('$baseUrl/api/profile/patient-id'),
      headers: _headers(jsonBody: true),
      body: jsonEncode({'patient_id': patientId}),
    );
    if (resp.statusCode != 200) {
      throw Exception('setPatientId failed: ${resp.statusCode} ${resp.body}');
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> createMed({
    required String name,
    required String dosage,
    required String timeOfDay,
    bool enabled = true,
  }) async {
    final resp = await http.post(
      Uri.parse('$baseUrl/api/meds'),
      headers: _headers(jsonBody: true),
      body: jsonEncode({
        'name': name,
        'dosage': dosage,
        'time_of_day': timeOfDay,
        'enabled': enabled,
      }),
    );
    if (resp.statusCode != 200) {
      throw Exception('createMed failed: ${resp.statusCode} ${resp.body}');
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateMed({
    required int id,
    required String name,
    required String dosage,
    required String timeOfDay,
    required bool enabled,
  }) async {
    final resp = await http.put(
      Uri.parse('$baseUrl/api/meds/$id'),
      headers: _headers(jsonBody: true),
      body: jsonEncode({
        'name': name,
        'dosage': dosage,
        'time_of_day': timeOfDay,
        'enabled': enabled,
      }),
    );
    if (resp.statusCode != 200) {
      throw Exception('updateMed failed: ${resp.statusCode} ${resp.body}');
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> deleteMed(int id) async {
    final resp = await http.delete(
      Uri.parse('$baseUrl/api/meds/$id'),
      headers: _headers(),
    );
    if (resp.statusCode != 200) {
      throw Exception('deleteMed failed: ${resp.statusCode} ${resp.body}');
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> toggleMed(int id) async {
    final resp = await http.post(
      Uri.parse('$baseUrl/api/meds/$id/toggle'),
      headers: _headers(),
    );
    if (resp.statusCode != 200) {
      throw Exception('toggleMed failed: ${resp.statusCode} ${resp.body}');
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> markMedSent(int id) async {
    final resp = await http.post(
      Uri.parse('$baseUrl/api/meds/$id/mark-sent'),
      headers: _headers(),
    );
    if (resp.statusCode != 200) {
      throw Exception('markMedSent failed: ${resp.statusCode} ${resp.body}');
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> confirmMed({
    required int id,
    required String confirmedBy,
  }) async {
    final resp = await http.post(
      Uri.parse('$baseUrl/api/meds/$id/confirm'),
      headers: _headers(jsonBody: true),
      body: jsonEncode({
        'confirmed_by': confirmedBy,
      }),
    );
    if (resp.statusCode != 200) {
      throw Exception('confirmMed failed: ${resp.statusCode} ${resp.body}');
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> createManualVital({
    int? heartRate,
    int? steps,
    int? calories,
    double? sleep,
    String notes = '',
  }) async {
    final resp = await http.post(
      Uri.parse('$baseUrl/api/vitals/manual'),
      headers: _headers(jsonBody: true),
      body: jsonEncode({
        'heart_rate': heartRate,
        'steps': steps,
        'calories': calories,
        'sleep': sleep,
        'notes': notes,
      }),
    );
    if (resp.statusCode != 200) {
      throw Exception('createManualVital failed: ${resp.statusCode} ${resp.body}');
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> deleteManualVital(int id) async {
    final resp = await http.delete(
      Uri.parse('$baseUrl/api/vitals/manual/$id'),
      headers: _headers(),
    );
    if (resp.statusCode != 200) {
      throw Exception('deleteManualVital failed: ${resp.statusCode} ${resp.body}');
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateEmail({
    required String newEmail,
    required String currentPassword,
  }) async {
    final resp = await http.put(
      Uri.parse('$baseUrl/api/profile/email'),
      headers: _headers(jsonBody: true),
      body: jsonEncode({
        'new_email': newEmail,
        'current_password': currentPassword,
      }),
    );
    if (resp.statusCode != 200) {
      throw Exception('updateEmail failed: ${resp.statusCode} ${resp.body}');
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updatePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final resp = await http.put(
      Uri.parse('$baseUrl/api/profile/password'),
      headers: _headers(jsonBody: true),
      body: jsonEncode({
        'current_password': currentPassword,
        'new_password': newPassword,
      }),
    );
    if (resp.statusCode != 200) {
      throw Exception('updatePassword failed: ${resp.statusCode} ${resp.body}');
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> deleteAccount({
    required String currentPassword,
  }) async {
    final resp = await http.delete(
      Uri.parse('$baseUrl/api/profile/account'),
      headers: _headers(jsonBody: true),
      body: jsonEncode({
        'current_password': currentPassword,
      }),
    );
    if (resp.statusCode != 200) {
      throw Exception('deleteAccount failed: ${resp.statusCode} ${resp.body}');
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }
}