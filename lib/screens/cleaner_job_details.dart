// ============================================================
//  CleanIT — Cleaner Job Details Screen
//  Flutter Widget
//
//  Shows the active job details for a cleaner, with:
//  - Job metadata (room, tasks, notes, urgency indicator)
//  - Primary CTA: "Scan Student QR to Finish" (camera scanner)
//  - Secondary CTA: "Room Locked / Student Not Present" (photo → cancel)
//  - Status updates via polling
// ============================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../config/app_theme.dart';
import '../services/request_service.dart';
import '../services/auth_service.dart';

import '../services/qr_service.dart';
import '../services/sound_service.dart';

/// Data model representing an active cleaning job
class CleaningJob {
  final String requestId;
  final String assignmentId;
  final String roomLabel;      // e.g. "A-101"
  final bool isSweeping;
  final bool isMopping;
  final bool isUrgent;
  final String? notes;
  final String studentName;
  final String status;         // ASSIGNED, IN_PROGRESS

  CleaningJob({
    required this.requestId,
    required this.assignmentId,
    required this.roomLabel,
    required this.isSweeping,
    required this.isMopping,
    required this.isUrgent,
    this.notes,
    required this.studentName,
    required this.status,
  });
}

class CleanerJobDetailsScreen extends StatefulWidget {
  final CleaningJob job;

  const CleanerJobDetailsScreen({super.key, required this.job});

  @override
  State<CleanerJobDetailsScreen> createState() => _CleanerJobDetailsScreenState();
}

