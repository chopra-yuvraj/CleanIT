/// CleanIT — Main Entry Point
///
/// Initializes Firebase (mobile only), Supabase, and FCM.
/// Routes to auth screen or the appropriate role-based dashboard.

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'config/app_config.dart';
import 'config/app_theme.dart';
import 'models/models.dart';
import 'services/services.dart';
import 'screens/auth_screen.dart';
import 'screens/student_home_screen.dart';
import 'screens/cleaner_dashboard_screen.dart';

/// Top-level background FCM handler (must be outside any class)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint('Background FCM: ${message.notification?.title}');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── Initialize Firebase (mobile only — web has no firebase_options configured) ──
  if (!kIsWeb) {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Request notification permissions
    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      criticalAlert: true,
    );

    // Get and store FCM token
    final fcmToken = await messaging.getToken();
    debugPrint('FCM Token: $fcmToken');

    if (fcmToken != null) {
      try {
        final auth = AuthService.instance;
        if (auth.isSignedIn) {
          await auth.updateFcmToken(fcmToken);
        }
      } catch (_) {}
    }

    // Listen for token refresh
    messaging.onTokenRefresh.listen((newToken) async {
      try {
        await AuthService.instance.updateFcmToken(newToken);
      } catch (_) {}
    });
  }

  // ── Initialize Supabase (works on all platforms) ──
  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    anonKey: AppConfig.supabaseAnonKey,
  );

  runApp(const CleanITApp());
}

class CleanITApp extends StatelessWidget {
  const CleanITApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CleanIT',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const _AuthGate(),
    );
  }
}

/// Checks if the user is already signed in and routes accordingly.
class _AuthGate extends StatefulWidget {
  const _AuthGate();

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  bool _isLoading = true;
  Widget? _destination;

  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    try {
      final auth = AuthService.instance;

      if (auth.isSignedIn) {
        final profile = await auth.fetchProfile();

        // Save FCM token (mobile only)
        if (!kIsWeb) {
          final token = await FirebaseMessaging.instance.getToken();
          if (token != null) await auth.updateFcmToken(token);
        }

        _destination = profile.role == UserRole.student
            ? const StudentHomeScreen()
            : const CleanerDashboardScreen();
      } else {
        _destination = const AuthScreen();
      }
    } catch (e) {
      debugPrint('Auth check error: $e');
      _destination = const AuthScreen();
    }

    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppTheme.crust,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.blue.withOpacity(0.1),
                ),
                child: const Icon(
                  Icons.cleaning_services_rounded,
                  color: AppTheme.blue,
                  size: 36,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'CleanIT',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
              ),
              const SizedBox(height: 24),
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: AppTheme.blue,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return _destination!;
  }
}
