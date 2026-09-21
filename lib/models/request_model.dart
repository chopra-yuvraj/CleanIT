// CleanIT — Cleaning Request Model (MongoDB)

enum RequestStatus {
  open,
  assigned,
  inProgress,
  completed,
  cancelledRoomLocked;

  /// Parse from database string like 'OPEN', 'IN_PROGRESS', etc.
  static RequestStatus fromString(String value) {
    switch (value.toUpperCase()) {
      case 'OPEN':
        return RequestStatus.open;
      case 'ASSIGNED':
        return RequestStatus.assigned;
      case 'IN_PROGRESS':
        return RequestStatus.inProgress;
      case 'COMPLETED':
        return RequestStatus.completed;
      case 'CANCELLED_ROOM_LOCKED':
        return RequestStatus.cancelledRoomLocked;
      default:
        return RequestStatus.open;
    }
  }

  String get dbValue {
    switch (this) {
      case RequestStatus.open:
        return 'OPEN';
      case RequestStatus.assigned:
        return 'ASSIGNED';
      case RequestStatus.inProgress:
        return 'IN_PROGRESS';
      case RequestStatus.completed:
        return 'COMPLETED';
      case RequestStatus.cancelledRoomLocked:
        return 'CANCELLED_ROOM_LOCKED';
    }
  }

  String get displayLabel {
    switch (this) {
      case RequestStatus.open:
        return 'Open';
      case RequestStatus.assigned:
        return 'Assigned';
      case RequestStatus.inProgress:
        return 'In Progress';
      case RequestStatus.completed:
        return 'Completed';
      case RequestStatus.cancelledRoomLocked:
        return 'Cancelled — Room Locked';
    }
  }

  bool get isActive =>
      this == RequestStatus.open ||
      this == RequestStatus.assigned ||
      this == RequestStatus.inProgress;
}

class CleaningRequest {
  final String id;
  final String studentId;
  final RequestStatus status;
  final bool isSweeping;
  final bool isMopping;
  final bool isUrgent;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Denormalized / embedded fields
  final String? studentName;
  final String? studentBlock;
  final String? studentRoom;
  final String? cleanerName;
  final String? assignmentId;

  CleaningRequest({
    required this.id,
    required this.studentId,
    required this.status,
    required this.isSweeping,
    required this.isMopping,
    required this.isUrgent,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
    this.studentName,
    this.studentBlock,
    this.studentRoom,
    this.cleanerName,
    this.assignmentId,
  });

  String get roomLabel =>
      (studentBlock != null && studentRoom != null)
          ? '$studentBlock-$studentRoom'
          : 'N/A';

  String get tasksSummary {
    final tasks = <String>[];
    if (isSweeping) tasks.add('Floor Sweeping');
    if (isMopping) tasks.add('Wet Mopping');
    return tasks.join(' + ');
  }

  CleaningRequest copyWith({RequestStatus? status, String? cleanerName, String? assignmentId}) {
    return CleaningRequest(
      id: id,
      studentId: studentId,
      status: status ?? this.status,
      isSweeping: isSweeping,
      isMopping: isMopping,
      isUrgent: isUrgent,
      notes: notes,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      studentName: studentName,
      studentBlock: studentBlock,
      studentRoom: studentRoom,
      cleanerName: cleanerName ?? this.cleanerName,
      assignmentId: assignmentId ?? this.assignmentId,
    );
  }

  factory CleaningRequest.fromJson(Map<String, dynamic> json) {
    // Handle embedded assignment (MongoDB embedded document pattern)
    final assignment = json['assignment'] as Map<String, dynamic>?;

    return CleaningRequest(
      // MongoDB _id or API-transformed 'id'
      id: (json['id'] ?? json['_id'] ?? '') as String,
      studentId: (json['studentId'] ?? json['student_id'] ?? '') as String,
      status: RequestStatus.fromString((json['status'] ?? 'OPEN') as String),
      isSweeping: json['isSweeping'] as bool? ?? json['is_sweeping'] as bool? ?? false,
      isMopping: json['isMopping'] as bool? ?? json['is_mopping'] as bool? ?? false,
      isUrgent: json['isUrgent'] as bool? ?? json['is_urgent'] as bool? ?? false,
      notes: json['notes'] as String?,
      createdAt: _parseDate(json['createdAt'] ?? json['created_at']),
      updatedAt: _parseDate(json['updatedAt'] ?? json['updated_at']),
      // Denormalized student info
      studentName: json['studentName'] as String? ?? json['student_name'] as String?,
      studentBlock: json['studentBlock'] as String? ?? json['student_block'] as String?,
      studentRoom: json['studentRoom'] as String? ?? json['student_room'] as String?,
      // Embedded assignment data
      cleanerName: assignment?['cleanerName'] as String? ?? assignment?['cleaner_name'] as String?,
      assignmentId: (assignment?['id'] ?? assignment?['_id'])?.toString(),
    );
  }

  static DateTime _parseDate(dynamic value) {
    if (value == null) return DateTime.now();
    if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
    return DateTime.now();
  }
}
