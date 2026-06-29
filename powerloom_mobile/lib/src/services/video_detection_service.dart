import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show DartPluginRegistrant;

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_compress/video_compress.dart';

import '../api/api_client.dart';

/// Phases the background video detection job moves through.
class DetectionPhase {
  static const String idle = 'idle';
  static const String compressing = 'compressing';
  static const String uploading = 'uploading';
  static const String detecting = 'detecting';
  static const String completed = 'completed';
  static const String error = 'error';
  static const String cancelled = 'cancelled';
}

/// Immutable snapshot of the background detection job.
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

/// Coordinates the background compress -> upload -> detect pipeline.
///
/// The heavy work runs in a separate background isolate via
/// [FlutterBackgroundService] so it keeps going (with an ongoing notification)
/// even when the user leaves the page or sends the app to the background.
/// It only stops when the user taps Cancel or fully closes the app.
class VideoDetectionService {
  VideoDetectionService._();
  static final VideoDetectionService instance = VideoDetectionService._();

  static const String notificationChannelId = 'video_detection_channel';
  static const int notificationId = 778;
  static const String _prefsStateKey = 'video_detection_state';
  static const String _prefsRequestKey = 'video_detection_request';

  final FlutterBackgroundService _service = FlutterBackgroundService();
  final ValueNotifier<VideoDetectionState> state =
      ValueNotifier<VideoDetectionState>(const VideoDetectionState());

  StreamSubscription<Map<String, dynamic>?>? _updateSub;
  bool _configured = false;

  /// Must be called once during app startup (before runApp).
  Future<void> configure() async {
    if (_configured) return;
    _configured = true;

    // Ensure the notification channel exists with an importance Android accepts
    // for a foreground service notification.
    final localNotifications = FlutterLocalNotificationsPlugin();
    const channel = AndroidNotificationChannel(
      notificationChannelId,
      'Video Detection',
      description: 'Shows progress while uploading and detecting loom data.',
      importance: Importance.low,
    );
    await localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    await _service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: _onStart,
        autoStart: false,
        isForegroundMode: true,
        notificationChannelId: notificationChannelId,
        initialNotificationTitle: 'Video detection',
        initialNotificationContent: 'Preparing...',
        foregroundServiceNotificationId: notificationId,
        foregroundServiceTypes: [AndroidForegroundType.dataSync],
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: _onStart,
        onBackground: _onIosBackground,
      ),
    );

    // Restore any persisted state (e.g. a job that finished while the UI was gone).
    await loadPersisted();

    // Listen for live progress updates coming from the background isolate.
    _updateSub?.cancel();
    _updateSub = _service.on('update').listen((event) {
      if (event == null) return;
      state.value = VideoDetectionState.fromMap(event);
    });
  }

  /// Re-reads the last persisted job state. Useful when returning to the screen
  /// after the background isolate produced a result while the UI wasn't listening.
  Future<void> loadPersisted() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final raw = prefs.getString(_prefsStateKey);
      if (raw == null || raw.trim().isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        state.value = VideoDetectionState.fromMap(decoded);
      }
    } catch (_) {
      // Ignore: keep current in-memory state.
    }
  }

  /// Starts (or queues) a detection job for [videoPath].
  Future<void> start({
    required String baseUrl,
    required String videoPath,
    required String shift,
  }) async {
    await configure();

    final videoName = videoPath.split(Platform.pathSeparator).last;

    // Optimistic local state so the UI reacts immediately.
    state.value = VideoDetectionState(
      phase: DetectionPhase.compressing,
      shift: shift,
      videoName: videoName,
    );

    final request = <String, dynamic>{
      'baseUrl': baseUrl,
      'videoPath': videoPath,
      'shift': shift,
      'videoName': videoName,
    };

    // Persist the request so the background isolate can pick it up even if the
    // invoke below races the isolate startup.
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsRequestKey, jsonEncode(request));
      await prefs.setString(_prefsStateKey, jsonEncode(state.value.toMap()));
    } catch (_) {
      // Non-fatal.
    }

    final running = await _service.isRunning();
    if (!running) {
      await _service.startService();
    }
    // Nudge the isolate (handles the already-running case too).
    _service.invoke('startDetection', request);
  }

  /// Requests cancellation of the running job and stops the service.
  Future<void> cancel() async {
    _service.invoke('cancel');
    // Reflect cancellation locally right away.
    final current = state.value;
    if (current.isActive) {
      state.value = VideoDetectionState(
        phase: DetectionPhase.cancelled,
        message: 'Cancelled.',
        shift: current.shift,
        videoName: current.videoName,
      );
    }
  }

  /// Clears a terminal (completed/error/cancelled) state back to idle so the UI
  /// doesn't keep re-applying the same result.
  Future<void> acknowledge() async {
    state.value = const VideoDetectionState();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsStateKey);
      await prefs.remove(_prefsRequestKey);
    } catch (_) {
      // Ignore.
    }
  }
}

