import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_controller.dart';
import '../models/admin_message.dart';
import '../models/session.dart';

class AdminScreen extends StatefulWidget {
  final AppController controller;
  final Session session;

  const AdminScreen({super.key, required this.controller, required this.session});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  final _addUserKey = GlobalKey<FormState>();
  final _updatePasswordKey = GlobalKey<FormState>();
  final _removeUserKey = GlobalKey<FormState>();
  final _removeDataKey = GlobalKey<FormState>();

  final _newUsernameController = TextEditingController();
  final _newPasswordController = TextEditingController();
  String _newRole = 'loomer';

  final _pwUsernameController = TextEditingController();
  final _pwNewController = TextEditingController();
  final _pwConfirmController = TextEditingController();

  final _removeUsernameController = TextEditingController();

  final _removeDataLoomerController = TextEditingController();
  final _removeDataLoomController = TextEditingController(text: 'all');
  String _removeDataShift = 'all';
  DateTime _removeFrom = DateTime.now();
  DateTime _removeTo = DateTime.now();

  bool _loadingUsers = false;
  List<Map<String, dynamic>> _users = const [];

  bool _busy = false;

  final _serverUrlController = TextEditingController();

  // Warp management
  bool _loadingWarp = false;
  double _currentWarp = 0.0;
  final _warpValueController = TextEditingController();
  final _warpRemarksController = TextEditingController();
  DateTime _warpDate = DateTime.now();
  final _knottingController = TextEditingController();
  double? _knottingResult;

  bool get _isAdmin => widget.session.role.toLowerCase() == 'admin';

  @override
  void initState() {
    super.initState();
    _serverUrlController.text = widget.controller.baseUrl;
    _refreshUsers();
    _refreshWarp();
  }

  @override
  void dispose() {
    _newUsernameController.dispose();
    _newPasswordController.dispose();
    _pwUsernameController.dispose();
    _pwNewController.dispose();
    _pwConfirmController.dispose();
    _removeUsernameController.dispose();
    _removeDataLoomerController.dispose();
    _removeDataLoomController.dispose();

    _warpValueController.dispose();
    _warpRemarksController.dispose();
    _knottingController.dispose();
    _serverUrlController.dispose();

    super.dispose();
  }

