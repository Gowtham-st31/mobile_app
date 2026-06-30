import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_compress/video_compress.dart';

import '../api/api_client.dart';

/// Phases the video detection job moves through.
class DetectionPhase {
  static const String idle = 'idle';
  static const String compressing = 'compressing';
  static const String uploading = 'uploading';
  static const String detecting = 'detecting';
  static const String completed = 'completed';
  static const String error = 'error';
  static const String cancelled = 'cancelled';
}

/// Immutable snapshot of the detection job, observed by the UI.
@immutable
class VideoDetectionState {
  final String phase;
  final int compress;
  final int upload;
  final int detect;
  final String? message;
  final String? shift;
  final String? videoName;
  final List<Map<String, dynamic>> rows;

  const VideoDetectionState({
    this.phase = DetectionPhase.idle,
    this.compress = 0,
    this.upload = 0,
    this.detect = 0,
    this.message,
    this.shift,
    this.videoName,
    this.rows = const [],
  });

  bool get isIdle => phase == DetectionPhase.idle;

  bool get isActive =>
      phase == DetectionPhase.compressing ||
      phase == DetectionPhase.uploading ||
      phase == DetectionPhase.detecting;

  bool get isTerminal =>
      phase == DetectionPhase.completed ||
      phase == DetectionPhase.error ||
      phase == DetectionPhase.cancelled;

  VideoDetectionState copyWith({
    String? phase,
    int? compress,
    int? upload,
    int? detect,
    String? message,
    String? shift,
    String? videoName,
    List<Map<String, dynamic>>? rows,
  }) {
    return VideoDetectionState(
      phase: phase ?? this.phase,
      compress: compress ?? this.compress,
      upload: upload ?? this.upload,
      detect: detect ?? this.detect,
      message: message ?? this.message,
      shift: shift ?? this.shift,
      videoName: videoName ?? this.videoName,
      rows: rows ?? this.rows,
    );
  }

  Map<String, dynamic> toMap() => {
        'phase': phase,
        'compress': compress,
        'upload': upload,
        'detect': detect,
        'message': message,
        'shift': shift,
        'videoName': videoName,
        'rows': jsonEncode(rows),
      };

  static VideoDetectionState fromMap(Map<dynamic, dynamic> map) {
    List<Map<String, dynamic>> parsedRows = const [];
    final rawRows = map['rows'];
    if (rawRows is String && rawRows.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(rawRows);
        if (decoded is List) {
          parsedRows = decoded
              .whereType<Map>()
              .map((e) => e.cast<String, dynamic>())
              .toList(growable: false);
        }
      } catch (_) {
        parsedRows = const [];
      }
    }

    int asInt(dynamic v) {
      if (v is num) return v.round();
      return int.tryParse('${v ?? ''}') ?? 0;
    }

    return VideoDetectionState(
      phase: (map['phase'] ?? DetectionPhase.idle).toString(),
      compress: asInt(map['compress']),
      upload: asInt(map['upload']),
      detect: asInt(map['detect']),
      message: (map['message'] == null) ? null : map['message'].toString(),
      shift: (map['shift'] == null) ? null : map['shift'].toString(),
      videoName: (map['videoName'] == null) ? null : map['videoName'].toString(),
      rows: parsedRows,
    );
  }
}

/// Runs the compress -> upload -> detect pipeline.
///
/// The job is owned by this singleton (not the screen), so it keeps running when
/// the user navigates away from the page. Progress, the cancel action and the
/// detected rows are all driven from here so the UI updates reliably, and an
/// ongoing notification shows progress in the status bar. The job stops on
/// Cancel, on completion, or when the app process is fully closed.
class VideoDetectionService {
  VideoDetectionService._();
  static final VideoDetectionService instance = VideoDetectionService._();

  static const String _channelId = 'video_detection_channel';
  static const String _channelName = 'Video Detection';
  static const int _progressNotificationId = 778;
  static const int _resultNotificationId = 779;
  static const String _prefsStateKey = 'video_detection_state';

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  final ValueNotifier<VideoDetectionState> state =
      ValueNotifier<VideoDetectionState>(const VideoDetectionState());

