// CleanIT — Auth Service
//
// Handles authentication via JWT tokens against the Express/MongoDB API.

import 'package:flutter/foundation.dart';
import '../models/models.dart';
import 'api_client.dart';

class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  final _api = ApiClient.instance;

  // Cached app user profile
  AppUser? _cachedProfile;
  AppUser? get currentProfile => _cachedProfile;

  /// Whether a user is currently signed in (has a stored token)
  Future<bool> checkSignedIn() async {
    return await _api.hasToken();
  }

  /// Synchronous check using cached state (call checkSignedIn first)
  bool get isSignedIn => _cachedProfile != null;

  /// Sign up with email & password, then return user profile
  Future<AppUser?> signUp({
    required String email,
    required String password,
    required String name,
    required UserRole role,
    String? block,
    String? roomNumber,
  }) async {
    final response = await _api.post('/auth/register', body: {
      'email': email,
      'password': password,
      'name': name,
      'role': role.name,
      'block': block,
      'roomNumber': roomNumber,
    });

    if (response['success'] == true) {
      // Save JWT token
      await _api.saveToken(response['token'] as String);

      // Cache profile
      _cachedProfile = AppUser.fromJson(response['user'] as Map<String, dynamic>);
      return _cachedProfile;
    }

    throw Exception(response['message'] ?? 'Sign up failed');
  }

  /// Sign in with email & password
  Future<AppUser> signIn({
    required String email,
    required String password,
  }) async {
    final response = await _api.post('/auth/login', body: {
      'email': email,
      'password': password,
    });

    if (response['success'] == true) {
      // Save JWT token
      await _api.saveToken(response['token'] as String);

      // Cache profile
      _cachedProfile = AppUser.fromJson(response['user'] as Map<String, dynamic>);
      return _cachedProfile!;
    }

    throw Exception(response['message'] ?? 'Sign in failed');
  }

  /// Fetch the current user's profile from the API
  Future<AppUser> fetchProfile() async {
    final response = await _api.get('/auth/profile');

    if (response['success'] == true) {
      _cachedProfile = AppUser.fromJson(response['user'] as Map<String, dynamic>);
      return _cachedProfile!;
    }

    throw Exception('Failed to fetch profile');
  }

  /// Update FCM token in the user profile
  Future<void> updateFcmToken(String token) async {
    try {
      await _api.put('/auth/fcm-token', body: {'fcmToken': token});
    } catch (e) {
      debugPrint('Failed to update FCM token: $e');
    }
  }

  /// Toggle cleaner on-duty status
  Future<void> toggleOnDuty(bool isOnDuty) async {
    final response = await _api.put('/auth/toggle-duty', body: {
      'isOnDuty': isOnDuty,
    });

    if (response['success'] == true && response['user'] != null) {
      _cachedProfile = AppUser.fromJson(response['user'] as Map<String, dynamic>);
    }
  }

  /// Sign out
  Future<void> signOut() async {
    _cachedProfile = null;
    await _api.deleteToken();
  }
}
