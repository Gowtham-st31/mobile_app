import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_controller.dart';
import '../models/session.dart';

class EnterDataScreen extends StatefulWidget {
  final AppController controller;
  final Session session;

  const EnterDataScreen({super.key, required this.controller, required this.session});

  @override
  State<EnterDataScreen> createState() => _EnterDataScreenState();
}

class _EnterDataScreenState extends State<EnterDataScreen> {
  final _formKey = GlobalKey<FormState>();

  final _loomerController = TextEditingController();
  final _loomController = TextEditingController();
  final _metersController = TextEditingController();
  final _salaryController = TextEditingController();

  String _shift = 'Morning';
  DateTime _date = DateTime.now();
  bool _submitting = false;

  @override
  void dispose() {
    _loomerController.dispose();
    _loomController.dispose();
    _metersController.dispose();
    _salaryController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final selected = await showDatePicker(
      context: context,
      firstDate: DateTime(2000, 1, 1),
      lastDate: DateTime(2100, 12, 31),
      initialDate: _date,
    );
    if (selected == null) return;
    setState(() => _date = selected);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final loomer = _loomerController.text.trim().toLowerCase();
    final loom = _loomController.text.trim().toLowerCase();
    final meters = int.tryParse(_metersController.text.trim());
    final salary = double.tryParse(_salaryController.text.trim());

    if (meters == null || salary == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter valid meters and salary values.')));
      return;
    }

    setState(() => _submitting = true);
    try {
      final dateStr = DateFormat('yyyy-MM-dd').format(_date);
      await widget.controller.api.addLoomData(
        loomerName: loomer,
        loomNumber: loom,
        shift: _shift,
        meters: meters,
        salaryPerMeter: salary,
        dateYYYYMMDD: dateStr,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Data added successfully.')));
      _metersController.clear();
      _salaryController.clear();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Enter Loom Data', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),

            TextFormField(
              controller: _loomerController,
              decoration: const InputDecoration(labelText: 'Loomer Name'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 12),

            TextFormField(
              controller: _loomController,
              decoration: const InputDecoration(labelText: 'Loom Number'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 12),

            DropdownButtonFormField<String>(
              value: _shift,
              decoration: const InputDecoration(labelText: 'Shift'),
              items: const [
                DropdownMenuItem(value: 'Morning', child: Text('Morning')),
                DropdownMenuItem(value: 'Night', child: Text('Night')),
              ],
              onChanged: _submitting ? null : (v) => setState(() => _shift = v ?? 'Morning'),
            ),
            const SizedBox(height: 12),

            TextFormField(
              controller: _metersController,
              decoration: const InputDecoration(labelText: 'Meters'),
              keyboardType: TextInputType.number,
              validator: (v) {
                final value = int.tryParse((v ?? '').trim());
                if (value == null) return 'Enter a valid number';
                if (value < 0) return 'Cannot be negative';
                return null;
              },
            ),
            const SizedBox(height: 12),

            TextFormField(
              controller: _salaryController,
              decoration: const InputDecoration(labelText: 'Salary per Meter'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: (v) {
                final value = double.tryParse((v ?? '').trim());
                if (value == null) return 'Enter a valid number';
                if (value < 0) return 'Cannot be negative';
                return null;
              },
            ),
            const SizedBox(height: 12),

            OutlinedButton.icon(
              onPressed: _submitting ? null : _pickDate,
              icon: const Icon(Icons.calendar_today),
              label: Text('Date: ${DateFormat('yyyy-MM-dd').format(_date)}'),
            ),
            const SizedBox(height: 16),

            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Submit Data'),
            ),
          ],
        ),
      ),
    );
  }
}
