// CleanIT — User Model (MongoDB)

enum UserRole { student, cleaner, admin }

class AppUser {
  final String id;
  final String email;
  final String name;
  final UserRole role;
  final String? block;
  final String? roomNumber;
  final String? fcmToken;
  final bool isOnDuty;

  AppUser({
    required this.id,
    required this.email,
    required this.name,
    required this.role,
    this.block,
    this.roomNumber,
    this.fcmToken,
    this.isOnDuty = false,
  });

  String get roomLabel =>
      (block != null && roomNumber != null) ? '$block-$roomNumber' : 'N/A';

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      // MongoDB uses _id, but our API transforms it to 'id'
      id: (json['id'] ?? json['_id'] ?? '') as String,
      email: json['email'] as String,
      name: json['name'] as String,
      role: UserRole.values.firstWhere(
        (r) => r.name == json['role'],
        orElse: () => UserRole.student,
      ),
      block: json['block'] as String?,
      roomNumber: json['roomNumber'] as String?,
      fcmToken: json['fcmToken'] as String?,
      isOnDuty: json['isOnDuty'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'name': name,
        'role': role.name,
        'block': block,
        'roomNumber': roomNumber,
        'fcmToken': fcmToken,
        'isOnDuty': isOnDuty,
      };
}
