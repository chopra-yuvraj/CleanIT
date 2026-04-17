// CleanIT — App Configuration
//
// Centralized config for Supabase, QR signing, and feature flags.
// Values are injected at build time via --dart-define.

class AppConfig {
  AppConfig._();

  // ── Supabase ──
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://YOUR_PROJECT_REF.supabase.co',
  );

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );

  // ── QR Signing ──
  /// Must match QR_SIGNING_SECRET set in Supabase Edge Function secrets.
  static const String qrSigningSecret = String.fromEnvironment(
    'QR_SIGNING_SECRET',
    defaultValue: 'dev-secret-change-me-in-production',
  );

  /// QR codes expire after this duration.
  static const Duration qrExpiry = Duration(minutes: 3);

  // ── Edge Functions base path ──
  static String get functionsUrl =>
      supabaseUrl.replaceAll('.supabase.co', '.functions.supabase.co');
}
