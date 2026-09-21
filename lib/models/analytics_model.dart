// CleanIT — Analytics Models
//
// Data models for analytics responses from the MongoDB aggregation pipeline.

class AnalyticsOverview {
  final int totalRequests;
  final int completedRequests;
  final int cancelledRequests;
  final int activeRequests;
  final int urgentRequests;
  final double completionRate;
  final double avgCompletionMinutes;
  final int totalStudents;
  final int totalCleaners;
  final String avgRating;
  final int totalFeedback;

  AnalyticsOverview({
    required this.totalRequests,
    required this.completedRequests,
    required this.cancelledRequests,
    required this.activeRequests,
    required this.urgentRequests,
    required this.completionRate,
    required this.avgCompletionMinutes,
    required this.totalStudents,
    required this.totalCleaners,
    required this.avgRating,
    required this.totalFeedback,
  });

  factory AnalyticsOverview.fromJson(Map<String, dynamic> json) {
    return AnalyticsOverview(
      totalRequests: (json['totalRequests'] ?? 0) as int,
      completedRequests: (json['completedRequests'] ?? 0) as int,
      cancelledRequests: (json['cancelledRequests'] ?? 0) as int,
      activeRequests: (json['activeRequests'] ?? 0) as int,
      urgentRequests: (json['urgentRequests'] ?? 0) as int,
      completionRate: (json['completionRate'] ?? 0).toDouble(),
      avgCompletionMinutes: (json['avgCompletionMinutes'] ?? 0).toDouble(),
      totalStudents: (json['totalStudents'] ?? 0) as int,
      totalCleaners: (json['totalCleaners'] ?? 0) as int,
      avgRating: (json['avgRating'] ?? '0.0').toString(),
      totalFeedback: (json['totalFeedback'] ?? 0) as int,
    );
  }
}

class BlockStat {
  final String block;
  final int totalRequests;
  final int completedRequests;
  final int urgentRequests;

  BlockStat({
    required this.block,
    required this.totalRequests,
    required this.completedRequests,
    required this.urgentRequests,
  });

  factory BlockStat.fromJson(Map<String, dynamic> json) {
    return BlockStat(
      block: (json['block'] ?? 'Unknown') as String,
      totalRequests: (json['totalRequests'] ?? 0) as int,
      completedRequests: (json['completedRequests'] ?? 0) as int,
      urgentRequests: (json['urgentRequests'] ?? 0) as int,
    );
  }
}

class LeaderboardEntry {
  final String cleanerId;
  final String cleanerName;
  final int completedJobs;
  final double avgCompletionMinutes;

  LeaderboardEntry({
    required this.cleanerId,
    required this.cleanerName,
    required this.completedJobs,
    required this.avgCompletionMinutes,
  });

  factory LeaderboardEntry.fromJson(Map<String, dynamic> json) {
    return LeaderboardEntry(
      cleanerId: (json['cleanerId'] ?? '') as String,
      cleanerName: (json['cleanerName'] ?? 'Unknown') as String,
      completedJobs: (json['completedJobs'] ?? 0) as int,
      avgCompletionMinutes: (json['avgCompletionMinutes'] ?? 0).toDouble(),
    );
  }
}

class HourlyStat {
  final int hour;
  final String label;
  final int count;

  HourlyStat({
    required this.hour,
    required this.label,
    required this.count,
  });

  factory HourlyStat.fromJson(Map<String, dynamic> json) {
    return HourlyStat(
      hour: (json['hour'] ?? 0) as int,
      label: (json['label'] ?? '') as String,
      count: (json['count'] ?? 0) as int,
    );
  }
}

class StatusStat {
  final String status;
  final int count;

  StatusStat({required this.status, required this.count});

  factory StatusStat.fromJson(Map<String, dynamic> json) {
    return StatusStat(
      status: (json['status'] ?? 'UNKNOWN') as String,
      count: (json['count'] ?? 0) as int,
    );
  }
}

class TrendPoint {
  final String date;
  final int count;
  final int completed;

  TrendPoint({
    required this.date,
    required this.count,
    required this.completed,
  });

  factory TrendPoint.fromJson(Map<String, dynamic> json) {
    return TrendPoint(
      date: (json['date'] ?? '') as String,
      count: (json['count'] ?? 0) as int,
      completed: (json['completed'] ?? 0) as int,
    );
  }
}

class AuditLogEntry {
  final String id;
  final String collection;
  final String documentId;
  final String action;
  final String performedByName;
  final Map<String, dynamic>? changes;
  final String summary;
  final DateTime timestamp;

  AuditLogEntry({
    required this.id,
    required this.collection,
    required this.documentId,
    required this.action,
    required this.performedByName,
    this.changes,
    required this.summary,
    required this.timestamp,
  });

  factory AuditLogEntry.fromJson(Map<String, dynamic> json) {
    return AuditLogEntry(
      id: (json['id'] ?? json['_id'] ?? '') as String,
      collection: (json['collection'] ?? '') as String,
      documentId: (json['documentId'] ?? '') as String,
      action: (json['action'] ?? '') as String,
      performedByName: (json['performedByName'] ?? 'system') as String,
      changes: json['changes'] as Map<String, dynamic>?,
      summary: (json['summary'] ?? '') as String,
      timestamp: DateTime.tryParse(
            (json['timestamp'] ?? '').toString(),
          ) ??
          DateTime.now(),
    );
  }
}
