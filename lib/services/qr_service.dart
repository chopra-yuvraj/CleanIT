/// CleanIT — QR Service
///
/// Generates HMAC-signed, time-limited QR payloads for verification
/// and validates incoming QR data on the client side (optional pre-check).

import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../config/app_config.dart';

class QRService {
  QRService._();
  static final QRService instance = QRService._();

  /// Generate a signed QR payload for a given request.
  ///
  /// The QR code contains:
  /// - request_id: the cleaning request UUID
  /// - student_id: the student's user UUID
  /// - timestamp: current epoch milliseconds
  /// - signature: HMAC-SHA256 of "request_id:student_id:timestamp"
  ///
  /// Returns a base64-encoded JSON string to display as QR.
  String generatePayload({
    required String requestId,
    required String studentId,
  }) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    // Create HMAC signature
    final message = '$requestId:$studentId:$timestamp';
    final key = utf8.encode(AppConfig.qrSigningSecret);
    final hmacSha256 = Hmac(sha256, key);
    final digest = hmacSha256.convert(utf8.encode(message));
    final signature = digest.toString();

    // Build the payload
    final payload = {
      'request_id': requestId,
      'student_id': studentId,
      'timestamp': timestamp,
      'signature': signature,
    };

    // Base64 encode the JSON
    return base64Encode(utf8.encode(jsonEncode(payload)));
  }

  /// Check if a QR payload has expired (client-side pre-check).
  /// The real validation happens server-side in the verify-qr Edge Function.
  bool isExpired(String base64Payload) {
    try {
      final decoded = utf8.decode(base64Decode(base64Payload));
      final data = jsonDecode(decoded) as Map<String, dynamic>;
      final timestamp = data['timestamp'] as int;
      final age = DateTime.now().millisecondsSinceEpoch - timestamp;
      return age > AppConfig.qrExpiry.inMilliseconds;
    } catch (_) {
      return true;
    }
  }

  /// Calculate remaining seconds before expiry.
  int remainingSeconds(String base64Payload) {
    try {
      final decoded = utf8.decode(base64Decode(base64Payload));
      final data = jsonDecode(decoded) as Map<String, dynamic>;
      final timestamp = data['timestamp'] as int;
      final elapsed = DateTime.now().millisecondsSinceEpoch - timestamp;
      final remaining =
          (AppConfig.qrExpiry.inMilliseconds - elapsed) ~/ 1000;
      return remaining.clamp(0, AppConfig.qrExpiry.inSeconds);
    } catch (_) {
      return 0;
    }
  }
}
