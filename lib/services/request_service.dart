// CleanIT — Request Service
//
// Handles all cleaning request operations: create, fetch, accept,
// start, complete, report-locked, and feedback.
//
// All operations use HTTP calls to the Express/MongoDB backend API.

import 'package:flutter/foundation.dart';
import '../models/models.dart';
import 'api_client.dart';

class RequestService {
  RequestService._();
  static final RequestService instance = RequestService._();

  final _api = ApiClient.instance;

  // ─────────────────────────────────────────────────────────
  //  Student Operations
  // ─────────────────────────────────────────────────────────

  /// Create a new cleaning request (student).
  Future<Map<String, dynamic>> createRequest({
    required bool isSweeping,
    required bool isMopping,
    bool isUrgent = false,
    String? notes,
  }) async {
    try {
      final response = await _api.post('/requests', body: {
        'isSweeping': isSweeping,
        'isMopping': isMopping,
        'isUrgent': isUrgent,
        'notes': notes?.trim(),
      });

      return {
        'success': response['success'] ?? true,
        'request_id': response['request_id'],
        'message': response['message'] ?? 'Request broadcast to all available cleaners.',
      };
    } on ApiException catch (e) {
      return {
        'success': false,
        'code': e.code ?? 'INTERNAL_ERROR',
        'message': e.message,
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
    try {
      final response = await _api.get('/requests/my');
      final requests = response['requests'] as List<dynamic>? ?? [];
      return requests
          .map((json) => CleaningRequest.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('Fetch student requests error: $e');
      return [];
    }
  }

  /// Fetch the student's current active request (if any).
  Future<CleaningRequest?> fetchActiveStudentRequest(String studentId) async {
    try {
      final response = await _api.get('/requests/active');
      final requestData = response['request'];
      if (requestData == null) return null;
      return CleaningRequest.fromJson(requestData as Map<String, dynamic>);
    } catch (e) {
      debugPrint('Fetch active request error: $e');
      return null;
    }
  }

  /// Student cancels their own OPEN request.
  ///
  /// Uses a single atomic [findOneAndUpdate] on the backend filtered on
  /// `status: "OPEN"`, so if a cleaner accepts in the same instant this
  /// call is in-flight, the cancellation safely fails with [CANNOT_CANCEL]
  /// instead of corrupting state.
  Future<Map<String, dynamic>> cancelRequest(String requestId) async {
    try {
      final response = await _api.post('/requests/$requestId/cancel');
      return {
        'success': response['success'] ?? true,
        'message': response['message'] ?? 'Request cancelled.',
      };
    } on ApiException catch (e) {
      return {
        'success': false,
        'code': e.code ?? 'CANNOT_CANCEL',
        'message': e.message,
      };
    } catch (e) {
      debugPrint('Cancel request error: $e');
      return {
        'success': false,
        'code': 'INTERNAL_ERROR',
        'message': 'Failed to cancel request.',
      };
    }
  }

  Future<void> submitFeedback({
    required String requestId,
    required String studentId,
    required int rating,
    String? comment,
  }) async {
    await _api.post('/feedback', body: {
      'requestId': requestId,
      'rating': rating,
      'comment': comment,
    });
  }

  // ─────────────────────────────────────────────────────────
  //  Cleaner Operations
  // ─────────────────────────────────────────────────────────

  /// Fetch all OPEN requests for the cleaner broadcast view.
  Future<List<CleaningRequest>> fetchOpenRequests() async {
    try {
      final response = await _api.get('/requests/open');
      final requests = response['requests'] as List<dynamic>? ?? [];
      return requests
          .map((json) => CleaningRequest.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('Fetch open requests error: $e');
      return [];
    }
  }

  /// Fetch the cleaner's active/assigned jobs.
  Future<List<CleaningRequest>> fetchCleanerJobs(String cleanerId) async {
    try {
      final response = await _api.get('/requests/cleaner-jobs');
      final requests = response['requests'] as List<dynamic>? ?? [];
      return requests
          .map((json) => CleaningRequest.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('Fetch cleaner jobs error: $e');
      return [];
    }
  }

  /// Accept a request (cleaner).
  Future<Map<String, dynamic>> acceptRequest(String requestId) async {
    try {
      final response = await _api.post('/requests/$requestId/accept');
      return response;
    } on ApiException catch (e) {
      return {
        'success': false,
        'code': e.code ?? 'INTERNAL_ERROR',
        'message': e.message,
      };
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
      final response = await _api.post('/requests/$requestId/start');
      return response;
    } on ApiException catch (e) {
      return {
        'success': false,
        'code': e.code ?? 'INTERNAL_ERROR',
        'message': e.message,
      };
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
  Future<Map<String, dynamic>> verifyQR({
    required String requestId,
    required String qrPayload,
  }) async {
    try {
      final response = await _api.post('/requests/$requestId/complete');
      return response;
    } on ApiException catch (e) {
      return {
        'success': false,
        'code': e.code ?? 'INTERNAL_ERROR',
        'message': e.message,
      };
    } catch (e) {
      debugPrint('Verify QR error: $e');
      return {
        'success': false,
        'code': 'INTERNAL_ERROR',
        'message': 'Failed to verify QR: $e',
      };
    }
  }

  /// Report room locked — cancels the request.
  Future<Map<String, dynamic>> reportRoomLocked({
    required String requestId,
    required String photoPath,
    String failureReason = 'room_locked',
  }) async {
    try {
      final response = await _api.post('/requests/$requestId/report-locked', body: {
        'failureReason': failureReason,
      });
      return response;
    } on ApiException catch (e) {
      return {
        'success': false,
        'code': e.code ?? 'INTERNAL_ERROR',
        'message': e.message,
      };
    } catch (e) {
      debugPrint('Report locked error: $e');
      return {
        'success': false,
        'code': 'INTERNAL_ERROR',
        'message': 'Failed to report: $e',
      };
    }
  }
}
