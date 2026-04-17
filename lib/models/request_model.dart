// CleanIT — Cleaning Request Model

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

  // Joined fields (from relationships)
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
    // Handle nested student data from joins
    final student = json['student'] as Map<String, dynamic>?;
    // Handle nested assignment data from joins
    final assignments = json['assignments'] as List<dynamic>?;
    final assignment =
        (assignments != null && assignments.isNotEmpty)
            ? assignments.first as Map<String, dynamic>
            : null;
    final cleaner = assignment?['cleaner'] as Map<String, dynamic>?;

    return CleaningRequest(
      id: json['id'] as String,
      studentId: json['student_id'] as String,
      status: RequestStatus.fromString(json['status'] as String),
      isSweeping: json['is_sweeping'] as bool? ?? false,
      isMopping: json['is_mopping'] as bool? ?? false,
      isUrgent: json['is_urgent'] as bool? ?? false,
      notes: json['notes'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      studentName: student?['name'] as String?,
      studentBlock: student?['block'] as String?,
      studentRoom: student?['room_number'] as String?,
      cleanerName: cleaner?['name'] as String?,
      assignmentId: assignment?['id'] as String?,
    );
  }
}
