import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/admin_message.dart';

class LocalMessageStore {
  static const _keyPrefix = 'admin_messages_v1:';
  static const _maxMessages = 200;

  String _keyForUser(String username) {
    final safe = username.trim().isEmpty ? 'anonymous' : username.trim().toLowerCase();
    return '$_keyPrefix$safe';
  }

  Future<List<AdminMessage>> load({required String username}) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyForUser(username));
    if (raw == null || raw.isEmpty) return const [];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((e) => AdminMessage.fromJson(e.cast<String, dynamic>()))
          .where((m) => m.message.trim().isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> save({required String username, required List<AdminMessage> messages}) async {
    final prefs = await SharedPreferences.getInstance();
    final capped = messages.length <= _maxMessages ? messages : messages.sublist(0, _maxMessages);
    final raw = jsonEncode(capped.map((e) => e.toJson()).toList(growable: false));
    await prefs.setString(_keyForUser(username), raw);
  }
}
