// CleanIT — Centralized API Client
//
// All HTTP calls to the Express/MongoDB backend go through this client.
// Handles JWT token injection, error parsing, and response normalization.

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';

class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  static const _tokenKey = 'cleanit_jwt_token';

  // Use secure storage on mobile, shared prefs on web
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  /// Save JWT token
  Future<void> saveToken(String token) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tokenKey, token);
    } else {
      await _secureStorage.write(key: _tokenKey, value: token);
    }
  }

  /// Get stored JWT token
  Future<String?> getToken() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_tokenKey);
    } else {
      return await _secureStorage.read(key: _tokenKey);
    }
  }

  /// Delete JWT token (logout)
  Future<void> deleteToken() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_tokenKey);
    } else {
      await _secureStorage.delete(key: _tokenKey);
    }
  }

  /// Check if a token is stored
  Future<bool> hasToken() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  /// Build headers with JWT auth
  Future<Map<String, String>> _headers() async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    final token = await getToken();
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  /// GET request
  Future<Map<String, dynamic>> get(String path) async {
    final url = Uri.parse('${AppConfig.apiBaseUrl}$path');
    final response = await http.get(url, headers: await _headers());
    return _handleResponse(response);
  }

  /// POST request
  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final url = Uri.parse('${AppConfig.apiBaseUrl}$path');
    final response = await http.post(
      url,
      headers: await _headers(),
      body: body != null ? jsonEncode(body) : null,
    );
    return _handleResponse(response);
  }

  /// PUT request
  Future<Map<String, dynamic>> put(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final url = Uri.parse('${AppConfig.apiBaseUrl}$path');
    final response = await http.put(
      url,
      headers: await _headers(),
      body: body != null ? jsonEncode(body) : null,
    );
    return _handleResponse(response);
  }

  /// Parse and handle HTTP response
  Map<String, dynamic> _handleResponse(http.Response response) {
    try {
      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return data;
      }

      // Extract error message
      final message = data['message'] ?? data['error'] ?? 'Request failed';
      throw ApiException(
        statusCode: response.statusCode,
        message: message.toString(),
        code: data['code']?.toString(),
      );
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(
        statusCode: response.statusCode,
        message: 'Failed to parse server response',
      );
    }
  }
}

/// Custom exception for API errors
class ApiException implements Exception {
  final int statusCode;
  final String message;
  final String? code;

  ApiException({
    required this.statusCode,
    required this.message,
    this.code,
  });

  @override
  String toString() => message;
}
