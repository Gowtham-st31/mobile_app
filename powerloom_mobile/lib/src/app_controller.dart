import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

import 'api/api_client.dart';
import 'models/announcement.dart';
import 'models/admin_message.dart';
import 'models/profile_summary.dart';
import 'models/session.dart';
import 'services/notification_service.dart';
import 'services/local_message_store.dart';
import 'services/realtime_service.dart';

class AppController extends ChangeNotifier {
  static const _prefsBaseUrlKey = 'apiBaseUrl';

  ApiClient? _api;
  Session? _session;
  ProfileSummary? _profile;
  bool _bootstrapping = true;

  final _notifications = NotificationService();
  final _realtime = RealtimeService();
  final _localMessages = LocalMessageStore();

  Timer? _messagePoller;
  String? _lastSeenAnnouncementId;

  int _adminMessageVersion = 0;
  Map<String, dynamic>? _lastAdminMessage;

  List<AdminMessage> _storedAdminMessages = const [];

  String _baseUrl;

  AppController({required String defaultBaseUrl}) : _baseUrl = defaultBaseUrl;

  bool get bootstrapping => _bootstrapping;
  ApiClient get api {
    final client = _api;
    if (client == null) throw StateError('ApiClient not initialized');
    return client;
  }

  Session? get session => _session;
  ProfileSummary? get profile => _profile;
  String get baseUrl => _baseUrl;
  NotificationService get notifications => _notifications;

  int get adminMessageVersion => _adminMessageVersion;
  Map<String, dynamic>? get lastAdminMessage => _lastAdminMessage;
  List<AdminMessage> get storedAdminMessages => _storedAdminMessages;

  Future<void> deleteStoredAdminMessageById(String id) async {
    final username = _session?.username;
    if (username == null || username.trim().isEmpty) return;
    final next = _storedAdminMessages.where((m) => m.id != id).toList(growable: false);
    _storedAdminMessages = next;
    await _localMessages.save(username: username, messages: next);
    notifyListeners();
  }

  Future<void> init() async {
    final start = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    _baseUrl = prefs.getString(_prefsBaseUrlKey) ?? _baseUrl;

    await _initApi();

    await _notifications.init();

    // Try to restore session from persisted cookies.
    try {
      final summary = await api.getProfileSummary();
      _profile = summary;
      _session = Session(username: summary.user.username, role: summary.user.role);
      await _loadLocalMessagesForCurrentUser();
      _startRealtime();
      _startMessagePolling();
    } catch (_) {
      _profile = null;
      _session = null;
      _storedAdminMessages = const [];
    }

    // Keep splash visible for at least 3 seconds.
    final elapsed = DateTime.now().difference(start);
    const minSplash = Duration(seconds: 3);
    if (elapsed < minSplash) {
      await Future.delayed(minSplash - elapsed);
    }

    _bootstrapping = false;
    notifyListeners();
  }

  Future<void> setBaseUrl(String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;

    _baseUrl = trimmed;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsBaseUrlKey, _baseUrl);

