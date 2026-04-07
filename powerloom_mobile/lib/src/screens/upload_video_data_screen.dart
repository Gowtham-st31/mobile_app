import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../app_controller.dart';
import '../models/session.dart';

class UploadVideoDataScreen extends StatefulWidget {
  final AppController controller;
  final Session session;

  const UploadVideoDataScreen({
    super.key,
    required this.controller,
    required this.session,
  });

  @override
  State<UploadVideoDataScreen> createState() => _UploadVideoDataScreenState();
}

class _UploadVideoDataScreenState extends State<UploadVideoDataScreen> {
  final _formKey = GlobalKey<FormState>();

  final _loomerController = TextEditingController();
  final _loomController = TextEditingController();
  final _metersController = TextEditingController();
  final _salaryController = TextEditingController();

  final ImagePicker _picker = ImagePicker();

  String _shift = 'Morning';
  DateTime _date = DateTime.now();

  bool _detecting = false;
  bool _submitting = false;
  bool _cameraInitializing = false;
  bool _recording = false;
  bool _recordingPaused = false;

  File? _selectedVideoFile;

  CameraController? _cameraController;
  List<_DetectedRowEditor> _detectedRows = [];

  @override
  void initState() {
    super.initState();

    _loomController.addListener(() {
      if (_detectedRows.isEmpty) return;
      final controller = _detectedRows.first.loomController;
      if (controller.text == _loomController.text) return;
      controller.text = _loomController.text;
      controller.selection = TextSelection.collapsed(offset: controller.text.length);
    });

    _metersController.addListener(() {
      if (_detectedRows.isEmpty) return;
      final controller = _detectedRows.first.metersController;
      if (controller.text == _metersController.text) return;
      controller.text = _metersController.text;
      controller.selection = TextSelection.collapsed(offset: controller.text.length);
    });
  }

  @override
  void dispose() {
    _disposeCamera();
    _clearDetectedRows();

    _loomerController.dispose();
    _loomController.dispose();
    _metersController.dispose();
    _salaryController.dispose();
    super.dispose();
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  String _normalizeLoomNumber(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';

    final parsed = int.tryParse(trimmed);
    if (parsed == null) return trimmed;
    return parsed.toString();
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

  Future<void> _pickVideoFromGallery() async {
    try {
      final picked = await _picker.pickVideo(source: ImageSource.gallery);
      if (picked == null) return;

      setState(() {
        _selectedVideoFile = File(picked.path);
      });

      await _runDetection(autoTriggered: true);
    } catch (e) {
      _showMessage('Unable to pick video: $e');
    }
  }

  Future<bool> _ensureCameraReady() async {
    if (_cameraController != null && _cameraController!.value.isInitialized) {
      return true;
    }

    setState(() => _cameraInitializing = true);
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        _showMessage('No camera found on this device.');
        return false;
      }

      final selected = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      await _disposeCamera();

      final controller = CameraController(
        selected,
        ResolutionPreset.medium,
        enableAudio: true,
      );

      await controller.initialize();
      await controller.prepareForVideoRecording();

      if (!mounted) {
        await controller.dispose();
        return false;
      }

      setState(() {
        _cameraController = controller;
      });
      return true;
    } catch (e) {
      _showMessage('Unable to initialize camera: $e');
      return false;
    } finally {
      if (mounted) {
        setState(() => _cameraInitializing = false);
      }
    }
  }

  Future<void> _startRecording() async {
    if (_recording || _cameraInitializing) return;

    final ready = await _ensureCameraReady();
    if (!ready) return;

    final controller = _cameraController;
    if (controller == null) return;

    try {
      await controller.startVideoRecording();
      if (!mounted) return;
      setState(() {
        _recording = true;
        _recordingPaused = false;
        _selectedVideoFile = null;
      });
      _showMessage('Recording started.');
    } catch (e) {
      _showMessage('Failed to start recording: $e');
    }
  }

  Future<void> _pauseRecording() async {
    final controller = _cameraController;
    if (controller == null || !_recording || _recordingPaused) return;

    try {
      await controller.pauseVideoRecording();
      if (!mounted) return;
      setState(() {
        _recordingPaused = true;
      });
      _showMessage('Recording paused.');
    } catch (e) {
      _showMessage('Failed to pause recording: $e');
    }
  }

