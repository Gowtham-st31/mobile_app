import 'dart:convert';
import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:path_provider/path_provider.dart';

import '../models/profile_summary.dart';
import '../models/graph_data.dart';
import '../models/report.dart';
import '../models/announcement.dart';
import '../models/warp_history.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;

  const ApiException(this.message, {this.statusCode});

  @override
  String toString() => 'ApiException(statusCode: $statusCode, message: $message)';
}

class LoginResult {
  final String role;

  const LoginResult({required this.role});
}

class ApiClient {
  final Dio _dio;

  ApiClient._(this._dio);

  static Future<ApiClient> create({required String baseUrl}) async {
    final dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(seconds: 30),
        headers: {
          'Accept': 'application/json',
        },
      ),
    );

    final appDir = await getApplicationSupportDirectory();
    final cookiePath = '${appDir.path}${Platform.pathSeparator}cookies';
    final cookieJar = PersistCookieJar(storage: FileStorage(cookiePath));
    dio.interceptors.add(CookieManager(cookieJar));

    return ApiClient._(dio);
  }

  Future<LoginResult> login({required String username, required String password}) async {
    try {
      final response = await _dio.post(
        '/authenticate',
        data: FormData.fromMap({
          'username': username,
          'password': password,
        }),
      );

      final data = (response.data as Map).cast<String, dynamic>();
      if (data['status'] == 'success') {
        return LoginResult(role: (data['role'] ?? '').toString());
      }
      throw ApiException((data['message'] ?? 'Login failed').toString(), statusCode: response.statusCode);
    } on DioException catch (e) {
      final message = _extractMessage(e) ?? _friendlyNetworkMessage(e) ?? 'Login failed';
      throw ApiException(message, statusCode: e.response?.statusCode);
    }
  }

  String? _friendlyNetworkMessage(DioException e) {
    // Only use this when there is no response body to extract.
    if (e.response != null) return null;

    String? describeDetails() {
      final error = e.error;
      if (error is SocketException) {
        final os = error.osError?.message;
        final host = error.address?.host;
        final port = error.port;
        final target = [if (host != null && host.trim().isNotEmpty) host, if (port != 0) port.toString()].join(':');
        final parts = <String>[
          error.message.trim().isNotEmpty ? error.message.trim() : 'Socket error',
          if (os != null && os.trim().isNotEmpty) os.trim(),
          if (target.trim().isNotEmpty) 'target=$target',
        ];
        return parts.join(' | ');
      }

      final msg = (e.message ?? '').trim();
      if (msg.isNotEmpty) return msg;
      if (error != null) return error.toString();
      return null;
    }

    switch (e.type) {
      case DioExceptionType.connectionTimeout:
        return 'Connection timed out. The server may be starting up or unreachable.';
      case DioExceptionType.sendTimeout:
        return 'Request timed out while sending data.';
      case DioExceptionType.receiveTimeout:
        return 'Server took too long to respond.';
      case DioExceptionType.badCertificate:
        return 'Secure connection failed (bad certificate). ${describeDetails() ?? 'Check the server URL and HTTPS setup.'}';
      case DioExceptionType.connectionError:
        return 'Network error. ${describeDetails() ?? 'Check your internet connection and server URL.'}';
      case DioExceptionType.cancel:
        return 'Request was cancelled.';
      case DioExceptionType.badResponse:
        // Should have e.response; fall through.
        return null;
      case DioExceptionType.unknown:
        // Try to surface something helpful without being noisy.
        final details = describeDetails();
        if (details == null || details.trim().isEmpty) return 'Network error. Check your internet connection and server URL.';
        return 'Network error: $details';
    }
  }

  Future<void> logout() async {
    try {
      final response = await _dio.post('/logout');
      final data = (response.data as Map).cast<String, dynamic>();
      if (data['status'] == 'success') return;
      throw ApiException((data['message'] ?? 'Logout failed').toString(), statusCode: response.statusCode);
    } on DioException catch (e) {
      final message = _extractMessage(e) ?? 'Logout failed';
      throw ApiException(message, statusCode: e.response?.statusCode);
    }
  }

  Future<ProfileSummary> getProfileSummary() async {
    try {
      final response = await _dio.get('/profile/summary');
      final data = (response.data as Map).cast<String, dynamic>();
      if (data['status'] == 'success') {
        return ProfileSummary.fromJson(data);
      }
      throw ApiException((data['message'] ?? 'Failed to load profile').toString(), statusCode: response.statusCode);
    } on DioException catch (e) {
      final message = _extractMessage(e) ?? 'Failed to load profile';
      throw ApiException(message, statusCode: e.response?.statusCode);
    }
  }

  Future<void> addLoomData({
    required String loomerName,
    required String loomNumber,
    required String shift,
    required int meters,
    required double salaryPerMeter,
    required String dateYYYYMMDD,
  }) async {
    try {
      final response = await _dio.post(
        '/add_form',
        data: FormData.fromMap({
          'loomer_name': loomerName,
          'loom_number': loomNumber,
          'shift': shift,
          'meters': meters,
          'salary_per_meter': salaryPerMeter,
          'date': dateYYYYMMDD,
        }),
      );
      final data = (response.data as Map).cast<String, dynamic>();
      if (data['status'] == 'success') return;
      throw ApiException((data['message'] ?? 'Failed to add data').toString(), statusCode: response.statusCode);
    } on DioException catch (e) {
      final message = _extractMessage(e) ?? 'Failed to add data';
      throw ApiException(message, statusCode: e.response?.statusCode);
    }
  }

  Future<ReportResult> getMetersReport({
    required String loomerName,
    required String shift,
    required String loomNumber,
    required String fromDateYYYYMMDD,
    required String toDateYYYYMMDD,
  }) async {
    try {
      final response = await _dio.post(
        '/get_meters',
        data: FormData.fromMap({
          'loomer_name': loomerName,
          'shift': shift,
          'loom_number': loomNumber,
          'from_date': fromDateYYYYMMDD,
          'to_date': toDateYYYYMMDD,
        }),
      );

      final data = (response.data as Map).cast<String, dynamic>();
      if (data['status'] == 'success') {
        return ReportResult.fromJson(data);
      }
      throw ApiException((data['message'] ?? 'Failed to generate report').toString(), statusCode: response.statusCode);
    } on DioException catch (e) {
      final message = _extractMessage(e) ?? 'Failed to generate report';
      throw ApiException(message, statusCode: e.response?.statusCode);
    }
  }

  Future<GraphData> getGraphData({
    required String loomerName,
    required String period,
    required String fromDateYYYYMMDD,
    required String toDateYYYYMMDD,
  }) async {
    try {
      final response = await _dio.post(
        '/get_graph_data',
        data: FormData.fromMap({
          'loomer_name': loomerName,
          'period': period,
          'from_date': fromDateYYYYMMDD,
          'to_date': toDateYYYYMMDD,
        }),
      );

      final data = (response.data as Map).cast<String, dynamic>();
      if (data['status'] == 'success') {
        return GraphData.fromJson(data);
      }
      throw ApiException((data['message'] ?? 'Failed to load graph data').toString(), statusCode: response.statusCode);
    } on DioException catch (e) {
      final message = _extractMessage(e) ?? 'Failed to load graph data';
      throw ApiException(message, statusCode: e.response?.statusCode);
    }
  }

  Future<File> downloadReportPdf({
    required String loomerName,
    required String shift,
    required String fromDateYYYYMMDD,
    required String toDateYYYYMMDD,
    required int totalMeters,
    required String totalSalary,
  }) async {
    try {
      final response = await _dio.get(
        '/download_report_pdf',
        queryParameters: {
          'loomer': loomerName,
          'shift': shift,
          'from_date': fromDateYYYYMMDD,
          'to_date': toDateYYYYMMDD,
          'total_meters': totalMeters.toString(),
          'total_salary': totalSalary,
        },
        options: Options(
          responseType: ResponseType.bytes,
          headers: const {
            'Accept': 'application/pdf, application/json',
          },
        ),
      );

      final contentType = response.headers.value('content-type') ?? '';
      final bytes = (response.data as List).cast<int>();

      if (contentType.contains('application/json')) {
        final text = utf8.decode(bytes);
        final json = jsonDecode(text);
        if (json is Map && json['message'] != null) {
          throw ApiException(json['message'].toString(), statusCode: response.statusCode);
        }
        throw ApiException('PDF download failed', statusCode: response.statusCode);
      }

      if (!contentType.contains('application/pdf')) {
        throw ApiException('Unexpected response while downloading PDF', statusCode: response.statusCode);
      }

      final dir = await getApplicationDocumentsDirectory();
      final safeFrom = fromDateYYYYMMDD.replaceAll(':', '-');
      final safeTo = toDateYYYYMMDD.replaceAll(':', '-');
      final file = File('${dir.path}${Platform.pathSeparator}report_${safeFrom}_$safeTo.pdf');
      await file.writeAsBytes(bytes, flush: true);
      return file;
    } on DioException catch (e) {
      final status = e.response?.statusCode;

      // When responseType=bytes, errors might still be bytes. Try to decode JSON message.
      final data = e.response?.data;
      if (data is List<int>) {
        try {
          final text = utf8.decode(data);
          final json = jsonDecode(text);
          if (json is Map && json['message'] != null) {
            throw ApiException(json['message'].toString(), statusCode: status);
          }
        } catch (_) {
          // fall through
        }
      }

      final message = _extractMessage(e) ?? 'Failed to download PDF';
      throw ApiException(message, statusCode: status);
    }
  }

  Future<List<Map<String, dynamic>>> getUsers() async {
    try {
      final response = await _dio.get('/admin/get_users');
      final data = (response.data as Map).cast<String, dynamic>();
      if (data['status'] == 'success') {
        final users = (data['users'] as List? ?? const []).cast<dynamic>();
        return users.map((e) => (e as Map).cast<String, dynamic>()).toList(growable: false);
      }
      throw ApiException((data['message'] ?? 'Failed to load users').toString(), statusCode: response.statusCode);
    } on DioException catch (e) {
      final message = _extractMessage(e) ?? 'Failed to load users';
      throw ApiException(message, statusCode: e.response?.statusCode);
    }
  }

  Future<double> getCurrentWarp() async {
    try {
      final response = await _dio.get('/get_current_warp');
      final data = (response.data as Map).cast<String, dynamic>();
      if (data['status'] == 'success') {
        final v = data['total_warp'];
        if (v is num) return v.toDouble();
        return double.tryParse('$v') ?? 0.0;
      }
      throw ApiException((data['message'] ?? 'Failed to load current warp').toString(), statusCode: response.statusCode);
    } on DioException catch (e) {
      final message = _extractMessage(e) ?? 'Failed to load current warp';
      throw ApiException(message, statusCode: e.response?.statusCode);
    }
  }

  Future<double> updateWarp({
    required double valueChange,
    required String remarks,
    required String dateYYYYMMDD,
  }) async {
    try {
      final response = await _dio.post(
        '/update_warp',
        data: {
          'value': valueChange,
          'remarks': remarks,
          'date': dateYYYYMMDD,
        },
        options: Options(headers: {'Content-Type': 'application/json'}),
      );
      final data = (response.data as Map).cast<String, dynamic>();
      if (data['status'] == 'success') {
        final v = data['new_total_warp'];
        if (v is num) return v.toDouble();
        return double.tryParse('$v') ?? 0.0;
      }
      throw ApiException((data['message'] ?? 'Failed to update warp').toString(), statusCode: response.statusCode);
    } on DioException catch (e) {
      final message = _extractMessage(e) ?? 'Failed to update warp';
      throw ApiException(message, statusCode: e.response?.statusCode);
    }
  }

  Future<double> applyKnotting({
    required double knottingValue,
    required double currentTotalWarp,
  }) async {
    try {
      final response = await _dio.post(
        '/apply_knotting',
        data: {
          'knotting_value': knottingValue,
          'current_total_warp': currentTotalWarp,
        },
        options: Options(headers: {'Content-Type': 'application/json'}),
      );
      final data = (response.data as Map).cast<String, dynamic>();
      if (data['status'] == 'success') {
        final v = data['calculated_remaining_warp'];
        if (v is num) return v.toDouble();
        return double.tryParse('$v') ?? 0.0;
      }
      throw ApiException((data['message'] ?? 'Failed to calculate knotting').toString(), statusCode: response.statusCode);
    } on DioException catch (e) {
      final message = _extractMessage(e) ?? 'Failed to calculate knotting';
      throw ApiException(message, statusCode: e.response?.statusCode);
    }
  }

  Future<List<WarpHistoryRecord>> getWarpHistory() async {
    try {
      final response = await _dio.get('/get_warp_history');
      final data = (response.data as Map).cast<String, dynamic>();
      if (data['status'] == 'success') {
        final list = (data['history'] as List? ?? const []).cast<dynamic>();
        return list
            .map((e) => WarpHistoryRecord.fromJson((e as Map).cast<String, dynamic>()))
            .toList(growable: false);
      }
      throw ApiException((data['message'] ?? 'Failed to load warp history').toString(), statusCode: response.statusCode);
    } on DioException catch (e) {
      final message = _extractMessage(e) ?? 'Failed to load warp history';
      throw ApiException(message, statusCode: e.response?.statusCode);
    }
  }

  Future<void> clearWarpHistory() async {
    try {
      final response = await _dio.post('/clear_warp_history');
      final data = (response.data as Map).cast<String, dynamic>();
      if (data['status'] == 'success') return;
      throw ApiException((data['message'] ?? 'Failed to clear warp history').toString(), statusCode: response.statusCode);
    } on DioException catch (e) {
      final message = _extractMessage(e) ?? 'Failed to clear warp history';
      throw ApiException(message, statusCode: e.response?.statusCode);
    }
  }

  Future<List<Announcement>> getAnnouncements() async {
    try {
      final response = await _dio.get('/messages');
      final data = (response.data as Map).cast<String, dynamic>();
      if (data['status'] == 'success') {
        final list = (data['messages'] as List? ?? const []).cast<dynamic>();
        return list
            .map((e) => Announcement.fromJson((e as Map).cast<String, dynamic>()))
            .toList(growable: false);
      }
      throw ApiException((data['message'] ?? 'Failed to load messages').toString(), statusCode: response.statusCode);
    } on DioException catch (e) {
      final message = _extractMessage(e) ?? 'Failed to load messages';
      throw ApiException(message, statusCode: e.response?.statusCode);
    }
  }

  Future<void> broadcastAnnouncement({required String message}) async {
    try {
      final response = await _dio.post(
        '/admin/broadcast_message',
        data: {'message': message},
        options: Options(headers: {'Content-Type': 'application/json'}),
      );
      final data = (response.data as Map).cast<String, dynamic>();
      if (data['status'] == 'success') return;
      throw ApiException((data['message'] ?? 'Failed to send message').toString(), statusCode: response.statusCode);
    } on DioException catch (e) {
      final message = _extractMessage(e) ?? 'Failed to send message';
      throw ApiException(message, statusCode: e.response?.statusCode);
    }
  }

  Future<void> deleteAnnouncement({required String id}) async {
    try {
      final response = await _dio.delete('/admin/messages/$id');
      final data = (response.data as Map).cast<String, dynamic>();
      if (data['status'] == 'success') return;
      throw ApiException((data['message'] ?? 'Failed to delete message').toString(), statusCode: response.statusCode);
    } on DioException catch (e) {
      final message = _extractMessage(e) ?? 'Failed to delete message';
      throw ApiException(message, statusCode: e.response?.statusCode);
    }
  }

  Future<void> addUser({
    required String username,
    required String password,
    required String role,
  }) async {
    try {
      final response = await _dio.post(
        '/admin/add_user',
        data: FormData.fromMap({
          'username': username,
          'password': password,
          'role': role,
        }),
      );
      final data = (response.data as Map).cast<String, dynamic>();
      if (data['status'] == 'success') return;
      throw ApiException((data['message'] ?? 'Failed to add user').toString(), statusCode: response.statusCode);
    } on DioException catch (e) {
      final message = _extractMessage(e) ?? 'Failed to add user';
      throw ApiException(message, statusCode: e.response?.statusCode);
    }
  }

  Future<void> updateUserPassword({
    required String username,
    required String newPassword,
    required String confirmPassword,
  }) async {
    try {
      final response = await _dio.post(
        '/admin/update_password',
        data: FormData.fromMap({
          'username': username,
          'new_password': newPassword,
          'confirm_password': confirmPassword,
        }),
      );
      final data = (response.data as Map).cast<String, dynamic>();
      if (data['status'] == 'success') return;
      throw ApiException((data['message'] ?? 'Failed to update password').toString(), statusCode: response.statusCode);
    } on DioException catch (e) {
      final message = _extractMessage(e) ?? 'Failed to update password';
      throw ApiException(message, statusCode: e.response?.statusCode);
    }
  }

  Future<void> removeUser({required String username}) async {
    try {
      final response = await _dio.post(
        '/admin/remove_user',
        data: FormData.fromMap({'username': username}),
      );
      final data = (response.data as Map).cast<String, dynamic>();
      if (data['status'] == 'success') return;
      throw ApiException((data['message'] ?? 'Failed to remove user').toString(), statusCode: response.statusCode);
    } on DioException catch (e) {
      final message = _extractMessage(e) ?? 'Failed to remove user';
      throw ApiException(message, statusCode: e.response?.statusCode);
    }
  }

  Future<void> removeLoomData({
    required String loomerName,
    required String loomNumber,
    required String shift,
    required String fromDateYYYYMMDD,
    required String toDateYYYYMMDD,
  }) async {
    try {
      final response = await _dio.post(
        '/admin/remove_data',
        data: FormData.fromMap({
          'loomer_name': loomerName,
          'loom_number': loomNumber,
          'shift': shift,
          'from_date': fromDateYYYYMMDD,
          'to_date': toDateYYYYMMDD,
        }),
      );
      final data = (response.data as Map).cast<String, dynamic>();
      if (data['status'] == 'success') return;
      throw ApiException((data['message'] ?? 'Failed to remove data').toString(), statusCode: response.statusCode);
    } on DioException catch (e) {
      final message = _extractMessage(e) ?? 'Failed to remove data';
      throw ApiException(message, statusCode: e.response?.statusCode);
    }
  }

  String? _extractMessage(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['message'] != null) {
      return data['message'].toString();
    }
    return null;
  }
}
