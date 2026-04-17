// CleanIT — Request Service
//
// Handles all cleaning request operations: create, fetch, accept,
// start, complete, report-locked, and real-time subscriptions.

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';

class RequestService {
  RequestService._();
  static final RequestService instance = RequestService._();

  final _supabase = Supabase.instance.client;

  String get _functionsBase {
    final url = _supabase.rest.url;
    // Convert REST URL to Functions URL
    // e.g., https://xyz.supabase.co/rest/v1 → https://xyz.supabase.co/functions/v1
    return url.replaceAll('/rest/v1', '/functions/v1');
  }

  String? get _accessToken => _supabase.auth.currentSession?.accessToken;

  Map<String, String> get _authHeaders => {
        'Authorization': 'Bearer ${_accessToken ?? ''}',
        'Content-Type': 'application/json',
      };

  // ─────────────────────────────────────────────────────────
  //  Student Operations
  // ─────────────────────────────────────────────────────────

  /// Create a new cleaning request (student).
  /// Calls the create-request Edge Function which handles FCM broadcast.
  Future<Map<String, dynamic>> createRequest({
    required bool isSweeping,
    required bool isMopping,
    bool isUrgent = false,
    String? notes,
  }) async {
    final response = await http.post(
      Uri.parse('$_functionsBase/create-request'),
      headers: _authHeaders,
      body: jsonEncode({
        'is_sweeping': isSweeping,
        'is_mopping': isMopping,
        'is_urgent': isUrgent,
        'notes': notes?.trim(),
      }),
    );

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Fetch the student's request history (most recent first).
  Future<List<CleaningRequest>> fetchStudentRequests(String studentId) async {
    final response = await _supabase
        .from('requests')
        .select('''
          *,
          assignments (
            id,
            cleaner_id,
            assigned_at,
            started_at,
            completed_at,
            failure_reason,
            proof_image_url,
            cleaner:users!assignments_cleaner_id_fkey ( name )
          )
        ''')
        .eq('student_id', studentId)
        .order('created_at', ascending: false)
        .limit(20);

    return (response as List)
        .map((json) => CleaningRequest.fromJson(json))
        .toList();
  }

  /// Fetch the student's current active request (if any).
  Future<CleaningRequest?> fetchActiveStudentRequest(String studentId) async {
    final response = await _supabase
        .from('requests')
        .select('''
          *,
          assignments (
            id,
            cleaner_id,
            assigned_at,
            started_at,
            completed_at,
            cleaner:users!assignments_cleaner_id_fkey ( name )
          )
        ''')
        .eq('student_id', studentId)
        .inFilter('status', ['OPEN', 'ASSIGNED', 'IN_PROGRESS'])
        .order('created_at', ascending: false)
        .limit(1);

    if ((response as List).isEmpty) return null;
    return CleaningRequest.fromJson(response.first);
  }

  /// Submit feedback for a completed request.
  Future<void> submitFeedback({
    required String requestId,
    required String studentId,
    required int rating,
    String? comment,
  }) async {
    await _supabase.from('feedback').insert({
      'request_id': requestId,
      'student_id': studentId,
      'rating': rating,
      'comment': comment,
    });
  }

  // ─────────────────────────────────────────────────────────
  //  Cleaner Operations
  // ─────────────────────────────────────────────────────────

  /// Fetch all OPEN requests for the cleaner broadcast view.
  Future<List<CleaningRequest>> fetchOpenRequests() async {
    final response = await _supabase
        .from('requests')
        .select('''
          *,
          student:users!requests_student_id_fkey ( name, block, room_number )
        ''')
        .eq('status', 'OPEN')
        .order('is_urgent', ascending: false)
        .order('created_at', ascending: true);

    return (response as List)
        .map((json) => CleaningRequest.fromJson(json))
        .toList();
  }

  /// Fetch the cleaner's active/assigned jobs.
  Future<List<CleaningRequest>> fetchCleanerJobs(String cleanerId) async {
    // First get assignment IDs for this cleaner
    final assignments = await _supabase
        .from('assignments')
        .select('request_id')
        .eq('cleaner_id', cleanerId);

    if ((assignments as List).isEmpty) return [];

    final requestIds =
        assignments.map((a) => a['request_id'] as String).toList();

    final response = await _supabase
        .from('requests')
        .select('''
          *,
          student:users!requests_student_id_fkey ( name, block, room_number ),
          assignments (
            id,
            cleaner_id,
            assigned_at,
            started_at,
            completed_at,
            failure_reason,
            cleaner:users!assignments_cleaner_id_fkey ( name )
          )
        ''')
        .inFilter('id', requestIds)
        .inFilter('status', ['ASSIGNED', 'IN_PROGRESS'])
        .order('created_at', ascending: false);

    return (response as List)
        .map((json) => CleaningRequest.fromJson(json))
        .toList();
  }

  /// Accept a request (calls the concurrency-safe Edge Function).
  Future<Map<String, dynamic>> acceptRequest(String requestId) async {
    final response = await http.post(
      Uri.parse('$_functionsBase/accept-request'),
      headers: _authHeaders,
      body: jsonEncode({'request_id': requestId}),
    );

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Start a job (ASSIGNED → IN_PROGRESS).
  Future<Map<String, dynamic>> startJob(String requestId) async {
    final userId = _supabase.auth.currentUser?.id;
    // Get internal user ID
    final user = await _supabase
        .from('users')
        .select('id')
        .eq('auth_id', userId!)
        .single();

    final result = await _supabase.rpc('start_job', params: {
      'p_request_id': requestId,
      'p_cleaner_id': user['id'],
    });

    return result as Map<String, dynamic>;
  }

  /// Verify QR code (calls the verify-qr Edge Function).
  Future<Map<String, dynamic>> verifyQR({
    required String requestId,
    required String qrPayload,
  }) async {
    final response = await http.post(
      Uri.parse('$_functionsBase/verify-qr'),
      headers: _authHeaders,
      body: jsonEncode({
        'request_id': requestId,
        'qr_payload': qrPayload,
      }),
    );

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Report room locked (calls the report-locked Edge Function with photo).
  Future<Map<String, dynamic>> reportRoomLocked({
    required String requestId,
    required String photoPath,
    String failureReason = 'room_locked',
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$_functionsBase/report-locked'),
    );
    request.headers['Authorization'] = 'Bearer ${_accessToken ?? ''}';
    request.fields['request_id'] = requestId;
    request.fields['failure_reason'] = failureReason;
    request.files.add(await http.MultipartFile.fromPath('photo', photoPath));

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  // ─────────────────────────────────────────────────────────
  //  Real-time Subscriptions
  // ─────────────────────────────────────────────────────────

  /// Subscribe to new OPEN requests (for cleaner broadcast).
  RealtimeChannel subscribeToNewRequests(
      void Function(CleaningRequest) onNewRequest) {
    return _supabase
        .channel('open-requests')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'requests',
          callback: (payload) {
            try {
              final request = CleaningRequest.fromJson(payload.newRecord);
              onNewRequest(request);
            } catch (e) {
              debugPrint('Error parsing new request: $e');
            }
          },
        )
        .subscribe();
  }

  /// Subscribe to status changes on a specific request.
  RealtimeChannel subscribeToRequestStatus(
    String requestId,
    void Function(RequestStatus newStatus) onStatusChange,
  ) {
    return _supabase
        .channel('request-$requestId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'requests',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: requestId,
          ),
          callback: (payload) {
            final statusStr = payload.newRecord['status'] as String?;
            if (statusStr != null) {
              onStatusChange(RequestStatus.fromString(statusStr));
            }
          },
        )
        .subscribe();
  }
}
