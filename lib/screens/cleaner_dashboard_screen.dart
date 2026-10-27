// CleanIT — Cleaner Dashboard Screen
//
// Live radar for cleaners showing:
// - On-duty toggle
// - Incoming broadcast pop-up modals for new requests
// - Active jobs queue
// - Accept/decline real-time interactions
// - Navigation to job details

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/app_theme.dart';
import '../config/theme_notifier.dart';
import '../models/models.dart';
import '../services/services.dart';
import 'cleaner_job_details.dart';
import 'auth_screen.dart';
import 'cleaner_performance_screen.dart';
import 'profile_settings_screen.dart';

class CleanerDashboardScreen extends StatefulWidget {
  const CleanerDashboardScreen({super.key});

  @override
  State<CleanerDashboardScreen> createState() => _CleanerDashboardScreenState();
}

class _CleanerDashboardScreenState extends State<CleanerDashboardScreen>
    with TickerProviderStateMixin {
  final _auth = AuthService.instance;
  final _requestService = RequestService.instance;

  AppUser? _profile;
  List<CleaningRequest> _openRequests = [];
  List<CleaningRequest> _myJobs = [];
  bool _isLoading = true;
  bool _isOnDuty = true;
  String? _acceptingRequestId; // Which request is currently being accepted

  late AnimationController _radarController;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _radarController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
    _loadData();

    // ── Auto-poll every 5 seconds for seamless data sync ──
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted && _isOnDuty) _pollRefresh();
    });
  }

  @override
  void dispose() {
    _radarController.dispose();
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      _profile = _auth.currentProfile ?? await _auth.fetchProfile();
      _isOnDuty = _profile?.isOnDuty ?? true;
      final openRequests = await _requestService.fetchOpenRequests();
      // Ensure urgent first, then oldest
      openRequests.sort((a, b) {
        if (a.isUrgent != b.isUrgent) return a.isUrgent ? -1 : 1;
        return a.createdAt.compareTo(b.createdAt);
      });
      _openRequests = openRequests;
      _myJobs = await _requestService.fetchCleanerJobs(_profile!.id);
    } catch (e) {
      debugPrint('Error loading cleaner data: $e');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  /// Silent poll refresh — no loading spinner, just updates data.
  /// Also detects new requests and shows the broadcast popup.
  Future<void> _pollRefresh() async {
    try {
      if (_profile == null) return;
      final openRequests = await _requestService.fetchOpenRequests();
      openRequests.sort((a, b) {
        if (a.isUrgent != b.isUrgent) return a.isUrgent ? -1 : 1;
        return a.createdAt.compareTo(b.createdAt);
      });
      final myJobs = await _requestService.fetchCleanerJobs(_profile!.id);

      if (!mounted) return;

      // Detect genuinely new requests (IDs we haven't seen before)
      final oldIds = _openRequests.map((r) => r.id).toSet();
      final newRequests = openRequests
          .where((r) => !oldIds.contains(r.id))
          .toList();

      setState(() {
        _openRequests = openRequests;
        _myJobs = myJobs;
      });

      // Show broadcast popup for the first new request
      if (newRequests.isNotEmpty && _isOnDuty) {
        SoundService.instance.play(AppSound.requestReceived);
        _showBroadcastPopup(newRequests.first);
      }
    } catch (e) {
      debugPrint('Poll refresh error: $e');
    }
  }

  /// Feature 1.3: Report room locked directly from accepted job card
  Future<void> _confirmReportRoomLocked(CleaningRequest r) async {
    final c = AppTheme.of(context);
    final reasonController = TextEditingController(text: 'room_locked');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.base,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.lock_rounded, color: c.red, size: 26),
            const SizedBox(width: 10),
            Text('Report Room Locked?',
                style: TextStyle(color: c.text, fontSize: 18, fontWeight: FontWeight.w700)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Confirm that Room ${r.roomLabel} is locked. The request will be cancelled and the student notified.',
              style: TextStyle(color: c.subtext0, fontSize: 14),
            ),
            const SizedBox(height: 12),
            Text('Failure Reason:',
                style: TextStyle(color: c.text, fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            TextField(
              controller: reasonController,
              style: TextStyle(color: c.text),
              decoration: InputDecoration(
                hintText: 'e.g. room_locked, student not in room',
                hintStyle: TextStyle(color: c.surface1),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Go Back', style: TextStyle(color: c.overlay0)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: c.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Confirm & Cancel'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final res = await _requestService.reportRoomLocked(
        requestId: r.id,
        photoPath: '',
        failureReason: reasonController.text.trim().isNotEmpty
            ? reasonController.text.trim()
            : 'room_locked',
      );

      if (!mounted) return;

      if (res['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Job marked CANCELLED_ROOM_LOCKED and student notified.',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            backgroundColor: c.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
        _loadData();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res['message'] ?? 'Could not report room locked.'),
            backgroundColor: c.peach,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: c.red),
        );
      }
    }
  }



  Future<void> _toggleOnDuty(bool value) async {
    setState(() {
      _isOnDuty = value;
      if (!value) {
        _openRequests.clear();
      }
    });
    try {
      await _auth.toggleOnDuty(value);
    } catch (e) {
      debugPrint('Error toggling duty: $e');
    }
  }

  Future<void> _acceptRequest(CleaningRequest request) async {
    setState(() => _acceptingRequestId = request.id);

    try {
      final result = await _requestService.acceptRequest(request.id);

      if (!mounted) return;

      if (result['success'] == true) {
        setState(() {
          _openRequests.removeWhere((r) => r.id == request.id);
        });
        await _loadData();

        if (!mounted) return;
        _navigateToJobDetails(request);
      } else {
        SoundService.instance.play(AppSound.error);
        final code = result['code'] as String?;
        String message;
        switch (code) {
          case 'ALREADY_ASSIGNED':
            message = 'This request was already picked up by another cleaner.';
            break;
          case 'REQUEST_NOT_FOUND':
            message = 'This request is no longer available.';
            break;
          default:
            message = result['message'] ?? 'Could not accept this request. Please try another.';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message,
                style: const TextStyle(color: Color(0xFF1E1E2E), fontWeight: FontWeight.w600)),
            backgroundColor: AppTheme.peach,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
        _loadData();
      }
    } catch (e) {
      if (!mounted) return;
      SoundService.instance.play(AppSound.error);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Connection error. Please check your internet and try again.',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
          backgroundColor: AppTheme.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } finally {
      if (mounted) setState(() => _acceptingRequestId = null);
    }
  }

  void _navigateToJobDetails(CleaningRequest request) {
    final job = CleaningJob(
      requestId: request.id,
      assignmentId: request.assignmentId ?? '',
      roomLabel: request.roomLabel,
      isSweeping: request.isSweeping,
      isMopping: request.isMopping,
      isUrgent: request.isUrgent,
      notes: request.notes,
      studentName: request.studentName ?? 'Student',
      status: request.status.dbValue,
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CleanerJobDetailsScreen(job: job),
      ),
    ).then((_) => _loadData());
  }

  void _showBroadcastPopup(CleaningRequest request) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final c = AppTheme.of(ctx);
        return AlertDialog(
          backgroundColor: c.base,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          contentPadding: const EdgeInsets.all(24),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Urgent badge
              if (request.isUrgent)
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: c.red,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          color: Colors.white, size: 20),
                      SizedBox(width: 8),
                      Text('URGENT REQUEST',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                              letterSpacing: 1)),
                    ],
                  ),
                ),

              // Room info
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: request.isUrgent
                      ? c.red.withValues(alpha: 0.15)
                      : c.blue.withValues(alpha: 0.15),
                ),
                child: Icon(Icons.meeting_room_rounded,
                    color: request.isUrgent ? c.red : c.blue,
                    size: 28),
              ),
              const SizedBox(height: 14),
              Text(
                'New Request',
                style: GoogleFonts.outfit(
                    fontSize: 13,
                    color: c.overlay0,
                    fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                'Room ${request.roomLabel}',
                style: GoogleFonts.outfit(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: c.text),
              ),
              const SizedBox(height: 12),

              // Tasks
              Text(request.tasksSummary,
                  style: TextStyle(color: c.teal, fontSize: 15)),
              const SizedBox(height: 8),

              // Notes
              if (request.notes != null && request.notes!.isNotEmpty) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: c.surface0.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.sticky_note_2,
                          color: c.yellow, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(request.notes!,
                            style: TextStyle(
                                color: c.subtext0, fontSize: 13)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ] else
                const SizedBox(height: 8),

              // Accept button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _acceptRequest(request);
                  },
                  icon: const Icon(Icons.check_rounded, size: 22),
                  label: Text('Accept',
                      style: GoogleFonts.outfit(
                          fontSize: 17, fontWeight: FontWeight.w700)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: c.green,
                    foregroundColor: c.crust,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              const SizedBox(height: 10),

              // Decline button
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('Decline',
                      style: TextStyle(color: c.overlay0, fontSize: 15)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _signOut() async {
    await _auth.signOut();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const AuthScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    return Scaffold(
      backgroundColor: c.crust,
      appBar: AppBar(
        backgroundColor: c.base,
        title: Row(
          children: [
            Icon(Icons.cleaning_services_rounded,
                color: c.green, size: 24),
            const SizedBox(width: 10),
            Text('CleanIT',
                style: GoogleFonts.outfit(
                    fontWeight: FontWeight.w800, color: c.text)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: c.surface0,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text('Cleaner',
                  style: GoogleFonts.outfit(
                      fontSize: 11,
                      color: c.subtext0,
                      fontWeight: FontWeight.w600)),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.insights_rounded, color: c.teal),
            tooltip: 'Cleaner Performance Summary',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CleanerPerformanceScreen(
                    cleanerId: _profile?.id,
                    cleanerName: _profile?.name,
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: Icon(Icons.settings_outlined, color: c.text),
            tooltip: 'Profile & Settings',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProfileSettingsScreen()),
              ).then((_) => _loadData());
            },
          ),
          ValueListenableBuilder<ThemeMode>(
            valueListenable: themeNotifier,
            builder: (context, mode, _) {
              return IconButton(
                icon: Icon(
                  mode == ThemeMode.dark
                      ? Icons.light_mode_rounded
                      : Icons.dark_mode_rounded,
                  color: c.overlay0,
                ),
                tooltip: 'Toggle theme',
                onPressed: () {
                  themeNotifier.value =
                      themeNotifier.value == ThemeMode.dark
                          ? ThemeMode.light
                          : ThemeMode.dark;
                },
              );
            },
          ),
          IconButton(
            icon: Icon(Icons.refresh_rounded, color: c.text),
            onPressed: _loadData,
          ),
          IconButton(
            icon: Icon(Icons.logout_rounded, color: c.overlay0),
            onPressed: _signOut,
          ),
        ],
      ),
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(color: c.green))
          : RefreshIndicator(
              onRefresh: _loadData,
              color: c.green,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
                children: [
                  // ── Performance Quick Card ──
                  InkWell(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CleanerPerformanceScreen(
                            cleanerId: _profile?.id,
                            cleanerName: _profile?.name,
                          ),
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: c.teal.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: c.teal.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.leaderboard_rounded, color: c.teal, size: 22),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'My Performance Summary',
                                  style: GoogleFonts.outfit(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                    color: c.text,
                                  ),
                                ),
                                Text(
                                  'View completion rate, avg time & student ratings',
                                  style: TextStyle(color: c.subtext0, fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right_rounded, color: c.teal, size: 20),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── On Duty Toggle ──
                  _buildOnDutyToggle(c),
                  const SizedBox(height: 24),

                  // ── My Active Jobs ──
                  if (_myJobs.isNotEmpty) ...[
                    _buildSectionTitle('My Active Jobs', c),
                    const SizedBox(height: 14),
                    ..._myJobs.map((r) => _buildActiveJobCard(r, c)),
                    const SizedBox(height: 24),
                  ],

                  // ── Open Requests (Live Radar) ──
                  if (_isOnDuty) ...[
                    _buildSectionTitle('Open Requests', c),
                    const SizedBox(height: 14),
                    if (_openRequests.isEmpty)
                      _buildEmptyRadar(c)
                    else
                      ..._openRequests.map((r) => _buildOpenRequestCard(r, c)),
                  ] else
                    _buildOffDutyState(c),
                ],
              ),
            ),
    );
  }

  Widget _buildOnDutyToggle(ThemeColors c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: _isOnDuty
            ? c.green.withValues(alpha: 0.1)
            : c.base,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _isOnDuty ? c.green.withValues(alpha: 0.3) : c.surface0,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _isOnDuty ? c.green : c.overlay0,
              boxShadow: _isOnDuty
                  ? [
                      BoxShadow(
                          color: c.green.withValues(alpha: 0.5),
                          blurRadius: 8)
                    ]
                  : null,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isOnDuty ? 'On Duty' : 'Off Duty',
                  style: GoogleFonts.outfit(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: _isOnDuty ? c.green : c.overlay0,
                  ),
                ),
                Text(
                  _isOnDuty
                      ? 'Receiving new cleaning requests'
                      : 'Not receiving requests',
                  style: TextStyle(
                      fontSize: 12,
                      color: c.overlay0.withValues(alpha: 0.8)),
                ),
              ],
            ),
          ),
          Switch(
            value: _isOnDuty,
            onChanged: _toggleOnDuty,
            thumbColor: WidgetStateProperty.resolveWith<Color>((states) {
              if (states.contains(WidgetState.selected)) {
                return c.green;
              }
              return Colors.grey;
            }),
            activeTrackColor: c.green.withValues(alpha: 0.3),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, ThemeColors c) {
    return Text(
      title.toUpperCase(),
      style: GoogleFonts.outfit(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: c.overlay0,
        letterSpacing: 1.1,
      ),
    );
  }

  Widget _buildActiveJobCard(CleaningRequest r, ThemeColors c) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            c.green.withValues(alpha: 0.1),
            c.teal.withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.green.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: c.green.withValues(alpha: 0.15),
                ),
                child: Icon(Icons.meeting_room_rounded,
                    color: c.green, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Room ${r.roomLabel}',
                        style: GoogleFonts.outfit(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: c.text)),
                    const SizedBox(height: 3),
                    Text(r.tasksSummary,
                        style: TextStyle(
                            color: c.subtext0, fontSize: 13)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: r.status == RequestStatus.inProgress
                      ? c.peach
                      : c.teal,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  r.status.displayLabel,
                  style: TextStyle(
                      color: c.crust,
                      fontSize: 11,
                      fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              // Feature 1.3: Report Room Locked action button with confirmation dialog
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _confirmReportRoomLocked(r),
                  icon: Icon(Icons.lock_outline_rounded, size: 16, color: c.red),
                  label: Text(
                    'Report Room Locked',
                    style: GoogleFonts.outfit(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: c.red,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: c.red.withValues(alpha: 0.5)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton.icon(
                onPressed: () => _navigateToJobDetails(r),
                icon: const Icon(Icons.qr_code_scanner_rounded, size: 16),
                label: const Text('Open Job'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: c.teal,
                  foregroundColor: c.crust,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOpenRequestCard(CleaningRequest r, ThemeColors c) {
    final isAccepting = _acceptingRequestId == r.id;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: c.base,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: r.isUrgent
              ? c.red.withValues(alpha: 0.5)
              : c.surface0,
          width: r.isUrgent ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Feature 1.2: Pinned Urgent Flag/Badge at top of card
          if (r.isUrgent)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: c.red.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: c.red.withValues(alpha: 0.5)),
              ),
              child: Row(
                children: [
                  Icon(Icons.bolt_rounded, color: c.red, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    '⚡ PINNED URGENT REQUEST — PRIORITY FEED',
                    style: TextStyle(
                      color: c.red,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          Row(
            children: [
              // Room label
              Text('Room ${r.roomLabel}',
                  style: GoogleFonts.outfit(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: c.text)),
              const Spacer(),
              if (r.isUrgent)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: c.red,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('URGENT',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w800)),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(r.tasksSummary,
              style: TextStyle(color: c.teal, fontSize: 14)),
          if (r.notes != null && r.notes!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(r.notes!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: c.subtext0, fontSize: 13)),
          ],
          const SizedBox(height: 14),

          // Accept button
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton.icon(
              onPressed: isAccepting ? null : () => _acceptRequest(r),
              icon: isAccepting
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: c.crust))
                  : const Icon(Icons.check_rounded, size: 20),
              label: Text(isAccepting ? 'Accepting...' : 'Accept',
                  style: GoogleFonts.outfit(
                      fontSize: 15, fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                backgroundColor: c.green,
                foregroundColor: c.crust,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOffDutyState(ThemeColors c) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 64),
      child: Column(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: c.base,
              border: Border.all(color: c.surface0, width: 2),
            ),
            child: Icon(Icons.bedtime_rounded, color: c.overlay0, size: 36),
          ),
          const SizedBox(height: 20),
          Text('You are currently Off Duty',
              style: GoogleFonts.outfit(color: c.text, fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text('Toggle On Duty above to receive new requests.',
              style: TextStyle(color: c.subtext0, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildEmptyRadar(ThemeColors c) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          // Radar animation
          AnimatedBuilder(
            animation: _radarController,
            builder: (context, child) {
              return Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: c.green
                        .withValues(alpha: 1.0 - _radarController.value),
                    width: 2,
                  ),
                ),
                child: Center(
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: c.green.withValues(alpha: 0.1),
                    ),
                    child:
                        Icon(Icons.radar, color: c.green, size: 24),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          Text('Scanning for requests...',
              style: GoogleFonts.outfit(color: c.overlay0, fontSize: 15)),
          const SizedBox(height: 4),
          Text('New requests will pop up here',
              style: TextStyle(color: c.surface1, fontSize: 13)),
        ],
      ),
    );
  }
}
