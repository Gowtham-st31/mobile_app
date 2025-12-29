import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../models/admin_message.dart';
import '../models/profile_summary.dart';
import '../models/session.dart';

class ProfileScreen extends StatefulWidget {
  final AppController controller;
  final Session session;

  const ProfileScreen({super.key, required this.controller, required this.session});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _loading = false;

  String _formatCreatedAt(String raw) {
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;
    final local = parsed.toLocal();
    final two = (int v) => v.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }

  Widget _messagesCard(List<AdminMessage> messages) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Admin Messages', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            if (messages.isEmpty)
              const Text('No messages yet on this phone.')
            else
              ...messages.take(5).map(
                    (m) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(m.message, style: const TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 2),
                          Text('${m.sender} • ${_formatCreatedAt(m.createdAt)}', style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ),
          ],
        ),
      ),
    );
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      await widget.controller.refreshProfile();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = widget.controller.profile;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Profile', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            ),
            IconButton(
              onPressed: _loading ? null : _refresh,
              icon: _loading ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.refresh),
              tooltip: 'Refresh',
            ),
          ],
        ),
        const SizedBox(height: 12),

        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Username: ${widget.session.username}', style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text('Role: ${widget.session.role}', style: const TextStyle(fontWeight: FontWeight.w700)),
                if (summary?.user.createdAt != null) ...[
                  const SizedBox(height: 4),
                  Text('Created: ${summary!.user.createdAt}', style: const TextStyle(fontWeight: FontWeight.w500)),
                ],
              ],
            ),
          ),
        ),

        const SizedBox(height: 12),
        if (summary != null) _TotalsCard(totals: summary.totals) else const Text('Pull to refresh to load totals.'),

        const SizedBox(height: 12),
        AnimatedBuilder(
          animation: widget.controller,
          builder: (context, _) => _messagesCard(widget.controller.storedAdminMessages),
        ),
      ],
    );
  }
}

class _TotalsCard extends StatelessWidget {
  final ProfileTotals totals;

  const _TotalsCard({required this.totals});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Totals (${totals.scope})', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: _Metric(label: 'Records', value: '${totals.totalRecords}')),
                Expanded(child: _Metric(label: 'Meters', value: totals.totalMeters.toStringAsFixed(0))),
                Expanded(child: _Metric(label: 'Salary', value: '₹${totals.totalSalary.toStringAsFixed(2)}')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;

  const _Metric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(value, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
      ],
    );
  }
}