  bool _configured = false;
  bool _running = false;
  CancelToken? _cancelToken;

  /// Call once during app startup, before runApp.
  Future<void> configure() async {
    if (_configured) return;
    _configured = true;

    await _notifications.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );

    final android = _notifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: 'Shows progress while uploading and detecting loom data.',
        importance: Importance.low,
      ),
    );
    await android?.requestNotificationsPermission();

    await _loadPersisted();
  }

  Future<void> _loadPersisted() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsStateKey);
      if (raw == null || raw.trim().isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final restored = VideoDetectionState.fromMap(decoded);
        // Only restore terminal results (an active job can't survive a process kill).
        if (restored.isTerminal) state.value = restored;
      }
    } catch (_) {
      // Ignore.
    }
  }

  void _setState(VideoDetectionState s) {
    state.value = s;
    _persist(s);
  }

  Future<void> _persist(VideoDetectionState s) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsStateKey, jsonEncode(s.toMap()));
    } catch (_) {}
  }

  Future<void> _showProgressNotification({
    required String title,
    required String content,
    required int progress,
    bool indeterminate = false,
  }) async {
    try {
      final androidDetails = AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: 'Shows progress while uploading and detecting loom data.',
        importance: Importance.low,
        priority: Priority.low,
        ongoing: true,
        autoCancel: false,
        onlyAlertOnce: true,
        showProgress: true,
        maxProgress: 100,
        progress: progress.clamp(0, 100),
        indeterminate: indeterminate,
      );
      await _notifications.show(
        _progressNotificationId,
        title,
        content,
        NotificationDetails(android: androidDetails),
      );
    } catch (_) {}
  }

  Future<void> _clearProgressNotification() async {
    try {
      await _notifications.cancel(_progressNotificationId);
    } catch (_) {}
  }

  Future<void> _showResultNotification(String title, String body) async {
    try {
      await _notifications.show(
        _resultNotificationId,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
      );
    } catch (_) {}
  }

  /// Starts a detection job. Returns immediately; observe [state] for progress.
  Future<void> start({
    required ApiClient api,
    required String videoPath,
    required String shift,
  }) async {
    await configure();
    if (_running) return;

    final videoName = videoPath.split(Platform.pathSeparator).last;
    _running = true;
    _cancelToken = CancelToken();

    _setState(VideoDetectionState(
      phase: DetectionPhase.compressing,
      shift: shift,
      videoName: videoName,
    ));
    await _clearProgressNotification();
    await _showProgressNotification(
      title: 'Compressing video',
      content: 'Optimising for upload...',
      progress: 0,
      indeterminate: true,
    );

    unawaited(_runPipeline(
      api: api,
      videoPath: videoPath,
      shift: shift,
      videoName: videoName,
    ));
  }

  Future<void> _runPipeline({
    required ApiClient api,
    required String videoPath,
    required String shift,
    required String videoName,
  }) async {
    final cancelToken = _cancelToken!;
    MediaInfo? compressed;
    String workingPath = videoPath;
    Subscription? progressSub;

    try {
      if (!File(videoPath).existsSync()) {
        throw const ApiException('Selected video is no longer available.');
      }

      // ---- 1) Compress for a faster upload ----
      progressSub = VideoCompress.compressProgress$.subscribe((progress) {
        if (cancelToken.isCancelled) return;
        final pct = progress.round().clamp(0, 100);
        _setState(state.value.copyWith(phase: DetectionPhase.compressing, compress: pct));
        _showProgressNotification(
          title: 'Compressing video',
          content: 'Optimising for upload... $pct%',
          progress: pct,
        );
      });

      try {
        compressed = await VideoCompress.compressVideo(
          videoPath,
          quality: VideoQuality.MediumQuality,
          deleteOrigin: false,
          includeAudio: true,
        );
      } catch (_) {
        compressed = null; // Fall back to the original on any compression failure.
      } finally {
        progressSub.unsubscribe();
        progressSub = null;
      }

      if (cancelToken.isCancelled) {
        await _finishCancelled(shift, videoName);
        return;
      }

      final cp = compressed?.path;
      if (cp != null && File(cp).existsSync()) workingPath = cp;
      _setState(state.value.copyWith(phase: DetectionPhase.compressing, compress: 100));

      // ---- 2) Upload + 3) server-side detection ----
      final rows = await api.detectVideoData(
        videoFile: File(workingPath),
        shift: shift,
        cancelToken: cancelToken,
        onProgress: (uploadPercent, detectPercent, phase) {
          if (cancelToken.isCancelled) return;
          if (phase == 'uploading') {
            _setState(state.value.copyWith(
              phase: DetectionPhase.uploading,
              compress: 100,
              upload: uploadPercent,
            ));
            _showProgressNotification(
              title: 'Uploading video',
              content: 'Uploading to server... $uploadPercent%',
              progress: uploadPercent,
            );
          } else {
            _setState(state.value.copyWith(
              phase: DetectionPhase.detecting,
              compress: 100,
              upload: 100,
              detect: detectPercent,
            ));
            _showProgressNotification(
              title: 'Detecting loom data',
              content: 'Processing on server... $detectPercent%',
              progress: detectPercent,
              indeterminate: detectPercent <= 0,
            );
          }
        },
      );

      if (cancelToken.isCancelled) {
        await _finishCancelled(shift, videoName);
        return;
      }

      _setState(VideoDetectionState(
        phase: DetectionPhase.completed,
        compress: 100,
        upload: 100,
        detect: 100,
        shift: shift,
        videoName: videoName,
        rows: rows,
      ));
      await _clearProgressNotification();
      await _showResultNotification(
        'Detection complete',
        '${rows.length} row(s) detected. Open the app to review and submit.',
      );
    } on ApiException catch (e) {
      if (cancelToken.isCancelled) {
        await _finishCancelled(shift, videoName);
      } else {
        _setState(VideoDetectionState(
          phase: DetectionPhase.error,
          message: e.message,
          shift: shift,
          videoName: videoName,
        ));
        await _clearProgressNotification();
        await _showResultNotification('Detection failed', e.message);
      }
    } catch (_) {
      if (cancelToken.isCancelled) {
        await _finishCancelled(shift, videoName);
      } else {
        const msg = 'Failed to detect data from video.';
        _setState(VideoDetectionState(
          phase: DetectionPhase.error,
          message: msg,
          shift: shift,
          videoName: videoName,
        ));
        await _clearProgressNotification();
        await _showResultNotification('Detection failed', msg);
      }
    } finally {
      progressSub?.unsubscribe();
      try {
        final p = compressed?.path;
        if (p != null && p != videoPath && File(p).existsSync()) {
          await File(p).delete();
        }
      } catch (_) {}
      _running = false;
      _cancelToken = null;
    }
  }

  Future<void> _finishCancelled(String shift, String videoName) async {
    _setState(VideoDetectionState(
      phase: DetectionPhase.cancelled,
      message: 'Cancelled.',
      shift: shift,
      videoName: videoName,
    ));
    await _clearProgressNotification();
  }

  /// Cancels a running job (upload or detection).
  Future<void> cancel() async {
    try {
      await VideoCompress.cancelCompression();
    } catch (_) {}
    _cancelToken?.cancel('cancelled');
    await _clearProgressNotification();
    if (!_running && state.value.isActive) {
      _setState(state.value.copyWith(phase: DetectionPhase.cancelled, message: 'Cancelled.'));
    }
  }

  /// Resets a terminal state back to idle so results aren't re-applied.
  Future<void> acknowledge() async {
    state.value = const VideoDetectionState();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsStateKey);
    } catch (_) {}
    try {
      await _notifications.cancel(_resultNotificationId);
    } catch (_) {}
  }
}