    await _initApi();
    // Reconnect realtime on base URL change.
    if (_session != null) {
      _startRealtime();
    }
    notifyListeners();
  }

  Future<void> _initApi() async {
    _api = await ApiClient.create(baseUrl: _baseUrl);
  }

  Future<void> login({required String username, required String password}) async {
    final login = await api.login(username: username, password: password);

    // Confirm session and load profile.
    final summary = await api.getProfileSummary();
    _profile = summary;
    _session = Session(username: summary.user.username, role: login.role);
    await _loadLocalMessagesForCurrentUser();
    _startRealtime();
    _startMessagePolling();
    notifyListeners();
  }

  Future<void> refreshProfile() async {
    final summary = await api.getProfileSummary();
    _profile = summary;
    if (_session != null) {
      _session = Session(username: summary.user.username, role: summary.user.role);
    }
    notifyListeners();
  }

  Future<void> logout() async {
    await api.logout();
    _realtime.disconnect();
    _messagePoller?.cancel();
    _messagePoller = null;
    _lastSeenAnnouncementId = null;
    _session = null;
    _profile = null;
    _storedAdminMessages = const [];
    notifyListeners();
  }

  bool get isAdmin => (_session?.role.toLowerCase() ?? '') == 'admin';

  Future<List<Announcement>> loadAnnouncements() => api.getAnnouncements();

  Future<void> sendAnnouncement(String message) async {
    await api.broadcastAnnouncement(message: message);

    // Store on the admin device as well so Admin page can show history.
    final sender = _session?.username.trim().isNotEmpty == true ? _session!.username : 'admin';
    final now = DateTime.now().toIso8601String();
    final local = AdminMessage(
      id: 'local:${DateTime.now().microsecondsSinceEpoch}',
      message: message,
      sender: sender,
      createdAt: now,
    );
    await _appendLocalMessage(local);
  }

  Future<void> _loadLocalMessagesForCurrentUser() async {
    final username = _session?.username;
    if (username == null || username.trim().isEmpty) {
      _storedAdminMessages = const [];
      return;
    }
    _storedAdminMessages = await _localMessages.load(username: username);
  }

  Future<void> _appendLocalMessage(AdminMessage message) async {
    final username = _session?.username;
    if (username == null || username.trim().isEmpty) return;

    // De-dupe by id if present.
    final existing = _storedAdminMessages;
    if (existing.any((m) => m.id == message.id && m.id.isNotEmpty)) return;

    final next = <AdminMessage>[message, ...existing];
    _storedAdminMessages = next;
    await _localMessages.save(username: username, messages: next);
    notifyListeners();
  }

  Future<void> storeIncomingAdminPayload(Map<String, dynamic> payload) async {
    final text = (payload['message'] ?? payload['text'] ?? '').toString().trim();
    if (text.isEmpty) return;

    final sender = (payload['sender'] ?? payload['username'] ?? payload['from'] ?? 'admin').toString();
    final createdAt = (payload['created_at'] ?? payload['createdAt'] ?? DateTime.now().toIso8601String()).toString();
    final id = (payload['_id'] ?? payload['id'] ?? '').toString();

    final msg = AdminMessage(
      id: id.isNotEmpty ? id : 'rt:${DateTime.now().microsecondsSinceEpoch}',
      message: text,
      sender: sender,
      createdAt: createdAt,
    );

    await _appendLocalMessage(msg);
  }

  void _startMessagePolling() {
    _messagePoller?.cancel();
    _messagePoller = null;

    if (_session == null) return;

    Future<void> tick({required bool silent}) async {
      try {
        final list = await api.getAnnouncements();
        if (list.isEmpty) return;

        final newest = list.first;
        if (_lastSeenAnnouncementId == null) {
          // First load: don't spam a banner.
          _lastSeenAnnouncementId = newest.id;
          return;
        }

        if (newest.id == _lastSeenAnnouncementId) return;
        _lastSeenAnnouncementId = newest.id;

        _lastAdminMessage = {
          '_id': newest.id,
          'message': newest.message,
          'sender': newest.sender,
          'created_at': newest.createdAt,
        };
        _adminMessageVersion++;
        if (!silent) {
          _notifications.showAdminMessage(title: 'Admin message', body: newest.message);
        }

        // Persist locally on device.
        unawaited(storeIncomingAdminPayload(_lastAdminMessage!));
        notifyListeners();
      } catch (_) {
        // Ignore polling errors; UI can still manually refresh.
      }
    }

    // Prime once quickly (silent), then poll.
    unawaited(tick(silent: true));
    _messagePoller = Timer.periodic(const Duration(seconds: 8), (_) {
      unawaited(tick(silent: false));
    });
  }

  void _startRealtime() {
    _realtime.connect(
      baseUrl: _baseUrl,
      onAdminMessage: (payload) {
        final message = (payload['message'] ?? '').toString();
        if (message.isEmpty) return;
        _lastAdminMessage = payload;
        _adminMessageVersion++;
        _notifications.showAdminMessage(title: 'Admin message', body: message);
        unawaited(storeIncomingAdminPayload(payload));
        notifyListeners();
      },
    );
  }
}
