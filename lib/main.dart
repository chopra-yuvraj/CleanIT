// CleanIT — Main Entry Point
//
// Initializes Firebase (mobile only) and the API client.
// Routes to auth screen or the appropriate role-based dashboard.

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'config/app_theme.dart';
import 'config/theme_notifier.dart';
import 'models/models.dart';
import 'services/services.dart';
import 'screens/auth_screen.dart';
import 'screens/student_home_screen.dart';
import 'screens/cleaner_dashboard_screen.dart';
import 'screens/admin_dashboard_screen.dart';

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

    // ── Create Android notification channels ──
    await _createAndroidNotificationChannels();

    // Get and store FCM token
    final fcmToken = await messaging.getToken();
    debugPrint('FCM Token: $fcmToken');

    if (fcmToken != null) {
      try {
        final auth = AuthService.instance;
        final isSignedIn = await auth.checkSignedIn();
        if (isSignedIn) {
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

  runApp(const CleanITApp());
}

/// Creates the required notification channels on Android.
Future<void> _createAndroidNotificationChannels() async {
  try {
    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );
  } catch (e) {
    debugPrint('Notification setup skipped: $e');
  }
}

class CleanITApp extends StatelessWidget {
  const CleanITApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, mode, _) {
        return MaterialApp(
          title: 'CleanIT',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: mode,
          home: const _AuthGate(),
        );
      },
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
      final isSignedIn = await auth.checkSignedIn();

      if (isSignedIn) {
        final profile = await auth.fetchProfile();

        // Save FCM token (mobile only)
        if (!kIsWeb) {
          final token = await FirebaseMessaging.instance.getToken();
          if (token != null) await auth.updateFcmToken(token);
        }

        if (profile.role == UserRole.admin) {
          _destination = const AdminDashboardScreen();
        } else if (profile.role == UserRole.student) {
          _destination = const StudentHomeScreen();
        } else {
          _destination = const CleanerDashboardScreen();
        }
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
      final primary = Theme.of(context).colorScheme.primary;
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: primary.withValues(alpha: 0.1),
                ),
                child: Icon(
                  Icons.cleaning_services_rounded,
                  color: primary,
                  size: 36,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'CleanIT',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: primary,
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
