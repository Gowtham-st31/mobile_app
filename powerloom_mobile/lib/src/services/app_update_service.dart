import 'dart:io';

import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';

class AndroidUpdateInfo {
  final int versionCode;
  final String versionName;
  final String apkUrl;

  const AndroidUpdateInfo({
    required this.versionCode,
    required this.versionName,
    required this.apkUrl,
  });

  static AndroidUpdateInfo? fromJson(Map<String, dynamic> json) {
    final platform = (json['platform'] ?? '').toString().toLowerCase();
    if (platform.isNotEmpty && platform != 'android') return null;

    final versionCode = int.tryParse((json['version_code'] ?? '').toString()) ?? 0;
    final versionName = (json['version_name'] ?? '').toString();
    final apkUrl = (json['apk_url'] ?? '').toString().trim();

    if (versionCode <= 0 || apkUrl.isEmpty) return null;
    return AndroidUpdateInfo(versionCode: versionCode, versionName: versionName, apkUrl: apkUrl);
  }
}

class AppUpdateService {
  final Dio _dio;

  AppUpdateService({required Dio dio}) : _dio = dio;

  Future<AndroidUpdateInfo?> fetchLatestAndroid({required String baseUrl}) async {
    if (!Platform.isAndroid) return null;

    final normalized = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (normalized.isEmpty) return null;

    final url = '$normalized/api/mobile/android/latest';

    final response = await _dio.get(url, options: Options(responseType: ResponseType.json));
    final data = response.data;

    if (data is Map) {
      return AndroidUpdateInfo.fromJson(data.cast<String, dynamic>());
    }
    return null;
  }

  Future<int> getCurrentAndroidVersionCode() async {
    final info = await PackageInfo.fromPlatform();
    return int.tryParse(info.buildNumber) ?? 0;
  }
}
