// CleanIT — User Model

enum UserRole { student, cleaner, admin }

class AppUser {
  final String id;
  final String? authId;
  final String email;
  final String name;
  final UserRole role;
  final String? block;
  final String? roomNumber;
  final String? fcmToken;
  final bool isOnDuty;

  AppUser({
    required this.id,
    this.authId,
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
      id: json['id'] as String,
      authId: json['auth_id'] as String?,
      email: json['email'] as String,
      name: json['name'] as String,
      role: UserRole.values.firstWhere(
        (r) => r.name == json['role'],
        orElse: () => UserRole.student,
      ),
      block: json['block'] as String?,
      roomNumber: json['room_number'] as String?,
      fcmToken: json['fcm_token'] as String?,
      isOnDuty: json['is_on_duty'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'auth_id': authId,
        'email': email,
        'name': name,
        'role': role.name,
        'block': block,
        'room_number': roomNumber,
        'fcm_token': fcmToken,
        'is_on_duty': isOnDuty,
      };
}
