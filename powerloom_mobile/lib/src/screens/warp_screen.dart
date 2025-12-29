import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_controller.dart';
import '../models/session.dart';
import '../models/warp_history.dart';

class WarpScreen extends StatefulWidget {
  final AppController controller;
  final Session session;

  const WarpScreen({super.key, required this.controller, required this.session});

  @override
  State<WarpScreen> createState() => _WarpScreenState();
}

class _WarpScreenState extends State<WarpScreen> {
  bool _loading = false;
  double _currentWarp = 0.0;
  List<WarpHistoryRecord> _history = const [];

  bool _busy = false;
  final _warpValueController = TextEditingController();
  final _warpRemarksController = TextEditingController();
  DateTime _warpDate = DateTime.now();

  final _knottingController = TextEditingController();
  double? _knottingResult;

  bool get _isAdmin => widget.session.role.toLowerCase() == 'admin';

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _warpValueController.dispose();
    _warpRemarksController.dispose();
    _knottingController.dispose();
    super.dispose();
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final warp = await widget.controller.api.getCurrentWarp();
      final history = await widget.controller.api.getWarpHistory();
      if (!mounted) return;
      setState(() {
        _currentWarp = warp;
        _history = history;
      });
    } catch (e) {
      if (!mounted) return;
      _toast(e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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

  Future<void> _runBusy(Future<void> Function() fn) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await fn();
    } catch (e) {
      if (mounted) _toast(e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Warp', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Current Total Warp', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 8),
                        Text(
                          _loading ? 'Loading…' : _currentWarp.toStringAsFixed(2),
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _busy ? null : _refresh,
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Refresh',
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          if (_isAdmin)
            ExpansionTile(
              title: const Text('Admin Actions'),
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
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
                                    if (!mounted) return;
                                    setState(() => _currentWarp = newTotal);
                                    await _refresh();
                                    if (mounted) _toast('Warp updated. New total: ${newTotal.toStringAsFixed(2)}');
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
                    ],
                  ),
                ),
              ],
            ),

          const SizedBox(height: 12),

          Text('History', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),

          if (_loading)
            const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
          else if (_history.isEmpty)
            const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('No history yet.')))
          else
            ..._history.map(
              (h) => Card(
                child: ListTile(
                  title: Text('${h.changeType} • ${h.valueChange.toStringAsFixed(2)} → ${h.newTotalWarp.toStringAsFixed(2)}'),
                  subtitle: Text('${h.username} • ${h.eventDate}\n${h.remarks}'.trim()),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
