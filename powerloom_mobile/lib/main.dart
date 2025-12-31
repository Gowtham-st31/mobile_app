import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:dio/dio.dart';

import 'src/app_controller.dart';
import 'src/screens/home_shell.dart';
import 'src/screens/login_screen.dart';
import 'src/screens/update_required_screen.dart';
import 'src/services/app_update_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Default base URL:
  // - Release builds: Render deployment (HTTPS)
  // - Debug/dev builds: local server (HTTP)
  // Override at build time with: --dart-define=POWERLOOM_API_BASE_URL=<url>
  const envBaseUrl = String.fromEnvironment('POWERLOOM_API_BASE_URL', defaultValue: '');
  final defaultBaseUrl = envBaseUrl.isNotEmpty
      ? envBaseUrl
      : (kReleaseMode ? 'https://vinayagatexapp.onrender.com' : 'http://127.0.0.1:8080');

  final controller = AppController(defaultBaseUrl: defaultBaseUrl);
  runApp(PowerloomApp(controller: controller));
}

class PowerloomApp extends StatefulWidget {
  final AppController controller;

  const PowerloomApp({super.key, required this.controller});

  @override
  State<PowerloomApp> createState() => _PowerloomAppState();
}

class _PowerloomAppState extends State<PowerloomApp> {
  bool _startupComplete = false;
  AppVersionInfo? _updateRequired;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    // 1) Run existing bootstrap (baseUrl restore, cookies/session restore, etc)
    await widget.controller.init();

    // 2) Forced update gate (silent failure on any error)
    await _checkForForcedUpdate();

    if (!mounted) return;
    setState(() {
      _startupComplete = true;
    });
  }

  Future<void> _checkForForcedUpdate() async {
    try {
      final service = AppUpdateService(
        dio: Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 45),
            receiveTimeout: const Duration(seconds: 60),
            sendTimeout: const Duration(seconds: 60),
            headers: const {
              'Accept': 'application/json',
            },
          ),
        ),
      );
      final latest = await service.fetchLatestAppVersion(baseUrl: widget.controller.baseUrl);
      if (latest == null) return;

      final currentCode = await service.getCurrentAndroidVersionCode();
      if (latest.versionCode > currentCode) {
        if (!mounted) return;
        setState(() {
          _updateRequired = latest;
        });
      }
    } catch (_) {
      // Silent failure: treat as no forced update.
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        const spotifyGreen = Color(0xFF1DB954);
        const black = Colors.black;
        const surface = Color(0xFF121212);
        const surface2 = Color(0xFF1E1E1E);

        final scheme = ColorScheme.fromSeed(
          seedColor: spotifyGreen,
          brightness: Brightness.dark,
        ).copyWith(
          primary: spotifyGreen,
          onPrimary: black,
          secondary: spotifyGreen,
          onSecondary: black,
          surface: surface,
          onSurface: Colors.white,
          surfaceContainerHighest: surface2,
        );

        final theme = ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          colorScheme: scheme,
          scaffoldBackgroundColor: black,
          textTheme: ThemeData.dark().textTheme.apply(bodyColor: Colors.white, displayColor: Colors.white),
          appBarTheme: const AppBarTheme(
            backgroundColor: black,
            foregroundColor: Colors.white,
          ),
          iconTheme: const IconThemeData(color: Colors.white),
          cardTheme: const CardTheme(
            color: surface,
            surfaceTintColor: surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(16)),
            ),
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              backgroundColor: spotifyGreen,
              foregroundColor: black,
              textStyle: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          inputDecorationTheme: const InputDecorationTheme(
            filled: true,
            fillColor: surface,
            labelStyle: TextStyle(color: Colors.white70),
            floatingLabelStyle: TextStyle(color: spotifyGreen),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Colors.white24),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: spotifyGreen, width: 2),
            ),
            border: OutlineInputBorder(),
          ),
          navigationBarTheme: NavigationBarThemeData(
            height: 72,
            backgroundColor: black,
            indicatorColor: spotifyGreen.withValues(alpha: 0.18),
            labelTextStyle: WidgetStateProperty.resolveWith(
              (states) => TextStyle(
                color: states.contains(WidgetState.selected) ? spotifyGreen : Colors.white70,
                fontWeight: FontWeight.w600,
              ),
            ),
            iconTheme: WidgetStateProperty.resolveWith(
              (states) => IconThemeData(
                color: states.contains(WidgetState.selected) ? spotifyGreen : Colors.white70,
              ),
            ),
          ),
          snackBarTheme: const SnackBarThemeData(
            backgroundColor: surface2,
            contentTextStyle: TextStyle(color: Colors.white),
          ),
        );

        final session = widget.controller.session;

        final update = _updateRequired;
        final isUpdateRequired = update != null;

        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Vinayaga Tex',
          theme: theme,
          home: isUpdateRequired
              ? UpdateRequiredScreen(
                  latestVersion: update.latestVersion,
                  latestVersionCode: update.versionCode,
                  apkUrl: update.apkUrl,
                )
              : (!_startupComplete || widget.controller.bootstrapping)
                  ? const _Splash()
                  : (session == null
                      ? LoginScreen(controller: widget.controller)
                      : HomeShell(controller: widget.controller, session: session)),
        );
      },
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Image(
            image: AssetImage('assets/logo.png'),
            width: 160,
            height: 160,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}
