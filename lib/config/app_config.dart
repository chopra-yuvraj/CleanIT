// CleanIT — App Configuration
//
// Centralized config for Supabase, QR signing, and feature flags.
// Values can be overridden at build time via --dart-define.
//
// NOTE: The Supabase anon key is a PUBLIC key — it is safe to embed
// in client code because all data access is protected by Row Level
// Security (RLS) policies defined in the database.

class AppConfig {
  AppConfig._();

  // ── Supabase ──
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://qgpzwvigrkwpjxegwlha.supabase.co',
  );

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFncHp3dmlncmt3cGp4ZWd3bGhhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzY0MDk0MTYsImV4cCI6MjA5MTk4NTQxNn0.2YGbdLK3Aql4nm3Q13m2vbOW4vkd6m0xRHbw_DhgIJ8',
  );

  // ── QR Signing ──
  /// Must match QR_SIGNING_SECRET set in Supabase Edge Function secrets.
  static const String qrSigningSecret = String.fromEnvironment(
    'QR_SIGNING_SECRET',
    defaultValue: 'VIT_RoOmClEaNiNg_Application_QR_Key',
  );

  /// QR codes expire after this duration.
  static const Duration qrExpiry = Duration(minutes: 3);

  // ── Edge Functions base path ──
  /// Constructs the correct Supabase Edge Functions URL.
  static String get functionsUrl =>
      '$supabaseUrl/functions/v1';
}