  Future<void> _refreshUsers() async {
    if (!_isAdmin) return;
    setState(() => _loadingUsers = true);
    try {
      final users = await widget.controller.api.getUsers();
      if (!mounted) return;
      setState(() => _users = users);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _loadingUsers = false);
    }
  }

  Future<void> _pickRemoveFrom() async {
    final selected = await showDatePicker(
      context: context,
      firstDate: DateTime(2000, 1, 1),
      lastDate: DateTime(2100, 12, 31),
      initialDate: _removeFrom,
    );
    if (selected == null) return;
    setState(() => _removeFrom = selected);
  }

  Future<void> _pickRemoveTo() async {
    final selected = await showDatePicker(
      context: context,
      firstDate: DateTime(2000, 1, 1),
      lastDate: DateTime(2100, 12, 31),
      initialDate: _removeTo,
    );
    if (selected == null) return;
    setState(() => _removeTo = selected);
  }

  Future<void> _pickWarpDate() async {
    final selected = await showDatePicker(
      context: context,
      firstDate: DateTime(2000, 1, 1),
      lastDate: DateTime(2100, 12, 31),
      initialDate: _warpDate,
    );
    if (selected == null) return;
    setState(() => _warpDate = selected);
  }

  Future<void> _refreshWarp() async {
    if (!_isAdmin) return;
    setState(() => _loadingWarp = true);
    try {
      final v = await widget.controller.api.getCurrentWarp();
      if (!mounted) return;
      setState(() => _currentWarp = v);
    } catch (e) {
      if (!mounted) return;
      _toast(e.toString());
    } finally {
      if (mounted) setState(() => _loadingWarp = false);
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

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
            Text(
              'Admin Messages (saved on this phone)',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            if (messages.isEmpty)
              const Text('No messages yet on this phone.')
            else
              ...messages.take(10).map(
                    (m) {
                      final canDeleteSent = m.id.startsWith('local:');
                      return Card(
                        child: ListTile(
                          title: Text(m.message),
                          subtitle: Text('${m.sender}\n${_formatCreatedAt(m.createdAt)}'.trim()),
                          trailing: canDeleteSent
                              ? IconButton(
                                  tooltip: 'Delete sent message',
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () async {
                                    await widget.controller.deleteStoredAdminMessageById(m.id);
                                    if (mounted) _toast('Message deleted');
                                  },
                                )
                              : null,
                        ),
                      );
                    },
                  ),
          ],
        ),
      ),
    );
  }

  Future<void> _runBusy(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) _toast(e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAdmin) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          Text('Admin Tools (Admin only)'),
          SizedBox(height: 8),
          Card(child: Padding(padding: EdgeInsets.all(16), child: Text('You do not have access to admin tools.'))),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Admin Tools', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),

        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Server URL', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                TextField(
                  controller: _serverUrlController,
                  decoration: const InputDecoration(
                    labelText: 'Base URL',
                    hintText: 'https://vinayagatexapp.onrender.com',
                  ),
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.done,
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonal(
                    onPressed: _busy
                        ? null
                        : () => _runBusy(() async {
                              await widget.controller.setBaseUrl(_serverUrlController.text);
                              if (mounted) _toast('Server URL updated');
                            }),
                    child: const Text('Save Server URL'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        AnimatedBuilder(
          animation: widget.controller,
          builder: (context, _) => _messagesCard(widget.controller.storedAdminMessages),
        ),
        const SizedBox(height: 12),

        Card(
          child: ListTile(
            title: const Text('Users'),
            subtitle: Text(_loadingUsers ? 'Loading…' : '${_users.length} users'),
            trailing: IconButton(
              onPressed: _busy ? null : _refreshUsers,
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh',
            ),
          ),
        ),
        const SizedBox(height: 8),

        ExpansionTile(
          title: const Text('List Users'),
          initiallyExpanded: true,
          children: [
            if (_users.isEmpty && !_loadingUsers)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('No users loaded yet. Tap refresh above.'),
              )
            else
              ..._users.map(
                (u) => ListTile(
                  title: Text((u['username'] ?? '').toString()),
                  subtitle: Text((u['role'] ?? '').toString()),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),

        ExpansionTile(
          title: const Text('Add User'),
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _addUserKey,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _newUsernameController,
                      decoration: const InputDecoration(labelText: 'Username'),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _newPasswordController,
                      decoration: const InputDecoration(labelText: 'Password'),
                      obscureText: true,
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: _newRole,
                      decoration: const InputDecoration(labelText: 'Role'),
                      items: const [
                        DropdownMenuItem(value: 'loomer', child: Text('Loomer')),
                        DropdownMenuItem(value: 'admin', child: Text('Admin')),
                      ],
                      onChanged: _busy ? null : (v) => setState(() => _newRole = v ?? 'loomer'),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _busy
                            ? null
                            : () => _runBusy(() async {
                                  if (!_addUserKey.currentState!.validate()) return;
                                  await widget.controller.api.addUser(
                                    username: _newUsernameController.text.trim().toLowerCase(),
                                    password: _newPasswordController.text,
                                    role: _newRole,
                                  );
                                  _newUsernameController.clear();
                                  _newPasswordController.clear();
                                  await _refreshUsers();
                                  if (mounted) _toast('User added');
                                }),
                        child: _busy
                            ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Add User'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        ExpansionTile(
          title: const Text('Update User Password'),
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _updatePasswordKey,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _pwUsernameController,
                      decoration: const InputDecoration(labelText: 'Username to update'),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _pwNewController,
                      decoration: const InputDecoration(labelText: 'New password'),
                      obscureText: true,
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _pwConfirmController,
                      decoration: const InputDecoration(labelText: 'Confirm password'),
                      obscureText: true,
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _busy
                            ? null
                            : () => _runBusy(() async {
                                  if (!_updatePasswordKey.currentState!.validate()) return;
                                  await widget.controller.api.updateUserPassword(
                                    username: _pwUsernameController.text.trim().toLowerCase(),
                                    newPassword: _pwNewController.text,
                                    confirmPassword: _pwConfirmController.text,
                                  );
                                  _pwUsernameController.clear();
                                  _pwNewController.clear();
                                  _pwConfirmController.clear();
                                  if (mounted) _toast('Password updated');
                                }),
                        child: _busy
                            ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Update Password'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        ExpansionTile(
          title: const Text('Remove User'),
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _removeUserKey,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _removeUsernameController,
                      decoration: const InputDecoration(labelText: 'Username to remove'),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.tonal(
                        onPressed: _busy
                            ? null
                            : () => _runBusy(() async {
                                  if (!_removeUserKey.currentState!.validate()) return;
                                  await widget.controller.api.removeUser(
                                    username: _removeUsernameController.text.trim().toLowerCase(),
                                  );
                                  _removeUsernameController.clear();
                                  await _refreshUsers();
                                  if (mounted) _toast('User removed');
                                }),
                        child: _busy
                            ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Remove User'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text('Note: you cannot remove your own admin account while logged in.'),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        ExpansionTile(
          title: const Text('Remove Loom Data'),
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _removeDataKey,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _removeDataLoomerController,
                      decoration: const InputDecoration(
                        labelText: 'Loomer Name (optional)',
                        helperText: 'Leave empty to match all loomers',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _removeDataLoomController,
                      decoration: const InputDecoration(
                        labelText: 'Loom Number',
                        helperText: 'Use "all" for all looms',
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: _removeDataShift,
                      decoration: const InputDecoration(labelText: 'Shift'),
                      items: const [
                        DropdownMenuItem(value: 'all', child: Text('All Shifts')),
                        DropdownMenuItem(value: 'Morning', child: Text('Morning')),
                        DropdownMenuItem(value: 'Night', child: Text('Night')),
                      ],
                      onChanged: _busy ? null : (v) => setState(() => _removeDataShift = v ?? 'all'),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _busy ? null : _pickRemoveFrom,
                            icon: const Icon(Icons.calendar_today),
                            label: Text('From: ${DateFormat('yyyy-MM-dd').format(_removeFrom)}'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _busy ? null : _pickRemoveTo,
                            icon: const Icon(Icons.calendar_today),
                            label: Text('To: ${DateFormat('yyyy-MM-dd').format(_removeTo)}'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.tonal(
                        onPressed: _busy
                            ? null
                            : () => _runBusy(() async {
                                  if (!_removeDataKey.currentState!.validate()) return;
                                  final fromStr = DateFormat('yyyy-MM-dd').format(_removeFrom);
                                  final toStr = DateFormat('yyyy-MM-dd').format(_removeTo);
                                  final loomer = _removeDataLoomerController.text.trim().toLowerCase();
                                  await widget.controller.api.removeLoomData(
                                    loomerName: (loomer == 'all') ? '' : loomer,
                                    loomNumber: _removeDataLoomController.text.trim().toLowerCase(),
                                    shift: _removeDataShift,
                                    fromDateYYYYMMDD: fromStr,
                                    toDateYYYYMMDD: toStr,
                                  );
                                  if (mounted) _toast('Data removed');
                                }),
                        child: _busy
                            ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Remove Data'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 8),

        ExpansionTile(
          title: const Text('Warp Management'),
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Current Total Warp', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                                const SizedBox(height: 8),
                                Text(_loadingWarp ? 'Loading…' : _currentWarp.toStringAsFixed(2), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
                              ],
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: _busy ? null : _refreshWarp,
                        icon: const Icon(Icons.refresh),
                        tooltip: 'Refresh',
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  TextFormField(
                    controller: _warpValueController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                    decoration: const InputDecoration(
                      labelText: 'Value Change (+/-)',
                      helperText: 'Example: 10 adds, -5 subtracts',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _warpRemarksController,
                    decoration: const InputDecoration(labelText: 'Remarks (optional)'),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _pickWarpDate,
                      icon: const Icon(Icons.calendar_today),
                      label: Text('Date: ${DateFormat('yyyy-MM-dd').format(_warpDate)}'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _busy
                          ? null
                          : () => _runBusy(() async {
                                final value = double.tryParse(_warpValueController.text.trim()) ?? 0.0;
                                final dateStr = DateFormat('yyyy-MM-dd').format(_warpDate);
                                final newTotal = await widget.controller.api.updateWarp(
                                  valueChange: value,
                                  remarks: _warpRemarksController.text.trim(),
                                  dateYYYYMMDD: dateStr,
                                );
                                _warpValueController.clear();
                                _warpRemarksController.clear();
                                if (mounted) {
                                  setState(() => _currentWarp = newTotal);
                                  _toast('Warp updated. New total: ${newTotal.toStringAsFixed(2)}');
                                }
                              }),
                      child: _busy
                          ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Update Warp'),
                    ),
                  ),

                  const Divider(height: 32),

                  Text('Knotting Calculation', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _knottingController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Entered Knotting Count'),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonal(
                      onPressed: _busy
                          ? null
                          : () => _runBusy(() async {
                                final k = double.tryParse(_knottingController.text.trim()) ?? 0.0;
                                final remaining = await widget.controller.api.applyKnotting(
                                  knottingValue: k,
                                  currentTotalWarp: _currentWarp,
                                );
                                if (mounted) setState(() => _knottingResult = remaining);
                              }),
                      child: const Text('Calculate Remaining Warp'),
                    ),
                  ),
                  if (_knottingResult != null) ...[
                    const SizedBox(height: 8),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text('Remaining Warp: ${_knottingResult!.toStringAsFixed(2)}'),
                      ),
                    ),
                  ],

                  const Divider(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _busy
                          ? null
                          : () async {
                                try {
                                  final ctx = context;
                                  final history = await widget.controller.api.getWarpHistory();
                                  if (!ctx.mounted) return;
                                  showModalBottomSheet(
                                    context: ctx,
                                    showDragHandle: true,
                                    builder: (_) => ListView(
                                      padding: const EdgeInsets.all(16),
                                      children: [
                                        Text('Warp History', style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                                        const SizedBox(height: 12),
                                        if (history.isEmpty) const Text('No history yet.') else ...[
                                          ...history.map(
                                            (h) => Card(
                                              child: ListTile(
                                                title: Text('${h.changeType} • ${h.valueChange.toStringAsFixed(2)} → ${h.newTotalWarp.toStringAsFixed(2)}'),
                                                subtitle: Text('${h.username} • ${h.eventDate}\n${h.remarks}'.trim()),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  );
                                } catch (e) {
                                  if (!mounted) return;
                                  _toast(e.toString());
                                }
                              },
                      child: const Text('View Warp History'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}
