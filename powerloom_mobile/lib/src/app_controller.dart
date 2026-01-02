import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';

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

  StreamSubscription<String>? _fcmTokenRefreshSub;
  StreamSubscription<RemoteMessage>? _fcmForegroundMessageSub;
  bool _fcmForegroundListening = false;

  int _adminMessageVersion = 0;
  Map<String, dynamic>? _lastAdminMessage;

  List<AdminMessage> _storedAdminMessages = const [];

  String _baseUrl;

  AppController({required String defaultBaseUrl}) : _baseUrl = _normalizeBaseUrl(defaultBaseUrl) ?? defaultBaseUrl;

  /// Normalizes and validates a base URL for API calls.
  ///
  /// - Trims whitespace
  /// - Removes trailing slashes
  /// - Adds a scheme if missing (http for local dev, https otherwise)
  /// - Fixes a few common mobile typos like `ps://` -> `https://`
  /// - Ensures the result parses as a valid http(s) URI with a host
  String? normalizeBaseUrl(String? raw) => _normalizeBaseUrl(raw);

  static String? _normalizeBaseUrl(String? raw) {
    if (raw == null) return null;
    var value = raw.trim();
    if (value.isEmpty) return null;

    // Fix common missing-leading-character typos.
    // Example: users sometimes paste `ps://example.com` instead of `https://example.com`.
    final lowerRaw = value.toLowerCase();
    if (lowerRaw.startsWith('ps://')) {
      value = 'https://${value.substring(5)}';
    } else if (lowerRaw.startsWith('ttps://')) {
      value = 'https://${value.substring(7)}';
    } else if (lowerRaw.startsWith('ttp://')) {
      value = 'http://${value.substring(6)}';
    }

    // Fix a common domain typo (Render): onrender.cc -> onrender.com
    // This is safe because we only rewrite the host suffix.
    value = value.replaceAll(RegExp(r'onrender\.cc\b', caseSensitive: false), 'onrender.com');

    // Remove trailing slashes to keep URL joins consistent.
    value = value.replaceAll(RegExp(r'/+$'), '');

    final lower = value.toLowerCase();
    // If it already has a scheme, only allow http(s).
    if (lower.contains('://')) {
      if (!(lower.startsWith('http://') || lower.startsWith('https://'))) return null;
      final uri = Uri.tryParse(value);
      if (uri == null || uri.host.trim().isEmpty) return null;
      return value;
    }

    // If user entered a bare host (common on phones), add a scheme.
    // Prefer http for local dev hosts; otherwise default to https.
    final isLocalHost = lower.startsWith('localhost') || lower.startsWith('127.') || lower.startsWith('10.0.2.2');
    final isLanIp = RegExp(r'^(?:\d{1,3}\.){3}\d{1,3}(?::\d+)?$').hasMatch(value);

    final scheme = (isLocalHost || isLanIp) ? 'http://' : 'https://';

    final normalized = '$scheme$value';
    final uri = Uri.tryParse(normalized);
    if (uri == null || uri.host.trim().isEmpty) return null;
    return normalized;
  }

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

  static final RegExp _serverIdPattern = RegExp(r'^[a-f0-9]{24}$', caseSensitive: false);
  bool _isServerMessageId(String id) => _serverIdPattern.hasMatch(id);

  Future<void> deleteStoredAdminMessageById(String id) async {
    final username = _session?.username;
    if (username == null || username.trim().isEmpty) return;
    final next = _storedAdminMessages.where((m) => m.id != id).toList(growable: false);
    _storedAdminMessages = next;
    await _localMessages.save(username: username, messages: next);
    notifyListeners();
  }

  Future<void> deleteAdminMessageGlobally(String id) async {
    final trimmed = id.trim();
    if (trimmed.isEmpty) return;
    await api.deleteAnnouncement(id: trimmed);
    await deleteStoredAdminMessageById(trimmed);
    if (_lastSeenAnnouncementId == trimmed) {
      _lastSeenAnnouncementId = null;
    }
  }

  Future<void> init() async {
    final start = DateTime.now();
    final prefs = await SharedPreferences.getInstance();

    final stored = prefs.getString(_prefsBaseUrlKey);
    final normalizedStored = _normalizeBaseUrl(stored);
    if (normalizedStored != null) {
      _baseUrl = normalizedStored;
      if (stored != normalizedStored) {
        await prefs.setString(_prefsBaseUrlKey, normalizedStored);
      }
    } else {
      _baseUrl = _normalizeBaseUrl(_baseUrl) ?? _baseUrl;
    }

    await _initApi();

    await _notifications.init();
    await _ensureFcmForegroundListener();

    // Try to restore session from persisted cookies.
    try {
      final summary = await api.getProfileSummary();
      _profile = summary;
      _session = Session(username: summary.user.username, role: summary.user.role);
      await _loadLocalMessagesForCurrentUser();
      _startRealtime();
      _startMessagePolling();
      await _registerFcmTokenIfPossible();
      _listenForFcmTokenRefresh();
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
    final normalized = _normalizeBaseUrl(value);
    if (normalized == null) {
      throw ArgumentError('Invalid server URL');
    }

    _baseUrl = normalized;
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
    await _registerFcmTokenIfPossible();
    _listenForFcmTokenRefresh();
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

    await _fcmTokenRefreshSub?.cancel();
    _fcmTokenRefreshSub = null;

    await _fcmForegroundMessageSub?.cancel();
    _fcmForegroundMessageSub = null;
    _fcmForegroundListening = false;
    _messagePoller?.cancel();
    _messagePoller = null;
    _lastSeenAnnouncementId = null;
    _session = null;
    _profile = null;
    _storedAdminMessages = const [];
    notifyListeners();
  }

  Future<void> _ensureFcmForegroundListener() async {
    if (_fcmForegroundListening) return;
    _fcmForegroundListening = true;

    try {
      // On iOS this matters; on Android it's effectively a no-op.
      await FirebaseMessaging.instance.requestPermission();
    } catch (_) {
      // Ignore.
    }

    _fcmForegroundMessageSub = FirebaseMessaging.onMessage.listen((message) {
      final title = message.notification?.title?.trim().isNotEmpty == true ? message.notification!.title!.trim() : 'Admin message';

      String body = (message.notification?.body ?? '').trim();
      if (body.isEmpty) {
        final fromData = (message.data['message'] ?? message.data['body'] ?? '').toString().trim();
        body = fromData;
      }

      if (body.isEmpty) return;
      _notifications.showAdminMessage(title: title, body: body);
    });
  }

  Future<void> _registerFcmTokenIfPossible() async {
    if (_session == null) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token.trim().isEmpty) return;
      await api.registerFcmToken(token: token.trim());
    } catch (_) {
      // Ignore: push is best-effort.
    }
  }

  void _listenForFcmTokenRefresh() {
    if (_session == null) return;
    _fcmTokenRefreshSub?.cancel();
    _fcmTokenRefreshSub = FirebaseMessaging.instance.onTokenRefresh.listen((token) async {
      try {
        if (token.trim().isEmpty) return;
        await api.registerFcmToken(token: token.trim());
      } catch (_) {
        // Ignore: push is best-effort.
      }
    });
  }

  void _invalidateSession() {
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
    // History is stored server-side and will arrive via Socket.IO and/or polling.

    // Also do an immediate pull so the sender sees the server-assigned id right away
    // and so we confirm persistence even if realtime delivery is delayed.
    try {
      final list = await api.getAnnouncements();
      for (final a in list.reversed) {
        unawaited(
          storeIncomingAdminPayload({
            '_id': a.id,
            'message': a.message,
            'sender': a.sender,
            'created_at': a.createdAt,
          }),
        );
      }
      if (list.isNotEmpty) {
        _lastSeenAnnouncementId = list.first.id;
      }
    } catch (_) {
      // Ignore: broadcast succeeded; polling will pick it up.
    }
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

        // Reconcile deletions: if a server message is missing from the server list,
        // remove it locally (covers clients that missed realtime delete).
        // IMPORTANT: this must also run when the server list is empty, otherwise
        // deleted messages can remain stuck on other devices.
        final serverIds = list.map((a) => a.id).where((id) => id.trim().isNotEmpty).toSet();
        final existing = _storedAdminMessages;
        final pruned = existing.where((m) {
          if (!_isServerMessageId(m.id)) return true;
          return serverIds.contains(m.id);
        }).toList(growable: false);
        if (pruned.length != existing.length) {
          _storedAdminMessages = pruned;
          final username = _session?.username;
          if (username != null && username.trim().isNotEmpty) {
            await _localMessages.save(username: username, messages: pruned);
          }
          notifyListeners();
        }

        if (list.isEmpty) return;

        // API returns newest-first.
        final newest = list.first;

        // First load: persist current server messages to local storage so they
        // are visible in the Messages screen, but don't show a banner.
        if (_lastSeenAnnouncementId == null) {
          _lastSeenAnnouncementId = newest.id;
          for (final a in list.reversed) {
            unawaited(
              storeIncomingAdminPayload({
                '_id': a.id,
                'message': a.message,
                'sender': a.sender,
                'created_at': a.createdAt,
              }),
            );
          }
          return;
        }

        if (newest.id == _lastSeenAnnouncementId) return;

        // Persist all new messages since the last seen id (best-effort).
        final lastSeen = _lastSeenAnnouncementId;
        int stopIndex = -1;
        for (var i = 0; i < list.length; i++) {
          if (list[i].id == lastSeen) {
            stopIndex = i;
            break;
          }
        }

        // If lastSeen isn't found, it likely got deleted or the server truncated the list.
        // Do a silent resync to avoid spamming notifications.
        if (stopIndex == -1) {
          for (final a in list.reversed) {
            unawaited(
              storeIncomingAdminPayload({
                '_id': a.id,
                'message': a.message,
                'sender': a.sender,
                'created_at': a.createdAt,
              }),
            );
          }
          _lastSeenAnnouncementId = newest.id;
          return;
        }

        final newMessages = list.sublist(0, stopIndex);
        for (final a in newMessages.reversed) {
          unawaited(
            storeIncomingAdminPayload({
              '_id': a.id,
              'message': a.message,
              'sender': a.sender,
              'created_at': a.createdAt,
            }),
          );
        }

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
        notifyListeners();
      } on ApiException catch (e) {
        if (e.statusCode == 401 || e.statusCode == 403) {
          _invalidateSession();
          return;
        }
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
      onAdminMessageDeleted: (payload) {
        final id = (payload['_id'] ?? payload['id'] ?? '').toString().trim();
        if (id.isEmpty) return;
        if (_lastSeenAnnouncementId == id) {
          _lastSeenAnnouncementId = null;
        }
        unawaited(deleteStoredAdminMessageById(id));
      },
    );
  }
}