  Future<void> _resumeRecording() async {
    final controller = _cameraController;
    if (controller == null || !_recording || !_recordingPaused) return;

    try {
      await controller.resumeVideoRecording();
      if (!mounted) return;
      setState(() {
        _recordingPaused = false;
      });
      _showMessage('Recording resumed.');
    } catch (e) {
      _showMessage('Failed to resume recording: $e');
    }
  }

  Future<void> _stopRecording() async {
    final controller = _cameraController;
    if (controller == null || !_recording) return;

    try {
      final file = await controller.stopVideoRecording();
      if (!mounted) return;

      setState(() {
        _recording = false;
        _recordingPaused = false;
        _selectedVideoFile = File(file.path);
      });

      _showMessage('Recording stopped. Auto-detecting data...');
      await _runDetection(autoTriggered: true);
    } catch (e) {
      _showMessage('Failed to stop recording: $e');
    }
  }

  Future<void> _disposeCamera() async {
    final controller = _cameraController;
    _cameraController = null;
    if (controller != null) {
      await controller.dispose();
    }
  }

  String _videoName(File file) => file.path.split(Platform.pathSeparator).last;

  void _clearDetectedRows() {
    for (final row in _detectedRows) {
      row.dispose();
    }
    _detectedRows = [];
  }

  void _applyDetectedRows(List<Map<String, dynamic>> rows) {
    _clearDetectedRows();

    final normalizedRows = <_DetectedRowEditor>[];
    for (final row in rows) {
      final loomRaw = (row['loom_number'] ?? row['loom'] ?? '').toString();
      final metersRaw = row['meters'];

      final loom = _normalizeLoomNumber(loomRaw);
      final meters = int.tryParse('$metersRaw');
      if (loom.isEmpty || meters == null) {
        continue;
      }

      normalizedRows.add(_DetectedRowEditor(loomNumber: loom, meters: meters));
    }

    if (normalizedRows.isEmpty) {
      throw StateError('No valid detected rows found.');
    }

    setState(() {
      _detectedRows = normalizedRows;
      _loomController.text = normalizedRows.first.loomController.text;
      _metersController.text = normalizedRows.first.metersController.text;
    });
  }

  Future<void> _runDetection({bool autoTriggered = false}) async {
    final file = _selectedVideoFile;
    if (file == null) {
      if (!autoTriggered) {
        _showMessage('Please upload or record a video first.');
      }
      return;
    }

    setState(() => _detecting = true);
    try {
      final rows = await widget.controller.api.detectVideoData(
        videoFile: file,
        shift: _shift,
      );

      if (rows.isEmpty) {
        _showMessage('No rows detected from this video.');
        return;
      }

      _applyDetectedRows(rows);
      _showMessage('${rows.length} rows detected. You can edit before submitting.');
    } catch (e) {
      _showMessage(e.toString());
    } finally {
      if (mounted) setState(() => _detecting = false);
    }
  }

