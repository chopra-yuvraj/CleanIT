/// CleanIT — Active Job Screen (Student Side)
///
/// Shows the student's active request status with:
/// - Real-time status indicator
/// - Assigned cleaner info
/// - "Show QR to Cleaner" button (generates time-limited QR)
/// - QR countdown timer (3-minute expiry)
/// - Feedback prompt after completion

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_theme.dart';
import '../models/models.dart';
import '../services/services.dart';

class ActiveJobScreen extends StatefulWidget {
  final CleaningRequest request;

  const ActiveJobScreen({super.key, required this.request});

  @override
  State<ActiveJobScreen> createState() => _ActiveJobScreenState();
}

class _ActiveJobScreenState extends State<ActiveJobScreen> {
  late CleaningRequest _request;
  String? _qrPayload;
  Timer? _qrTimer;
  int _qrRemainingSeconds = 0;
  bool _showFeedback = false;
  int _rating = 0;

  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _request = widget.request;
    _subscribeToStatus();
  }

  @override
  void dispose() {
    _qrTimer?.cancel();
    _channel?.unsubscribe();
    super.dispose();
  }

  void _subscribeToStatus() {
    _channel = RequestService.instance.subscribeToRequestStatus(
      _request.id,
      (newStatus) {
        if (!mounted) return;
        setState(() {
          _request = _request.copyWith(status: newStatus);
        });

        if (newStatus == RequestStatus.completed) {
          setState(() => _showFeedback = true);
        }

        if (newStatus == RequestStatus.cancelledRoomLocked) {
          _showLockedDialog();
        }
      },
    );
  }

  void _generateQR() {
    final profile = AuthService.instance.currentProfile;
    if (profile == null) return;

    final payload = QRService.instance.generatePayload(
      requestId: _request.id,
      studentId: profile.id,
    );

    setState(() {
      _qrPayload = payload;
      _qrRemainingSeconds = 180; // 3 minutes
    });

    _qrTimer?.cancel();
    _qrTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _qrRemainingSeconds--;
        if (_qrRemainingSeconds <= 0) {
          _qrPayload = null;
          timer.cancel();
        }
      });
    });
  }

  Future<void> _submitFeedback() async {
    if (_rating == 0) return;

    try {
      final profile = AuthService.instance.currentProfile;
      await RequestService.instance.submitFeedback(
        requestId: _request.id,
        studentId: profile!.id,
        rating: _rating,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Thank you for your feedback! ⭐'),
          backgroundColor: AppTheme.green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.red),
      );
    }
  }

  void _showLockedDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.base,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.red.withOpacity(0.15),
              ),
              child: const Icon(Icons.lock_rounded,
                  color: AppTheme.red, size: 32),
            ),
            const SizedBox(height: 18),
            Text('Room Was Locked',
                style: GoogleFonts.outfit(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Colors.white)),
            const SizedBox(height: 8),
            const Text(
              'Your cleaner arrived, but your room was locked. '
              'The request has been cancelled.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.subtext0, fontSize: 14),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.red,
                    foregroundColor: Colors.white),
                child: const Text('Understood'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_showFeedback) return _buildFeedbackView();

    return Scaffold(
      backgroundColor: AppTheme.crust,
      appBar: AppBar(
        backgroundColor: AppTheme.base,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: AppTheme.text),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Active Request',
            style: GoogleFonts.outfit(
                fontWeight: FontWeight.w600, color: Colors.white)),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            child: Chip(
              label: Text(_request.status.displayLabel,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
              backgroundColor: _statusColor,
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // ── Status Timeline ──
            _buildStatusTimeline(),
            const SizedBox(height: 28),

            // ── Task Info ──
            _buildInfoCard(),
            const SizedBox(height: 20),

            // ── Cleaner Info (if assigned) ──
            if (_request.cleanerName != null) ...[
              _buildCleanerCard(),
              const SizedBox(height: 28),
            ],

            // ── QR Section ──
            if (_request.status == RequestStatus.inProgress) ...[
              if (_qrPayload != null) _buildQRDisplay() else _buildGenerateQRButton(),
            ],
          ],
        ),
      ),
    );
  }

  Color get _statusColor {
    switch (_request.status) {
      case RequestStatus.open:
        return AppTheme.blue;
      case RequestStatus.assigned:
        return AppTheme.teal;
      case RequestStatus.inProgress:
        return AppTheme.peach;
      case RequestStatus.completed:
        return AppTheme.green;
      case RequestStatus.cancelledRoomLocked:
        return AppTheme.red;
    }
  }

  Widget _buildStatusTimeline() {
    final steps = [
      ('Open', RequestStatus.open, Icons.radio_button_checked_rounded),
      ('Assigned', RequestStatus.assigned, Icons.person_add_alt_1_rounded),
      ('In Progress', RequestStatus.inProgress, Icons.cleaning_services_rounded),
      ('Completed', RequestStatus.completed, Icons.check_circle_rounded),
    ];

    final currentIdx = steps.indexWhere((s) => s.$2 == _request.status);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.base,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.surface0),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(steps.length, (i) {
          final isActive = i <= currentIdx;
          final isCurrent = i == currentIdx;
          return Expanded(
            child: Column(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isActive
                        ? _statusColor.withOpacity(isCurrent ? 0.3 : 0.1)
                        : AppTheme.surface0,
                    border: isCurrent
                        ? Border.all(color: _statusColor, width: 2)
                        : null,
                  ),
                  child: Icon(
                    steps[i].$3,
                    size: 18,
                    color: isActive ? _statusColor : AppTheme.overlay0,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  steps[i].$1,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                    color: isActive ? Colors.white : AppTheme.overlay0,
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.base,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.surface0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_request.tasksSummary,
              style: GoogleFonts.outfit(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: Colors.white)),
          if (_request.isUrgent) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                  color: AppTheme.red, borderRadius: BorderRadius.circular(8)),
              child: const Text('URGENT',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800)),
            ),
          ],
          if (_request.notes != null) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.sticky_note_2_rounded,
                    color: AppTheme.yellow, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(_request.notes!,
                      style: const TextStyle(
                          color: AppTheme.subtext0, fontSize: 14)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCleanerCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.base,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.surface0),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: AppTheme.green.withOpacity(0.2),
            child: const Icon(Icons.person, color: AppTheme.green, size: 22),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Assigned Cleaner',
                  style: TextStyle(color: AppTheme.overlay0, fontSize: 12)),
              const SizedBox(height: 2),
              Text(_request.cleanerName!,
                  style: GoogleFonts.outfit(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGenerateQRButton() {
    return SizedBox(
      width: double.infinity,
      height: 120,
      child: ElevatedButton.icon(
        onPressed: _generateQR,
        icon: const Icon(Icons.qr_code_2_rounded, size: 40),
        label: Text('Show QR to Cleaner',
            style: GoogleFonts.outfit(
                fontSize: 18, fontWeight: FontWeight.w700)),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.green,
          foregroundColor: AppTheme.crust,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        ),
      ),
    );
  }

  Widget _buildQRDisplay() {
    final minutes = _qrRemainingSeconds ~/ 60;
    final seconds = _qrRemainingSeconds % 60;
    final isExpiring = _qrRemainingSeconds < 30;

    return Column(
      children: [
        // QR Code
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
          ),
          child: QrImageView(
            data: _qrPayload!,
            version: QrVersions.auto,
            size: 220,
            backgroundColor: Colors.white,
            eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.roundedOuter, color: Color(0xFF1E1E2E)),
            dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.roundedOutsideCorners,
                color: Color(0xFF1E1E2E)),
          ),
        ),
        const SizedBox(height: 16),

        // Timer
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            color: isExpiring
                ? AppTheme.red.withOpacity(0.15)
                : AppTheme.base,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isExpiring ? AppTheme.red : AppTheme.surface0,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.timer_outlined,
                  size: 18,
                  color: isExpiring ? AppTheme.red : AppTheme.overlay0),
              const SizedBox(width: 8),
              Text(
                'Expires in ${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}',
                style: TextStyle(
                  color: isExpiring ? AppTheme.red : AppTheme.text,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Regenerate button
        TextButton.icon(
          onPressed: _generateQR,
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Generate New Code'),
          style:
              TextButton.styleFrom(foregroundColor: AppTheme.blue),
        ),
      ],
    );
  }

  // ── Feedback View ──
  Widget _buildFeedbackView() {
    return Scaffold(
      backgroundColor: AppTheme.crust,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTheme.green.withOpacity(0.15),
                  ),
                  child: const Icon(Icons.check_circle_rounded,
                      color: AppTheme.green, size: 48),
                ),
                const SizedBox(height: 24),
                Text('Room Cleaned! 🎉',
                    style: GoogleFonts.outfit(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: Colors.white)),
                const SizedBox(height: 8),
                const Text('How was the cleaning?',
                    style: TextStyle(color: AppTheme.subtext0, fontSize: 16)),
                const SizedBox(height: 32),

                // Star rating
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (i) {
                    return GestureDetector(
                      onTap: () => setState(() => _rating = i + 1),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Icon(
                          i < _rating
                              ? Icons.star_rounded
                              : Icons.star_border_rounded,
                          size: 44,
                          color: i < _rating
                              ? AppTheme.yellow
                              : AppTheme.surface1,
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 36),

                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _rating > 0 ? _submitFeedback : null,
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.green,
                        foregroundColor: AppTheme.crust),
                    child: Text('Submit Feedback',
                        style: GoogleFonts.outfit(
                            fontSize: 17, fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Skip',
                      style: TextStyle(color: AppTheme.overlay0)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
