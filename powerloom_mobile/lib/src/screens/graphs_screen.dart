import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

import '../app_controller.dart';
import '../models/graph_data.dart';
import '../models/session.dart';

class GraphsScreen extends StatefulWidget {
  final AppController controller;
  final Session session;

  const GraphsScreen({super.key, required this.controller, required this.session});

  @override
  State<GraphsScreen> createState() => _GraphsScreenState();
}

class _GraphsScreenState extends State<GraphsScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _loomerController;
  String _period = 'day';
  DateTime _from = DateTime.now();
  DateTime _to = DateTime.now();

  bool _loading = false;
  GraphData? _data;

  bool get _isAdmin => widget.session.role.toLowerCase() == 'admin';

  @override
  void initState() {
    super.initState();
    _loomerController = TextEditingController(text: _isAdmin ? 'all' : widget.session.username);
  }

  @override
  void dispose() {
    _loomerController.dispose();
    super.dispose();
  }

  Future<void> _pickFrom() async {
    final selected = await showDatePicker(
      context: context,
      firstDate: DateTime(2000, 1, 1),
      lastDate: DateTime(2100, 12, 31),
      initialDate: _from,
    );
    if (selected == null) return;
    setState(() => _from = selected);
  }

  Future<void> _pickTo() async {
    final selected = await showDatePicker(
      context: context,
      firstDate: DateTime(2000, 1, 1),
      lastDate: DateTime(2100, 12, 31),
      initialDate: _to,
    );
    if (selected == null) return;
    setState(() => _to = selected);
  }

  Future<void> _run() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _loading = true;
      _data = null;
    });

    try {
      final fromStr = DateFormat('yyyy-MM-dd').format(_from);
      final toStr = DateFormat('yyyy-MM-dd').format(_to);

      final data = await widget.controller.api.getGraphData(
        loomerName: _loomerController.text.trim().toLowerCase(),
        period: _period,
        fromDateYYYYMMDD: fromStr,
        toDateYYYYMMDD: toStr,
      );

      if (!mounted) return;
      setState(() => _data = data);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _buildMetersChart(GraphData data) {
    if (data.labels.isEmpty || data.meters.isEmpty) {
      return const SizedBox.shrink();
    }

    final spots = <FlSpot>[];
    for (var i = 0; i < data.meters.length; i++) {
      final y = data.meters[i].toDouble();
      spots.add(FlSpot(i.toDouble(), y));
    }

    final maxY = data.meters.fold<double>(0.0, (m, e) => e.toDouble() > m ? e.toDouble() : m);
    final minY = data.meters.fold<double>(maxY, (m, e) => e.toDouble() < m ? e.toDouble() : m);

    final accent = Theme.of(context).colorScheme.primary;
    final labelColor = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8);

    return SizedBox(
      height: 240,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: (data.meters.length - 1).toDouble(),
          minY: (minY - (maxY - minY) * 0.1).isFinite ? (minY - (maxY - minY) * 0.1) : 0,
          maxY: (maxY + (maxY - minY) * 0.1).isFinite ? (maxY + (maxY - minY) * 0.1) : maxY,
          gridData: FlGridData(show: true, drawVerticalLine: false, horizontalInterval: (maxY / 4).clamp(1, double.infinity)),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 42,
                getTitlesWidget: (value, meta) => Text(value.toStringAsFixed(0), style: TextStyle(color: labelColor, fontSize: 11)),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 34,
                interval: (data.labels.length / 4).clamp(1, data.labels.length.toDouble()),
                getTitlesWidget: (value, meta) {
                  final idx = value.round();
                  if (idx < 0 || idx >= data.labels.length) return const SizedBox.shrink();
                  final text = data.labels[idx];
                  return SideTitleWidget(
                    axisSide: meta.axisSide,
                    child: Text(text, style: TextStyle(color: labelColor, fontSize: 10)),
                  );
                },
              ),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: accent,
              barWidth: 3,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(show: true, color: accent.withValues(alpha: 0.12)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Production Graphs', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),

        Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _loomerController,
                enabled: _isAdmin,
                decoration: InputDecoration(
                  labelText: 'Loomer Name',
                  helperText: _isAdmin ? 'Use "all" for all loomers' : null,
                ),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),

              DropdownButtonFormField<String>(
                value: _period,
                decoration: const InputDecoration(labelText: 'Period'),
                items: const [
                  DropdownMenuItem(value: 'day', child: Text('Daily')),
                  DropdownMenuItem(value: 'week', child: Text('Weekly')),
                  DropdownMenuItem(value: 'month', child: Text('Monthly')),
                  DropdownMenuItem(value: 'year', child: Text('Yearly')),
                ],
                onChanged: _loading ? null : (v) => setState(() => _period = v ?? 'day'),
              ),
              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _loading ? null : _pickFrom,
                      icon: const Icon(Icons.calendar_today),
                      label: Text('From: ${DateFormat('yyyy-MM-dd').format(_from)}'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _loading ? null : _pickTo,
                      icon: const Icon(Icons.calendar_today),
                      label: Text('To: ${DateFormat('yyyy-MM-dd').format(_to)}'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _loading ? null : _run,
                  child: _loading
                      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Load Graph Data'),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),
        if (data != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
                    child: Row(
                      children: [
                        Text('Meters', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: _buildMetersChart(data),
                  ),
                  const SizedBox(height: 8),
                  for (var i = 0; i < data.labels.length; i++)
                    ListTile(
                      title: Text(data.labels[i]),
                      subtitle: Text('Meters: ${data.meters[i]}'),
                      trailing: Text('₹${data.salary[i]}', style: const TextStyle(fontWeight: FontWeight.w800)),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
