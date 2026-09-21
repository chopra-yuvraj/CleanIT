// CleanIT — App Configuration
//
// Centralized config for API backend, QR signing, and feature flags.
// Values can be overridden at build time via --dart-define.

class AppConfig {
  AppConfig._();

  // ── Backend API ──
  // Points to the Node.js/Express + MongoDB backend server.
  // For local development, use http://10.0.2.2:3000 (Android emulator)
  // or http://localhost:3000 (web / iOS simulator).
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:3000/api',
  );

  // ── QR Signing ──
  /// Must match QR_SIGNING_SECRET set in the backend .env.
  static const String qrSigningSecret = String.fromEnvironment(
    'QR_SIGNING_SECRET',
    defaultValue: 'cleanit-qr-signing-secret-74839201',
  );

  /// QR codes expire after this duration.
  static const Duration qrExpiry = Duration(minutes: 3);
}
