import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_controller.dart';
import '../models/report.dart';
import '../models/session.dart';

class ReportsScreen extends StatefulWidget {
  final AppController controller;
  final Session session;

  const ReportsScreen({super.key, required this.controller, required this.session});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _loomerController;
  final _loomController = TextEditingController(text: 'all');

  String _shift = 'all';
  DateTime _from = DateTime.now();
  DateTime _to = DateTime.now();

  bool _loading = false;
  ReportResult? _result;
  bool _downloadingPdf = false;

  bool get _isAdmin => widget.session.role.toLowerCase() == 'admin';

  @override
  void initState() {
    super.initState();
    _loomerController = TextEditingController(text: _isAdmin ? 'all' : widget.session.username);
  }

  @override
  void dispose() {
    _loomerController.dispose();
    _loomController.dispose();
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
      _result = null;
    });

    try {
      final fromStr = DateFormat('yyyy-MM-dd').format(_from);
      final toStr = DateFormat('yyyy-MM-dd').format(_to);

      final report = await widget.controller.api.getMetersReport(
        loomerName: _loomerController.text.trim().toLowerCase(),
        shift: _shift,
        loomNumber: _loomController.text.trim().toLowerCase(),
        fromDateYYYYMMDD: fromStr,
        toDateYYYYMMDD: toStr,
      );

      if (!mounted) return;
      setState(() => _result = report);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _downloadPdf() async {
    final result = _result;
    if (result == null) return;

    setState(() => _downloadingPdf = true);
    try {
      final fromStr = DateFormat('yyyy-MM-dd').format(_from);
      final toStr = DateFormat('yyyy-MM-dd').format(_to);
      final loomer = _loomerController.text.trim().toLowerCase();

      final file = await widget.controller.api.downloadReportPdf(
        loomerName: loomer,
        shift: _shift,
        fromDateYYYYMMDD: fromStr,
        toDateYYYYMMDD: toStr,
        totalMeters: result.totalMeters,
        totalSalary: result.totalSalary,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved PDF to: ${file.path}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _downloadingPdf = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Production Report', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
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
                value: _shift,
                decoration: const InputDecoration(labelText: 'Shift'),
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('All Shifts')),
                  DropdownMenuItem(value: 'Morning', child: Text('Morning')),
                  DropdownMenuItem(value: 'Night', child: Text('Night')),
                ],
                onChanged: _loading ? null : (v) => setState(() => _shift = v ?? 'all'),
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _loomController,
                decoration: const InputDecoration(
                  labelText: 'Loom Number',
                  helperText: 'Use "all" for all looms',
                ),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
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
                      : const Text('Generate Report'),
                ),
              ),
            ],
          ),
        ),

        if (result != null) ...[
          const SizedBox(height: 16),
          _SummaryCard(result: result),
          const SizedBox(height: 12),

          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: (_loading || _downloadingPdf) ? null : _downloadPdf,
              icon: _downloadingPdf
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.picture_as_pdf),
              label: Text(_downloadingPdf ? 'Downloading…' : 'Download PDF'),
            ),
          ),
          const SizedBox(height: 12),

          ExpansionTile(
            title: const Text('Subtotals per Loom'),
            children: result.loomSubtotals
                .map((s) => ListTile(
                      title: Text('Loom ${s.key}'),
                      subtitle: Text('Meters: ${s.totalMeters}'),
                      trailing: Text('₹${s.totalSalary}'),
                    ))
                .toList(growable: false),
          ),
          const SizedBox(height: 8),

          ExpansionTile(
            title: const Text('Subtotals per Day'),
            children: result.dailySubtotals
                .map((s) => ListTile(
                      title: Text(s.key),
                      subtitle: Text('Meters: ${s.totalMeters}'),
                      trailing: Text('₹${s.totalSalary}'),
                    ))
                .toList(growable: false),
          ),
          const SizedBox(height: 8),

          Text('Detailed Records', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          ...result.records.map((r) => _RecordTile(record: r)),
          const SizedBox(height: 16),
        ],
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final ReportResult result;

  const _SummaryCard({required this.result});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Total Meters', style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text('${result.totalMeters}', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
                ],
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Total Salary', style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text('₹${result.totalSalary}', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecordTile extends StatelessWidget {
  final ReportRecord record;

  const _RecordTile({required this.record});

  @override
  Widget build(BuildContext context) {
    final date = record.dateFormatted ?? '';
    return Card(
      child: ListTile(
        title: Text('${record.loomerName} • Loom ${record.loomNumber} • ${record.shift}'),
        subtitle: Text('$date\nMeters: ${record.meters} • Salary/m: ₹${record.salaryPerMeter}'),
        isThreeLine: true,
        trailing: Text('₹${record.calculatedSalary}', style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
    );
  }
}
