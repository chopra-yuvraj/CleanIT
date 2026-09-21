// CleanIT — Analytics Service
//
// Calls the analytics API endpoints for the admin dashboard.
// Demonstrates aggregation pipeline results from MongoDB.

import 'api_client.dart';
import '../models/analytics_model.dart';

class AnalyticsService {
  AnalyticsService._();
  static final AnalyticsService instance = AnalyticsService._();

  final _api = ApiClient.instance;

  /// Fetch overview statistics (aggregation pipeline result)
  Future<AnalyticsOverview> fetchOverview() async {
    final response = await _api.get('/analytics/overview');
    return AnalyticsOverview.fromJson(
      response['overview'] as Map<String, dynamic>,
    );
  }

  /// Fetch requests grouped by hostel block
  Future<List<BlockStat>> fetchByBlock() async {
    final response = await _api.get('/analytics/by-block');
    final stats = response['blockStats'] as List<dynamic>? ?? [];
    return stats
        .map((json) => BlockStat.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Fetch cleaner leaderboard
  Future<List<LeaderboardEntry>> fetchLeaderboard() async {
    final response = await _api.get('/analytics/cleaner-leaderboard');
    final entries = response['leaderboard'] as List<dynamic>? ?? [];
    return entries
        .map((json) => LeaderboardEntry.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Fetch peak hours distribution
  Future<List<HourlyStat>> fetchPeakHours() async {
    final response = await _api.get('/analytics/peak-hours');
    final stats = response['hourlyStats'] as List<dynamic>? ?? [];
    return stats
        .map((json) => HourlyStat.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Fetch status distribution
  Future<List<StatusStat>> fetchStatusDistribution() async {
    final response = await _api.get('/analytics/status-distribution');
    final dist = response['distribution'] as List<dynamic>? ?? [];
    return dist
        .map((json) => StatusStat.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Fetch daily trends (last 30 days)
  Future<List<TrendPoint>> fetchTrends() async {
    final response = await _api.get('/analytics/trends');
    final trends = response['trends'] as List<dynamic>? ?? [];
    return trends
        .map((json) => TrendPoint.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Fetch audit logs
  Future<List<AuditLogEntry>> fetchAuditLogs({
    int page = 1,
    int limit = 20,
  }) async {
    final response = await _api.get('/admin/audit-logs?page=$page&limit=$limit');
    final logs = response['logs'] as List<dynamic>? ?? [];
    return logs
        .map((json) => AuditLogEntry.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Fetch database stats
  Future<Map<String, dynamic>> fetchDbStats() async {
    return await _api.get('/admin/db-stats');
  }

  /// Full-text search across request notes
  Future<Map<String, dynamic>> searchRequests(String query) async {
    return await _api.get('/admin/search?q=${Uri.encodeComponent(query)}');
  }
}
