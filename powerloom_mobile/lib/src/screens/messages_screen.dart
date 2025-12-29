import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../models/admin_message.dart';
import '../models/session.dart';

class MessagesScreen extends StatefulWidget {
  final AppController controller;
  final Session session;

  const MessagesScreen({super.key, required this.controller, required this.session});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  final _msgController = TextEditingController();
  bool _sending = false;

  bool get _isAdmin => widget.session.role.toLowerCase() == 'admin';

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _msgController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _msgController.text.trim();
    if (text.isEmpty) return;

    setState(() => _sending = true);
    try {
      await widget.controller.sendAnnouncement(text);
      _msgController.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Notification sent')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _formatCreatedAt(String raw) {
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;
    final local = parsed.toLocal();
    final two = (int v) => v.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }

  Widget _buildMessageList(List<AdminMessage> messages) {
    if (messages.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('No messages yet on this device.'),
        ),
      );
    }

    return Column(
      children: [
        ...messages.take(50).map(
              (m) => Card(
                child: ListTile(
                  title: Text(m.message),
                  subtitle: Text('${m.sender}\n${_formatCreatedAt(m.createdAt)}'.trim()),
                ),
              ),
            ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Messages', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),

        Text('Saved on this phone', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        AnimatedBuilder(
          animation: widget.controller,
          builder: (context, _) => _buildMessageList(widget.controller.storedAdminMessages),
        ),
        const SizedBox(height: 12),

        if (_isAdmin)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Send notification to all users', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _msgController,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: 'Message'),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _sending ? null : _send,
                      child: _sending
                          ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Send Notification'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text('Sent messages are also saved on this phone.'),
                ],
              ),
            ),
          )
        else
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('Admin notifications are saved on this phone and also appear as a notification banner when received.'),
            ),
          ),
      ],
    );
  }
}
