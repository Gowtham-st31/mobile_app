import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:dio/dio.dart';

import '../app_controller.dart';
import '../models/session.dart';
import '../services/app_update_service.dart';
import 'admin_screen.dart';
import 'enter_data_screen.dart';
import 'graphs_screen.dart';
import 'messages_screen.dart';
import 'profile_screen.dart';
import 'reports_screen.dart';

class HomeShell extends StatefulWidget {
  final AppController controller;
  final Session session;

  const HomeShell({super.key, required this.controller, required this.session});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  int _seenAdminMessageVersion = 0;
  bool _checkedForUpdate = false;

  @override
  void initState() {
    super.initState();
    _seenAdminMessageVersion = widget.controller.adminMessageVersion;
    widget.controller.addListener(_onControllerChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) => _checkForAppUpdate());
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    final v = widget.controller.adminMessageVersion;
    if (v == _seenAdminMessageVersion) return;

    _seenAdminMessageVersion = v;
    final payload = widget.controller.lastAdminMessage;
    final message = (payload?['message'] ?? '').toString();
    if (message.isEmpty) return;

    final sender = (payload?['sender'] ?? 'Admin').toString();
    final createdAt = (payload?['created_at'] ?? '').toString();
    final subtitle = createdAt.isEmpty ? sender : '$sender • $createdAt';

    final messenger = ScaffoldMessenger.of(context);
    messenger.clearMaterialBanners();
    messenger.showMaterialBanner(
      MaterialBanner(
        content: Text('$message\n$subtitle'),
        actions: [
          TextButton(
            onPressed: () => messenger.hideCurrentMaterialBanner(),
            child: const Text('DISMISS'),
          ),
        ],
      ),
    );
  }

  Future<void> _checkForAppUpdate() async {
    if (_checkedForUpdate) return;
    _checkedForUpdate = true;

    try {
      final service = AppUpdateService(dio: Dio());
      final latest = await service.fetchLatestAndroid(baseUrl: widget.controller.baseUrl);
      if (latest == null) return;

      final currentCode = await service.getCurrentAndroidVersionCode();
      if (latest.versionCode <= currentCode) return;
      if (!mounted) return;

      final messenger = ScaffoldMessenger.of(context);
      messenger.clearMaterialBanners();
      messenger.showMaterialBanner(
        MaterialBanner(
          content: Text('Update available: v${latest.versionName.isEmpty ? latest.versionCode : latest.versionName}.\nPlease download and install the latest version.'),
          actions: [
            TextButton(
              onPressed: () async {
                final uri = Uri.tryParse(latest.apkUrl);
                if (uri == null) return;
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              },
              child: const Text('UPDATE'),
            ),
            TextButton(
              onPressed: () => messenger.hideCurrentMaterialBanner(),
              child: const Text('DISMISS'),
            ),
          ],
        ),
      );
    } catch (_) {
      // Ignore update check failures.
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = widget.session.role.toLowerCase() == 'admin';

    final pages = <Widget>[
      if (isAdmin) EnterDataScreen(controller: widget.controller, session: widget.session),
      ReportsScreen(controller: widget.controller, session: widget.session),
      GraphsScreen(controller: widget.controller, session: widget.session),
      MessagesScreen(controller: widget.controller, session: widget.session),
      ProfileScreen(controller: widget.controller, session: widget.session),
      if (isAdmin) AdminScreen(controller: widget.controller, session: widget.session),
    ];

    final destinations = <NavigationDestination>[
      if (isAdmin) const NavigationDestination(icon: Icon(Icons.edit_note), label: 'Enter'),
      const NavigationDestination(icon: Icon(Icons.receipt_long), label: 'Reports'),
      const NavigationDestination(icon: Icon(Icons.insights), label: 'Graphs'),
      const NavigationDestination(icon: Icon(Icons.notifications), label: 'Message'),
      const NavigationDestination(icon: Icon(Icons.person), label: 'Profile'),
      if (isAdmin) const NavigationDestination(icon: Icon(Icons.admin_panel_settings), label: 'Admin'),
    ];

    // Keep index in range if role changes.
    if (_index >= pages.length) _index = 0;

    return Scaffold(
      appBar: AppBar(
        leading: Padding(
          padding: const EdgeInsets.all(10),
          child: Image.asset('assets/logo.png', fit: BoxFit.contain),
        ),
        title: Text('Vinayaga Tex (${widget.session.username})'),
        actions: [
          IconButton(
            tooltip: 'Logout',
            onPressed: () async {
              try {
                await widget.controller.logout();
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
              }
            },
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: SafeArea(child: pages[_index]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: destinations,
      ),
    );
  }
}