// ---------------------------------------------------------------------------
// Background isolate entry points
// ---------------------------------------------------------------------------

@pragma('vm:entry-point')
Future<bool> _onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  return true;
}

@pragma('vm:entry-point')
void _onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  bool busy = false;
  CancelToken? activeToken;

  final resultNotifier = FlutterLocalNotificationsPlugin();
  bool resultNotifierInited = false;

  Future<void> showResultNotification(String title, String body) async {
    try {
      if (!resultNotifierInited) {
        await resultNotifier.initialize(
          const InitializationSettings(
            android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          ),
        );
        resultNotifierInited = true;
      }
      await resultNotifier.show(
        VideoDetectionService.notificationId + 1,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            VideoDetectionService.notificationChannelId,
            'Video Detection',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
      );
    } catch (_) {
      // Best-effort: notification is non-critical.
    }
  }

  Future<void> persistState(Map<String, dynamic> stateMap) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        VideoDetectionService._prefsStateKey,
        jsonEncode(stateMap),
      );
    } catch (_) {
      // Ignore persistence errors.
    }
  }

  Future<void> emit({
    required String phase,
    int compress = 0,
    int upload = 0,
    int detect = 0,
    String? message,
    String? shift,
    String? videoName,
    List<Map<String, dynamic>> rows = const [],
  }) async {
    final stateMap = <String, dynamic>{
      'phase': phase,
      'compress': compress,
      'upload': upload,
      'detect': detect,
      'message': message,
      'shift': shift,
      'videoName': videoName,
      'rows': jsonEncode(rows),
    };
    service.invoke('update', stateMap);
    await persistState(stateMap);

    if (service is AndroidServiceInstance) {
      String title;
      String content;
      switch (phase) {
        case DetectionPhase.compressing:
          title = 'Compressing video';
          content = 'Optimising video for upload... $compress%';
          break;
        case DetectionPhase.uploading:
          title = 'Uploading video';
          content = 'Uploading to server... $upload%';
          break;
        case DetectionPhase.detecting:
          title = 'Detecting loom data';
          content = 'Processing on server... $detect%';
          break;
        case DetectionPhase.completed:
          title = 'Detection complete';
          content = '${rows.length} row(s) detected. Open the app to review.';
          break;
        case DetectionPhase.cancelled:
          title = 'Detection cancelled';
          content = 'The video detection was cancelled.';
          break;
        case DetectionPhase.error:
          title = 'Detection failed';
          content = message ?? 'Something went wrong.';
          break;
        default:
          title = 'Video detection';
          content = 'Working...';
      }
      service.setForegroundNotificationInfo(title: title, content: content);
    }
  }

  Future<void> runJob(Map<dynamic, dynamic> request) async {
    if (busy) return;
    busy = true;

    final baseUrl = (request['baseUrl'] ?? '').toString();
    final videoPath = (request['videoPath'] ?? '').toString();
    final shift = (request['shift'] ?? '').toString();
    final videoName = (request['videoName'] ?? videoPath.split(Platform.pathSeparator).last).toString();

    final cancelToken = CancelToken();
    activeToken = cancelToken;

    String workingPath = videoPath;
    MediaInfo? compressed;

    try {
      // Clear the stored request now that we've picked it up.
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(VideoDetectionService._prefsRequestKey);
      } catch (_) {}

      if (baseUrl.isEmpty || videoPath.isEmpty || shift.isEmpty) {
        throw const ApiException('Missing video, server URL or shift.');
      }
      if (!File(videoPath).existsSync()) {
        throw const ApiException('Selected video is no longer available.');
      }

      // ---- 1) Compress (makes the upload dramatically faster) ----
      await emit(phase: DetectionPhase.compressing, compress: 0, shift: shift, videoName: videoName);

      final progressSub = VideoCompress.compressProgress$.subscribe((progress) {
        if (cancelToken.isCancelled) return;
        emit(
          phase: DetectionPhase.compressing,
          compress: progress.round().clamp(0, 100),
          shift: shift,
          videoName: videoName,
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
        compressed = null; // Fall back to original on any compression failure.
      } finally {
        progressSub.unsubscribe();
      }

      if (cancelToken.isCancelled) {
        await emit(phase: DetectionPhase.cancelled, message: 'Cancelled.', shift: shift, videoName: videoName);
        return;
      }

      final compressedPath = compressed?.path;
      if (compressedPath != null && File(compressedPath).existsSync()) {
        workingPath = compressedPath;
      }
      await emit(phase: DetectionPhase.compressing, compress: 100, shift: shift, videoName: videoName);

      // ---- 2) Upload + 3) server-side detection (with progress polling) ----
      final client = await ApiClient.create(baseUrl: baseUrl);

      final rows = await client.detectVideoData(
        videoFile: File(workingPath),
        shift: shift,
        cancelToken: cancelToken,
        onProgress: (uploadPercent, detectPercent, phase) {
          if (cancelToken.isCancelled) return;
          if (phase == 'uploading') {
            emit(
              phase: DetectionPhase.uploading,
              compress: 100,
              upload: uploadPercent,
              shift: shift,
              videoName: videoName,
            );
          } else {
            emit(
              phase: DetectionPhase.detecting,
              compress: 100,
              upload: 100,
              detect: detectPercent,
              shift: shift,
              videoName: videoName,
            );
          }
        },
      );

      if (cancelToken.isCancelled) {
        await emit(phase: DetectionPhase.cancelled, message: 'Cancelled.', shift: shift, videoName: videoName);
        return;
      }

      await emit(
        phase: DetectionPhase.completed,
        compress: 100,
        upload: 100,
        detect: 100,
        shift: shift,
        videoName: videoName,
        rows: rows,
      );
      await showResultNotification(
        'Detection complete',
        '${rows.length} row(s) detected. Open the app to review and submit.',
      );
    } on ApiException catch (e) {
      if (cancelToken.isCancelled) {
        await emit(phase: DetectionPhase.cancelled, message: 'Cancelled.', shift: shift, videoName: videoName);
      } else {
        await emit(phase: DetectionPhase.error, message: e.message, shift: shift, videoName: videoName);
        await showResultNotification('Detection failed', e.message);
      }
    } catch (e) {
      if (cancelToken.isCancelled) {
        await emit(phase: DetectionPhase.cancelled, message: 'Cancelled.', shift: shift, videoName: videoName);
      } else {
        await emit(phase: DetectionPhase.error, message: 'Failed to detect data from video.', shift: shift, videoName: videoName);
        await showResultNotification('Detection failed', 'Failed to detect data from video.');
      }
    } finally {
      // Clean up the compressed temp file (keep the user's original).
      try {
        final p = compressed?.path;
        if (p != null && p != videoPath && File(p).existsSync()) {
          await File(p).delete();
        }
      } catch (_) {}

      busy = false;
      activeToken = null;

      // Give the platform a moment to deliver the final notification/update,
      // then stop the foreground service so it no longer holds resources.
      await Future.delayed(const Duration(seconds: 2));
      service.stopSelf();
    }
  }

  service.on('startDetection').listen((event) {
    if (event == null) return;
    runJob(event);
  });

  service.on('cancel').listen((event) async {
    final token = activeToken;
    try {
      await VideoCompress.cancelCompression();
    } catch (_) {}
    if (token != null && !token.isCancelled) {
      token.cancel('cancelled');
    }
  });

  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  // Handle a request that may have been queued before our listeners attached.
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final raw = prefs.getString(VideoDetectionService._prefsRequestKey);
    if (raw != null && raw.trim().isNotEmpty) {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        runJob(decoded);
      }
    }
  } catch (_) {
    // Ignore.
  }
}