  List<Map<String, dynamic>> _collectRowsForSubmit() {
    if (_detectedRows.isEmpty) {
      final loom = _normalizeLoomNumber(_loomController.text);
      final meters = int.tryParse(_metersController.text.trim());
      if (loom.isEmpty || meters == null) {
        return const [];
      }
      return [
        {
          'loom_number': loom,
          'meters': meters,
        }
      ];
    }

    final rows = <Map<String, dynamic>>[];
    for (final row in _detectedRows) {
      final loom = _normalizeLoomNumber(row.loomController.text);
      final meters = int.tryParse(row.metersController.text.trim());
      if (loom.isEmpty || meters == null) {
        throw const FormatException('Each detected row needs valid loom number and meters.');
      }
      rows.add({'loom_number': loom, 'meters': meters});
    }

    if (rows.isNotEmpty) {
      final firstLoom = _normalizeLoomNumber(_loomController.text);
      final firstMeters = int.tryParse(_metersController.text.trim());
      if (firstLoom.isNotEmpty && firstMeters != null) {
        rows[0] = {'loom_number': firstLoom, 'meters': firstMeters};
      }
    }

    return rows;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final loomer = _loomerController.text.trim().toLowerCase();
    final salary = double.tryParse(_salaryController.text.trim());
    if (salary == null) {
      _showMessage('Enter a valid salary per meter.');
      return;
    }

    setState(() => _submitting = true);
    try {
      final dateStr = DateFormat('yyyy-MM-dd').format(_date);
      final rows = _collectRowsForSubmit();
      if (rows.isEmpty) {
        _showMessage('Please detect or enter valid loom data before submitting.');
        return;
      }

      if (_detectedRows.isNotEmpty) {
        final inserted = await widget.controller.api.addVideoBulkData(
          loomerName: loomer,
          shift: _shift,
          salaryPerMeter: salary,
          dateYYYYMMDD: dateStr,
          rows: rows,
        );
        if (!mounted) return;
        _showMessage('$inserted rows submitted successfully.');
      } else {
        await widget.controller.api.addLoomData(
          loomerName: loomer,
          loomNumber: _normalizeLoomNumber(_loomController.text).toLowerCase(),
          shift: _shift,
          meters: int.parse(_metersController.text.trim()),
          salaryPerMeter: salary,
          dateYYYYMMDD: dateStr,
        );
        if (!mounted) return;
        _showMessage('Data added successfully.');
      }
    } on FormatException catch (e) {
      _showMessage(e.message);
    } catch (e) {
      _showMessage(e.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cameraController = _cameraController;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Upload Data with Video'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Upload / Record and Auto Detect',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                Text(
                  'Detect values, edit if needed, then submit.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),

                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    OutlinedButton.icon(
                      onPressed: (_detecting || _submitting) ? null : _pickVideoFromGallery,
                      icon: const Icon(Icons.video_library),
                      label: const Text('Upload Video File'),
                    ),
                    FilledButton.icon(
                      onPressed: (_detecting || _submitting) ? null : () => _runDetection(autoTriggered: false),
                      icon: _detecting
                          ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.search),
                      label: const Text('Auto Detect from Video'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                if (_selectedVideoFile != null)
                  Text(
                    'Selected video: ${_videoName(_selectedVideoFile!)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),

                const SizedBox(height: 14),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('Record Video', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            FilledButton(
                              onPressed: (_submitting || _detecting || _recording || _cameraInitializing) ? null : _startRecording,
                              child: _cameraInitializing
                                  ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Text('Start Recording'),
                            ),
                            OutlinedButton(
                              onPressed: (!_recording || _recordingPaused || _submitting || _detecting) ? null : _pauseRecording,
                              child: const Text('Pause'),
                            ),
                            OutlinedButton(
                              onPressed: (!_recording || !_recordingPaused || _submitting || _detecting) ? null : _resumeRecording,
                              child: const Text('Resume'),
                            ),
                            OutlinedButton(
                              onPressed: (!_recording || _submitting || _detecting) ? null : _stopRecording,
                              child: const Text('Stop'),
                            ),
                          ],
                        ),
                        if (cameraController != null && cameraController.value.isInitialized) ...[
                          const SizedBox(height: 10),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: AspectRatio(
                              aspectRatio: cameraController.value.aspectRatio,
                              child: CameraPreview(cameraController),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),
                TextFormField(
                  controller: _loomerController,
                  decoration: const InputDecoration(labelText: 'Loomer Name'),
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
                  onChanged: (_submitting || _detecting) ? null : (v) => setState(() => _shift = v ?? 'Morning'),
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _loomController,
                  decoration: const InputDecoration(labelText: 'Loom Number (Auto Detected, Editable)'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _metersController,
                  decoration: const InputDecoration(labelText: 'Meters (Auto Detected, Editable)'),
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
                  onPressed: (_submitting || _detecting) ? null : _pickDate,
                  icon: const Icon(Icons.calendar_today),
                  label: Text('Date: ${DateFormat('yyyy-MM-dd').format(_date)}'),
                ),

                if (_detectedRows.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text('Detected Rows (Editable)', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemBuilder: (context, index) {
                      final row = _detectedRows[index];
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            children: [
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text('Row ${index + 1}', style: Theme.of(context).textTheme.labelLarge),
                              ),
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: row.loomController,
                                decoration: const InputDecoration(labelText: 'Loom Number'),
                              ),
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: row.metersController,
                                decoration: const InputDecoration(labelText: 'Meters'),
                                keyboardType: TextInputType.number,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemCount: _detectedRows.length,
                  ),
                ],

                const SizedBox(height: 18),
                FilledButton(
                  onPressed: (_submitting || _detecting) ? null : _submit,
                  child: _submitting
                      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Submit Data'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DetectedRowEditor {
  final TextEditingController loomController;
  final TextEditingController metersController;

  _DetectedRowEditor({required String loomNumber, required int meters})
      : loomController = TextEditingController(text: loomNumber),
        metersController = TextEditingController(text: meters.toString());

  void dispose() {
    loomController.dispose();
    metersController.dispose();
  }
}
