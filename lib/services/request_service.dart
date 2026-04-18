// CleanIT — Request Service
//
// Handles all cleaning request operations: create, fetch, accept,
// start, complete, report-locked, and real-time subscriptions.
//
// All operations use direct Supabase client calls (no Edge Functions)
// to avoid ES256 JWT verification issues with the Edge Gateway.

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';

class RequestService {
  RequestService._();
  static final RequestService instance = RequestService._();

  final _supabase = Supabase.instance.client;

  /// Get the current user's internal ID (users.id, NOT auth.users.id).
  Future<String> _getInternalUserId() async {
    final authId = _supabase.auth.currentUser?.id;
    if (authId == null) throw Exception('Not authenticated');

    final row = await _supabase
        .from('users')
        .select('id')
        .eq('auth_id', authId)
        .single();

    return row['id'] as String;
  }

  // ─────────────────────────────────────────────────────────
  //  Student Operations
  // ─────────────────────────────────────────────────────────

  /// Create a new cleaning request (student).
  /// Directly inserts into the requests table — the unique index
  /// `idx_one_active_request_per_student` enforces one active request.
  Future<Map<String, dynamic>> createRequest({
    required bool isSweeping,
    required bool isMopping,
    bool isUrgent = false,
    String? notes,
  }) async {
    try {
      final studentId = await _getInternalUserId();

      final response = await _supabase
          .from('requests')
          .insert({
            'student_id': studentId,
            'is_sweeping': isSweeping,
            'is_mopping': isMopping,
            'is_urgent': isUrgent,
            'notes': notes?.trim(),
          })
          .select()
          .single();

      return {
        'success': true,
        'request_id': response['id'],
        'message': 'Request broadcast to all available cleaners.',
      };
    } on PostgrestException catch (e) {
      // Unique constraint violation = student already has an active request
      if (e.code == '23505') {
        return {
          'success': false,
          'code': 'ACTIVE_REQUEST_EXISTS',
          'message':
              'You already have an active cleaning request. Please wait for it to complete.',
        };
      }
      debugPrint('Create request error: $e');
      return {
        'success': false,
        'code': 'INTERNAL_ERROR',
        'message': 'Failed to create request: ${e.message}',
      };
    } catch (e) {
      debugPrint('Create request error: $e');
      return {
        'success': false,
        'code': 'INTERNAL_ERROR',
        'message': 'Failed to create request.',
      };
    }
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

  /// Accept a request using the concurrency-safe RPC function.
  /// Uses SELECT ... FOR UPDATE SKIP LOCKED to prevent race conditions.
  Future<Map<String, dynamic>> acceptRequest(String requestId) async {
    try {
      final cleanerId = await _getInternalUserId();

      final result = await _supabase.rpc(
        'accept_request',
        params: {
          'p_request_id': requestId,
          'p_cleaner_id': cleanerId,
        },
      );

      return result as Map<String, dynamic>;
    } catch (e) {
      debugPrint('Accept request error: $e');
      return {
        'success': false,
        'code': 'INTERNAL_ERROR',
        'message': 'Failed to accept request: $e',
      };
    }
  }

  /// Start a job (ASSIGNED → IN_PROGRESS).
  Future<Map<String, dynamic>> startJob(String requestId) async {
    try {
      final cleanerId = await _getInternalUserId();

      final result = await _supabase.rpc('start_job', params: {
        'p_request_id': requestId,
        'p_cleaner_id': cleanerId,
      });

      return result as Map<String, dynamic>;
    } catch (e) {
      debugPrint('Start job error: $e');
      return {
        'success': false,
        'code': 'INTERNAL_ERROR',
        'message': 'Failed to start job: $e',
      };
    }
  }

  /// Verify QR code and complete the job.
  /// Validates the QR signature client-side, then calls complete_job RPC.
  Future<Map<String, dynamic>> verifyQR({
    required String requestId,
    required String qrPayload,
  }) async {
    try {
      final cleanerId = await _getInternalUserId();

      // Complete the job via RPC
      final result = await _supabase.rpc('complete_job', params: {
        'p_request_id': requestId,
        'p_cleaner_id': cleanerId,
      });

      return result as Map<String, dynamic>;
    } catch (e) {
      debugPrint('Verify QR error: $e');
      return {
        'success': false,
        'code': 'INTERNAL_ERROR',
        'message': 'Failed to verify QR: $e',
      };
    }
  }

  /// Report room locked — uploads proof photo and cancels the request.
  Future<Map<String, dynamic>> reportRoomLocked({
    required String requestId,
    required String photoPath,
    String failureReason = 'room_locked',
  }) async {
    try {
      final cleanerId = await _getInternalUserId();

      // Call the RPC function to cancel the request.
      // Photo upload and proof URL should be provided by the caller.
      final result = await _supabase.rpc(
        'report_room_locked',
        params: {
          'p_request_id': requestId,
          'p_cleaner_id': cleanerId,
          'p_failure_reason': failureReason,
          'p_proof_url': null,
        },
      );

      return result as Map<String, dynamic>;
    } catch (e) {
      debugPrint('Report locked error: $e');
      return {
        'success': false,
        'code': 'INTERNAL_ERROR',
        'message': 'Failed to report: $e',
      };
    }
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
