import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';

class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  final _supabase = Supabase.instance.client;

  /// Current Supabase auth user
  User? get currentAuthUser => _supabase.auth.currentUser;

  /// Stream of auth state changes
  Stream<AuthState> get authStateChanges => _supabase.auth.onAuthStateChange;

  /// Whether a user is currently signed in
  bool get isSignedIn => currentAuthUser != null;

  // Cached app user profile
  AppUser? _cachedProfile;
  AppUser? get currentProfile => _cachedProfile;

  /// Sign up with email & password, then create a user profile
  Future<AppUser> signUp({
    required String email,
    required String password,
    required String name,
    required UserRole role,
    String? block,
    String? roomNumber,
  }) async {
    // 1. Create auth account
    final authResponse = await _supabase.auth.signUp(
      email: email,
      password: password,
    );

    if (authResponse.user == null) {
      throw Exception('Sign up failed. Please try again.');
    }

    // 2. Create user profile in our users table
    final profileData = {
      'auth_id': authResponse.user!.id,
      'email': email,
      'name': name,
      'role': role.name,
      'block': block,
      'room_number': roomNumber,
      'is_on_duty': role == UserRole.cleaner,
    };

    final response = await _supabase
        .from('users')
        .insert(profileData)
        .select()
        .single();

    _cachedProfile = AppUser.fromJson(response);
    return _cachedProfile!;
  }

  /// Sign in with email & password
  Future<AppUser> signIn({
    required String email,
    required String password,
  }) async {
    await _supabase.auth.signInWithPassword(
      email: email,
      password: password,
    );

    return await fetchProfile();
  }

  /// Fetch the current user's profile from the users table
  Future<AppUser> fetchProfile() async {
    final authUser = currentAuthUser;
    if (authUser == null) throw Exception('Not authenticated');

    final response = await _supabase
        .from('users')
        .select()
        .eq('auth_id', authUser.id)
        .single();

    _cachedProfile = AppUser.fromJson(response);
    return _cachedProfile!;
  }

  /// Update FCM token in the user profile
  Future<void> updateFcmToken(String token) async {
    if (_cachedProfile == null) return;

    await _supabase
        .from('users')
        .update({'fcm_token': token})
        .eq('id', _cachedProfile!.id);
  }

  /// Toggle cleaner on-duty status
  Future<void> toggleOnDuty(bool isOnDuty) async {
    if (_cachedProfile == null) return;

    await _supabase
        .from('users')
        .update({'is_on_duty': isOnDuty})
        .eq('id', _cachedProfile!.id);

    _cachedProfile = AppUser(
      id: _cachedProfile!.id,
      authId: _cachedProfile!.authId,
      email: _cachedProfile!.email,
      name: _cachedProfile!.name,
      role: _cachedProfile!.role,
      block: _cachedProfile!.block,
      roomNumber: _cachedProfile!.roomNumber,
      fcmToken: _cachedProfile!.fcmToken,
      isOnDuty: isOnDuty,
    );
  }

  /// Sign out
  Future<void> signOut() async {
    _cachedProfile = null;
    await _supabase.auth.signOut();
  }
}
