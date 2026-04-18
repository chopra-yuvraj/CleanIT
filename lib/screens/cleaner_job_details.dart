// ============================================================
//  CleanIT — Cleaner Job Details Screen
//  Flutter Widget
//
//  Shows the active job details for a cleaner, with:
//  - Job metadata (room, tasks, notes, urgency indicator)
//  - Primary CTA: "Scan Student QR to Finish" (camera scanner)
//  - Secondary CTA: "Room Locked / Student Not Present" (photo → cancel)
//  - Real-time status updates via Supabase Realtime
// ============================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  // Supabase realtime subscription
  RealtimeChannel? _realtimeChannel;
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

    _subscribeToRealtimeUpdates();

    // ── Fetch full job data (student info) from DB ──
    _fetchFullJobData();

    // ── Auto-poll every 5 seconds for seamless status sync ──
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) _pollRefresh();
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _realtimeChannel?.unsubscribe();
    _pollTimer?.cancel();
    super.dispose();
  }

  /// Fetch full request data including student info from the database.
  /// This resolves "Room N/A" when the job was created from a realtime
  /// event that doesn't include joined student data.
  Future<void> _fetchFullJobData() async {
    try {
      final supabase = Supabase.instance.client;
      final row = await supabase
          .from('requests')
          .select('''
            status,
            student:users!requests_student_id_fkey ( name, block, room_number )
          ''')
          .eq('id', _job.requestId)
          .single();

      if (!mounted) return;

      final student = row['student'] as Map<String, dynamic>?;
      final block = student?['block'] as String?;
      final room = student?['room_number'] as String?;
      final name = student?['name'] as String?;
      final status = row['status'] as String;

      final roomLabel = (block != null && room != null)
          ? '$block-$room'
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
          studentName: name ?? _job.studentName,
          status: status,
        );
      });
    } catch (e) {
      debugPrint('Error fetching full job data: $e');
    }
  }

  /// Silent poll: re-fetch the request status and student data from the database.
  Future<void> _pollRefresh() async {
    try {
      final supabase = Supabase.instance.client;
      final row = await supabase
          .from('requests')
          .select('''
            status,
            student:users!requests_student_id_fkey ( name, block, room_number )
          ''')
          .eq('id', _job.requestId)
          .maybeSingle();

      if (row == null || !mounted) return;

      final newStatus = row['status'] as String;
      final student = row['student'] as Map<String, dynamic>?;
      final block = student?['block'] as String?;
      final room = student?['room_number'] as String?;
      final name = student?['name'] as String?;

      final roomLabel = (block != null && room != null)
          ? '$block-$room'
          : _job.roomLabel;

      final needsUpdate = newStatus != _job.status ||
          roomLabel != _job.roomLabel ||
          (name != null && name != _job.studentName);

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
            studentName: name ?? _job.studentName,
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

  /// Subscribe to real-time status changes on this request
  void _subscribeToRealtimeUpdates() {
    final supabase = Supabase.instance.client;
    _realtimeChannel = supabase
        .channel('request-${_job.requestId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'requests',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: _job.requestId,
          ),
          callback: (payload) {
            final newStatus = payload.newRecord['status'] as String?;
            if (newStatus != null && mounted) {
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
                  status: newStatus,
                );
              });

              if (newStatus == 'COMPLETED') {
                _showSuccessDialog();
              }
            }
          },
        )
        .subscribe();
  }

  // ── Start Job: ASSIGNED → IN_PROGRESS ──
  Future<void> _startJob() async {
    setState(() => _isStartingJob = true);

    try {
      final supabase = Supabase.instance.client;

      // Look up the internal user ID (users.id) from the auth UUID.
      // The start_job() RPC expects users.id, NOT auth.users.id.
      final userRow = await supabase
          .from('users')
          .select('id')
          .eq('auth_id', supabase.auth.currentUser!.id)
          .single();

      final result = await supabase.rpc('start_job', params: {
        'p_request_id': _job.requestId,
        'p_cleaner_id': userRow['id'],
      });

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

      // 2. Complete the job via direct RPC call
      final supabase = Supabase.instance.client;
      final userRow = await supabase
          .from('users')
          .select('id')
          .eq('auth_id', supabase.auth.currentUser!.id)
          .single();

      final result = await supabase.rpc('complete_job', params: {
        'p_request_id': _job.requestId,
        'p_cleaner_id': userRow['id'],
      });

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
    // Confirm with the cleaner first
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.lock_outline, color: Color(0xFFFF6B6B), size: 28),
            SizedBox(width: 12),
            Text('Room Locked?', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: const Text(
          'You\'ll need to take a photo of the locked door as proof. '
          'The student will be notified that their request was cancelled.',
          style: TextStyle(color: Color(0xFFCDD6F4), fontSize: 15),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Go Back', style: TextStyle(color: Color(0xFF6C7086))),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.camera_alt, size: 18),
            label: const Text('Take Photo'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF6B6B),
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
      final supabase = Supabase.instance.client;

      // 1. Look up internal user ID
      final userRow = await supabase
          .from('users')
          .select('id')
          .eq('auth_id', supabase.auth.currentUser!.id)
          .single();

      // 2. Upload proof photo to Supabase Storage
      final fileName = '${_job.requestId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final filePath = 'locked-proofs/$fileName';
      final photoBytes = await photo.readAsBytes();

      await supabase.storage
          .from('proof-photos')
          .uploadBinary(filePath, photoBytes, fileOptions: const FileOptions(
            contentType: 'image/jpeg',
            upsert: false,
          ));

      final publicUrl = supabase.storage
          .from('proof-photos')
          .getPublicUrl(filePath);

      // 3. Call the RPC function to cancel the request
      final result = await supabase.rpc(
        'report_room_locked',
        params: {
          'p_request_id': _job.requestId,
          'p_cleaner_id': userRow['id'],
          'p_failure_reason': 'room_locked',
          'p_proof_url': publicUrl,
        },
      );

      if (result['success'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Report submitted. Student notified.',
                  style: TextStyle(color: Color(0xFF1E1E2E), fontWeight: FontWeight.w600)),
              backgroundColor: const Color(0xFFFAB387),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
          Navigator.of(context).pop();
        }
      } else {
        // Clean up uploaded photo on failure
        await supabase.storage.from('proof-photos').remove([filePath]);
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
        backgroundColor: const Color(0xFFFF6B6B),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
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
                    const Color(0xFFA6E3A1).withValues(alpha: 0.3),
                    const Color(0xFFA6E3A1).withValues(alpha: 0.1),
                  ],
                ),
              ),
              child: const Icon(
                Icons.check_circle_rounded,
                color: Color(0xFFA6E3A1),
                size: 56,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Job Completed! 🎉',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Room ${_job.roomLabel} has been cleaned successfully.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFFCDD6F4), fontSize: 15),
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
                  backgroundColor: const Color(0xFFA6E3A1),
                  foregroundColor: const Color(0xFF1E1E2E),
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

    return Scaffold(
      backgroundColor: const Color(0xFF11111B),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E2E),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Color(0xFFCDD6F4)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Active Job',
          style: TextStyle(
            color: Colors.white,
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
              backgroundColor: _statusColor,
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
                _buildRoomHeader(),
                const SizedBox(height: 24),

                // ── Task Cards ──
                _buildSectionTitle('Tasks'),
                const SizedBox(height: 12),
                _buildTaskCards(),
                const SizedBox(height: 24),

                // ── Student Notes ──
                if (_job.notes != null && _job.notes!.isNotEmpty) ...[
                  _buildSectionTitle('Note from Student'),
                  const SizedBox(height: 12),
                  _buildNotesCard(),
                  const SizedBox(height: 24),
                ],

                // ── Student Info ──
                _buildSectionTitle('Student'),
                const SizedBox(height: 12),
                _buildStudentInfoCard(),
              ],
            ),
          ),

          // ── Bottom Action Buttons ──
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildActionButtons(),
          ),

          // ── Loading Overlay ──
          if (_isLoading)
            Container(
              color: Colors.black54,
              child: const Center(
                child: CircularProgressIndicator(
                  color: Color(0xFF89B4FA),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Color get _statusColor {
    switch (_job.status) {
      case 'ASSIGNED':
        return const Color(0xFF89B4FA);
      case 'IN_PROGRESS':
        return const Color(0xFFFAB387);
      case 'COMPLETED':
        return const Color(0xFFA6E3A1);
      default:
        return const Color(0xFF6C7086);
    }
  }

  Widget _buildRoomHeader() {
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
                    const Color(0xFFFF6B6B).withValues(alpha: 0.25),
                    const Color(0xFFEE5A24).withValues(alpha: 0.15),
                  ]
                : [
                    const Color(0xFF89B4FA).withValues(alpha: 0.15),
                    const Color(0xFFCBA6F7).withValues(alpha: 0.1),
                  ],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _job.isUrgent
                ? const Color(0xFFFF6B6B).withValues(alpha: 0.4)
                : const Color(0xFF89B4FA).withValues(alpha: 0.2),
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
                  color: const Color(0xFFFF6B6B),
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
                color: _job.isUrgent
                    ? const Color(0xFFFF6B6B)
                    : const Color(0xFF89B4FA),
              ),
            ),
            const SizedBox(height: 16),

            // Room label
            Text(
              'Room ${_job.roomLabel}',
              style: const TextStyle(
                color: Colors.white,
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

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: Color(0xFF6C7086),
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.1,
      ),
    );
  }

  Widget _buildTaskCards() {
    return Row(
      children: [
        if (_job.isSweeping)
          Expanded(child: _taskChip('Floor Sweeping', Icons.cleaning_services_rounded)),
        if (_job.isSweeping && _job.isMopping) const SizedBox(width: 12),
        if (_job.isMopping)
          Expanded(child: _taskChip('Wet Mopping', Icons.water_drop_rounded)),
      ],
    );
  }

  Widget _taskChip(String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF313244), width: 1),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: const Color(0xFF89DCEB), size: 22),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotesCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF313244), width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.sticky_note_2_rounded,
            color: Color(0xFFF9E2AF),
            size: 22,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              _job.notes!,
              style: const TextStyle(
                color: Color(0xFFCDD6F4),
                fontSize: 15,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStudentInfoCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF313244), width: 1),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: const Color(0xFFCBA6F7).withValues(alpha: 0.2),
            child: Text(
              _job.studentName.isNotEmpty ? _job.studentName[0].toUpperCase() : '?',
              style: const TextStyle(
                color: Color(0xFFCBA6F7),
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
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Room ${_job.roomLabel}',
                  style: const TextStyle(
                    color: Color(0xFF6C7086),
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

  Widget _buildActionButtons() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
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
                  backgroundColor: const Color(0xFF89B4FA),
                  foregroundColor: const Color(0xFF1E1E2E),
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
                  backgroundColor: const Color(0xFFA6E3A1),
                  foregroundColor: const Color(0xFF1E1E2E),
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
                  foregroundColor: const Color(0xFF6C7086),
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
                  color: const Color(0xFFA6E3A1).withValues(alpha: 0.7),
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