class _CleanerJobDetailsScreenState extends State<CleanerJobDetailsScreen>
    with TickerProviderStateMixin {
  late CleaningJob _job;
  bool _isLoading = false;
  bool _isStartingJob = false;
  bool _showQRScanner = false;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _job = widget.job;

    // Pulse animation for urgent jobs
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    if (_job.isUrgent) {
      _pulseController.repeat(reverse: true);
    }

    // ── Fetch full job data (student info) from API ──
    _fetchFullJobData();

    // ── Auto-poll every 5 seconds for seamless status sync ──
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) _pollRefresh();
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _pollTimer?.cancel();
    super.dispose();
  }

  /// Fetch full request data including student info from the API.
  /// This resolves "Room N/A" when the job was created from a realtime
  /// event that doesn't include joined student data.
  Future<void> _fetchFullJobData() async {
    try {
      final profile = AuthService.instance.currentProfile;
      if (profile == null) return;

      final jobs = await RequestService.instance.fetchCleanerJobs(profile.id);
      final match = jobs.where((r) => r.id == _job.requestId).firstOrNull;

      if (match == null || !mounted) return;

      final roomLabel = match.roomLabel != 'N/A'
          ? match.roomLabel
          : _job.roomLabel;

      setState(() {
        _job = CleaningJob(
          requestId: _job.requestId,
          assignmentId: _job.assignmentId,
          roomLabel: roomLabel,
          isSweeping: _job.isSweeping,
          isMopping: _job.isMopping,
          isUrgent: _job.isUrgent,
          notes: _job.notes,
          studentName: match.studentName ?? _job.studentName,
          status: match.status.dbValue,
        );
      });
    } catch (e) {
      debugPrint('Error fetching full job data: $e');
    }
  }

  /// Silent poll: re-fetch the request status and student data from the API.
  Future<void> _pollRefresh() async {
    try {
      final profile = AuthService.instance.currentProfile;
      if (profile == null) return;

      final jobs = await RequestService.instance.fetchCleanerJobs(profile.id);
      final match = jobs.where((r) => r.id == _job.requestId).firstOrNull;

      if (!mounted) return;

      if (match == null) return;

      final newStatus = match.status.dbValue;
      final roomLabel = match.roomLabel != 'N/A'
          ? match.roomLabel
          : _job.roomLabel;

      final needsUpdate = newStatus != _job.status ||
          roomLabel != _job.roomLabel;

      if (needsUpdate) {
        setState(() {
          _job = CleaningJob(
            requestId: _job.requestId,
            assignmentId: _job.assignmentId,
            roomLabel: roomLabel,
            isSweeping: _job.isSweeping,
            isMopping: _job.isMopping,
            isUrgent: _job.isUrgent,
            notes: _job.notes,
            studentName: match.studentName ?? _job.studentName,
            status: newStatus,
          );
        });

        if (newStatus == 'COMPLETED') {
          _showSuccessDialog();
        }
      }
    } catch (e) {
      debugPrint('Poll refresh error: $e');
    }
  }



  // ── Start Job: ASSIGNED → IN_PROGRESS ──
  Future<void> _startJob() async {
    setState(() => _isStartingJob = true);

    try {
      final result = await RequestService.instance.startJob(_job.requestId);

      if (result['success'] == true) {
        setState(() {
          _job = CleaningJob(
            requestId: _job.requestId,
            assignmentId: _job.assignmentId,
            roomLabel: _job.roomLabel,
            isSweeping: _job.isSweeping,
            isMopping: _job.isMopping,
            isUrgent: _job.isUrgent,
            notes: _job.notes,
            studentName: _job.studentName,
            status: 'IN_PROGRESS',
          );
        });
      } else {
        SoundService.instance.play(AppSound.error);
        _showError(result['message'] ?? 'Could not start job. Please try again.');
      }
    } catch (e) {
      SoundService.instance.play(AppSound.error);
      _showError('Connection issue. Please check your internet and try again.');
    } finally {
      setState(() => _isStartingJob = false);
    }
  }

  // ── Scan QR: Opens camera scanner ──
  void _openQRScanner() {
    setState(() => _showQRScanner = true);
  }

  Future<void> _onQRScanned(String qrPayload) async {
    setState(() {
      _showQRScanner = false;
      _isLoading = true;
    });

    try {
      // 1. Validate QR payload client-side (signature + expiry)
      final isValid = QRService.instance.validatePayload(
        qrPayload,
        _job.requestId,
      );

      if (!isValid) {
        SoundService.instance.play(AppSound.error);
        _showError('Invalid or expired QR code. Ask the student to generate a new one.');
        return;
      }

      // 2. Complete the job via API call
      final result = await RequestService.instance.verifyQR(
        requestId: _job.requestId,
        qrPayload: qrPayload,
      );

      if (result['success'] == true) {
        SoundService.instance.play(AppSound.qrSuccess);
        _showSuccessDialog();
      } else {
        SoundService.instance.play(AppSound.error);
        _showError(result['message'] ?? 'Verification failed. Please try again.');
      }
    } catch (e) {
      SoundService.instance.play(AppSound.error);
      _showError('Connection issue. Please check your internet and try again.');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // ── Room Locked Flow ──
  Future<void> _reportRoomLocked() async {
    final c = AppTheme.of(context);
    // Confirm with the cleaner first
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.base,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.lock_outline, color: c.red, size: 28),
            const SizedBox(width: 12),
            Text('Room Locked?', style: TextStyle(color: c.text)),
          ],
        ),
        content: Text(
          'You\'ll need to take a photo of the locked door as proof. '
          'The student will be notified that their request was cancelled.',
          style: TextStyle(color: c.subtext0, fontSize: 15),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Go Back', style: TextStyle(color: c.overlay0)),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.camera_alt, size: 18),
            label: const Text('Take Photo'),
            style: ElevatedButton.styleFrom(
              backgroundColor: c.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Open camera to capture proof photo
    final picker = ImagePicker();
    final XFile? photo = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 70,
      maxWidth: 1200,
    );

    if (photo == null) {
      _showError('Photo is required to report a locked room.');
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Report room locked via API (photo upload handled server-side in future)
      final result = await RequestService.instance.reportRoomLocked(
        requestId: _job.requestId,
        photoPath: photo.path,
        failureReason: 'room_locked',
      );

      if (result['success'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Report submitted. Student notified.',
                  style: TextStyle(color: Color(0xFF1E1E2E), fontWeight: FontWeight.w600)),
              backgroundColor: AppTheme.peach,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
          Navigator.of(context).pop();
        }
      } else {
        _showError(result['message'] ?? 'Could not submit report. Please try again.');
      }
    } catch (e) {
      _showError('Connection issue. Please check your internet and try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    SoundService.instance.play(AppSound.error);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
        backgroundColor: AppTheme.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _showSuccessDialog() {
    final c = AppTheme.of(context);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.base,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    c.green.withValues(alpha: 0.3),
                    c.green.withValues(alpha: 0.1),
                  ],
                ),
              ),
              child: Icon(
                Icons.check_circle_rounded,
                color: c.green,
                size: 56,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Job Completed! 🎉',
              style: TextStyle(
                color: c.text,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Room ${_job.roomLabel} has been cleaned successfully.',
              textAlign: TextAlign.center,
              style: TextStyle(color: c.subtext0, fontSize: 15),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.pop(context); // Return to dashboard
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: c.green,
                  foregroundColor: c.crust,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'Back to Dashboard',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // If QR scanner is active, show full-screen scanner
    if (_showQRScanner) {
      return _buildQRScannerView();
    }

    final c = AppTheme.of(context);
    return Scaffold(
      backgroundColor: c.crust,
      appBar: AppBar(
        backgroundColor: c.base,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, color: c.text),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Active Job',
          style: TextStyle(
            color: c.text,
            fontWeight: FontWeight.w600,
            fontSize: 20,
          ),
        ),
        centerTitle: true,
        actions: [
          // Status chip
          Container(
            margin: const EdgeInsets.only(right: 16),
            child: Chip(
              label: Text(
                _job.status.replaceAll('_', ' '),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              backgroundColor: _statusColor(c),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 140),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Room Header ──
                _buildRoomHeader(c),
                const SizedBox(height: 24),

                // ── Task Cards ──
                _buildSectionTitle('Tasks', c),
                const SizedBox(height: 12),
                _buildTaskCards(c),
                const SizedBox(height: 24),

                // ── Student Notes ──
                if (_job.notes != null && _job.notes!.isNotEmpty) ...[
                  _buildSectionTitle('Note from Student', c),
                  const SizedBox(height: 12),
                  _buildNotesCard(c),
                  const SizedBox(height: 24),
                ],

                // ── Student Info ──
                _buildSectionTitle('Student', c),
                const SizedBox(height: 12),
                _buildStudentInfoCard(c),
              ],
            ),
          ),

          // ── Bottom Action Buttons ──
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildActionButtons(c),
          ),

          // ── Loading Overlay ──
          if (_isLoading)
            Container(
              color: Colors.black54,
              child: Center(
                child: CircularProgressIndicator(
                  color: c.blue,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Color _statusColor(ThemeColors c) {
    switch (_job.status) {
      case 'ASSIGNED':
        return c.blue;
      case 'IN_PROGRESS':
        return c.peach;
      case 'COMPLETED':
        return c.green;
      default:
        return c.overlay0;
    }
  }

  Widget _buildRoomHeader(ThemeColors c) {
    return ScaleTransition(
      scale: _job.isUrgent ? _pulseAnimation : const AlwaysStoppedAnimation(1.0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: _job.isUrgent
                ? [
                    c.red.withValues(alpha: 0.25),
                    c.red.withValues(alpha: 0.15),
                  ]
                : [
                    c.blue.withValues(alpha: 0.15),
                    c.mauve.withValues(alpha: 0.1),
                  ],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _job.isUrgent
                ? c.red.withValues(alpha: 0.4)
                : c.blue.withValues(alpha: 0.2),
            width: 1.5,
          ),
        ),
        child: Column(
          children: [
            // Urgent badge
            if (_job.isUrgent)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: c.red,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.white, size: 18),
                    SizedBox(width: 6),
                    Text(
                      'URGENT',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ),

            // Room icon
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.1),
              ),
              child: Icon(
                Icons.meeting_room_rounded,
                size: 32,
                color: _job.isUrgent ? c.red : c.blue,
              ),
            ),
            const SizedBox(height: 16),

            // Room label
            Text(
              'Room ${_job.roomLabel}',
              style: TextStyle(
                color: c.text,
                fontSize: 28,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title, ThemeColors c) {
    return Text(
      title,
      style: TextStyle(
        color: c.overlay0,
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.1,
      ),
    );
  }

  Widget _buildTaskCards(ThemeColors c) {
    return Row(
      children: [
        if (_job.isSweeping)
          Expanded(child: _taskChip('Floor Sweeping', Icons.cleaning_services_rounded, c)),
        if (_job.isSweeping && _job.isMopping) const SizedBox(width: 12),
        if (_job.isMopping)
          Expanded(child: _taskChip('Wet Mopping', Icons.water_drop_rounded, c)),
      ],
    );
  }

  Widget _taskChip(String label, IconData icon, ThemeColors c) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
      decoration: BoxDecoration(
        color: c.base,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.surface0, width: 1),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: c.teal, size: 22),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                color: c.text,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotesCard(ThemeColors c) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: c.base,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.surface0, width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.sticky_note_2_rounded,
            color: c.yellow,
            size: 22,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              _job.notes!,
              style: TextStyle(
                color: c.text,
                fontSize: 15,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStudentInfoCard(ThemeColors c) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: c.base,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.surface0, width: 1),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: c.mauve.withValues(alpha: 0.2),
            child: Text(
              _job.studentName.isNotEmpty ? _job.studentName[0].toUpperCase() : '?',
              style: TextStyle(
                color: c.mauve,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _job.studentName,
                  style: TextStyle(
                    color: c.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Room ${_job.roomLabel}',
                  style: TextStyle(
                    color: c.overlay0,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(ThemeColors c) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      decoration: BoxDecoration(
        color: c.base,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Primary Action ──
          if (_job.status == 'ASSIGNED')
            // "Start Job" button when status is ASSIGNED
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: _isStartingJob ? null : _startJob,
                icon: _isStartingJob
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.play_arrow_rounded, size: 24),
                label: Text(
                  _isStartingJob ? 'Starting...' : 'Start Job',
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: c.blue,
                  foregroundColor: c.crust,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ),
              ),
            )
          else if (_job.status == 'IN_PROGRESS')
            // "Scan QR to Finish" button when status is IN_PROGRESS
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: _openQRScanner,
                icon: const Icon(Icons.qr_code_scanner_rounded, size: 26),
                label: const Text(
                  'Scan Student QR to Finish',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: c.green,
                  foregroundColor: c.crust,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ),
              ),
            ),

          const SizedBox(height: 12),

          // ── Secondary Action: Room Locked ──
          if (_job.status == 'ASSIGNED' || _job.status == 'IN_PROGRESS')
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: _reportRoomLocked,
                icon: const Icon(Icons.lock_outline, size: 18),
                label: const Text(
                  'Student not present / Room locked',
                  style: TextStyle(fontSize: 14),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: c.overlay0,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Full-Screen QR Scanner ──
  Widget _buildQRScannerView() {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => setState(() => _showQRScanner = false),
        ),
        title: const Text(
          'Scan Student\'s QR Code',
          style: TextStyle(color: Colors.white, fontSize: 18),
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          MobileScanner(
            onDetect: (BarcodeCapture capture) {
              final List<Barcode> barcodes = capture.barcodes;
              if (barcodes.isNotEmpty && barcodes.first.rawValue != null) {
                _onQRScanned(barcodes.first.rawValue!);
              }
            },
          ),
          // Scanner overlay
          Center(
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                border: Border.all(
                  color: AppTheme.green.withValues(alpha: 0.7),
                  width: 3,
                ),
                borderRadius: BorderRadius.circular(24),
              ),
            ),
          ),
          // Instructions
          Positioned(
            bottom: 80,
            left: 40,
            right: 40,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Text(
                'Ask the student to open CleanIT and\ntap "Show QR to Cleaner"',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  height: 1.4,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
