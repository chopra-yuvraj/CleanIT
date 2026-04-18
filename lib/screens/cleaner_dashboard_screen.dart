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
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_theme.dart';
import '../models/models.dart';
import '../services/services.dart';
import 'cleaner_job_details.dart';
import 'auth_screen.dart';

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

  RealtimeChannel? _broadcastChannel;
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
    _subscribeToNewRequests();

    // ── Auto-poll every 5 seconds for seamless data sync ──
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted && _isOnDuty) _pollRefresh();
    });
  }

  @override
  void dispose() {
    _radarController.dispose();
    _broadcastChannel?.unsubscribe();
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      _profile = _auth.currentProfile ?? await _auth.fetchProfile();
      _isOnDuty = _profile?.isOnDuty ?? true;
      _openRequests = await _requestService.fetchOpenRequests();
      _myJobs = await _requestService.fetchCleanerJobs(_profile!.id);
    } catch (e) {
      debugPrint('Error loading cleaner data: $e');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  /// Silent poll refresh — no loading spinner, just updates data.
  Future<void> _pollRefresh() async {
    try {
      if (_profile == null) return;
      final openRequests = await _requestService.fetchOpenRequests();
      final myJobs = await _requestService.fetchCleanerJobs(_profile!.id);
      if (mounted) {
        setState(() {
          _openRequests = openRequests;
          _myJobs = myJobs;
        });
      }
    } catch (e) {
      debugPrint('Poll refresh error: $e');
    }
  }

  void _subscribeToNewRequests() {
    _broadcastChannel = _requestService.subscribeToNewRequests((request) {
      if (!mounted || !_isOnDuty) return;

      // Add to open requests list
      setState(() {
        _openRequests.insert(0, request);
      });

      // Show the broadcast pop-up modal
      _showBroadcastPopup(request);
    });
  }

  Future<void> _toggleOnDuty(bool value) async {
    setState(() => _isOnDuty = value);
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
        // Remove from open list, add to my jobs
        setState(() {
          _openRequests.removeWhere((r) => r.id == request.id);
        });
        await _loadData(); // Refresh to get updated lists

        // Navigate to job details
        if (!mounted) return;
        _navigateToJobDetails(request);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? 'Request already taken.'),
            backgroundColor: AppTheme.peach,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
        // Refresh to remove the taken request
        _loadData();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.red),
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
        return AlertDialog(
          backgroundColor: AppTheme.base,
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
                    color: AppTheme.red,
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
                      ? AppTheme.red.withValues(alpha: 0.15)
                      : AppTheme.blue.withValues(alpha: 0.15),
                ),
                child: Icon(Icons.meeting_room_rounded,
                    color: request.isUrgent ? AppTheme.red : AppTheme.blue,
                    size: 28),
              ),
              const SizedBox(height: 14),
              Text(
                'New Request',
                style: GoogleFonts.outfit(
                    fontSize: 13,
                    color: AppTheme.overlay0,
                    fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                'Room ${request.roomLabel}',
                style: GoogleFonts.outfit(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: Colors.white),
              ),
              const SizedBox(height: 12),

              // Tasks
              Text(request.tasksSummary,
                  style: const TextStyle(color: AppTheme.teal, fontSize: 15)),
              const SizedBox(height: 8),

              // Notes
              if (request.notes != null && request.notes!.isNotEmpty) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.surface0.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.sticky_note_2,
                          color: AppTheme.yellow, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(request.notes!,
                            style: const TextStyle(
                                color: AppTheme.subtext0, fontSize: 13)),
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
                    backgroundColor: AppTheme.green,
                    foregroundColor: AppTheme.crust,
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
                  child: const Text('Decline',
                      style: TextStyle(color: AppTheme.overlay0, fontSize: 15)),
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
    return Scaffold(
      backgroundColor: AppTheme.crust,
      appBar: AppBar(
        backgroundColor: AppTheme.base,
        title: Row(
          children: [
            const Icon(Icons.cleaning_services_rounded,
                color: AppTheme.green, size: 24),
            const SizedBox(width: 10),
            Text('CleanIT',
                style: GoogleFonts.outfit(
                    fontWeight: FontWeight.w800, color: Colors.white)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppTheme.surface0,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text('Cleaner',
                  style: GoogleFonts.outfit(
                      fontSize: 11,
                      color: AppTheme.subtext0,
                      fontWeight: FontWeight.w600)),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppTheme.text),
            onPressed: _loadData,
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: AppTheme.overlay0),
            onPressed: _signOut,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.green))
          : RefreshIndicator(
              onRefresh: _loadData,
              color: AppTheme.green,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
                children: [
                  // ── On Duty Toggle ──
                  _buildOnDutyToggle(),
                  const SizedBox(height: 24),

                  // ── My Active Jobs ──
                  if (_myJobs.isNotEmpty) ...[
                    _buildSectionTitle('My Active Jobs'),
                    const SizedBox(height: 14),
                    ..._myJobs.map(_buildActiveJobCard),
                    const SizedBox(height: 24),
                  ],

                  // ── Open Requests (Live Radar) ──
                  _buildSectionTitle('Open Requests'),
                  const SizedBox(height: 14),
                  if (_openRequests.isEmpty)
                    _buildEmptyRadar()
                  else
                    ..._openRequests.map(_buildOpenRequestCard),
                ],
              ),
            ),
    );
  }

  Widget _buildOnDutyToggle() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: _isOnDuty
            ? AppTheme.green.withValues(alpha: 0.1)
            : AppTheme.base,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _isOnDuty ? AppTheme.green.withValues(alpha: 0.3) : AppTheme.surface0,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _isOnDuty ? AppTheme.green : AppTheme.overlay0,
              boxShadow: _isOnDuty
                  ? [
                      BoxShadow(
                          color: AppTheme.green.withValues(alpha: 0.5),
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
                    color: _isOnDuty ? AppTheme.green : AppTheme.overlay0,
                  ),
                ),
                Text(
                  _isOnDuty
                      ? 'Receiving new cleaning requests'
                      : 'Not receiving requests',
                  style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.overlay0.withValues(alpha: 0.8)),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: _isOnDuty,
            onChanged: _toggleOnDuty,
            activeThumbColor: AppTheme.green,
            activeTrackColor: AppTheme.green.withValues(alpha: 0.3),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title.toUpperCase(),
      style: GoogleFonts.outfit(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppTheme.overlay0,
        letterSpacing: 1.1,
      ),
    );
  }

  Widget _buildActiveJobCard(CleaningRequest r) {
    return GestureDetector(
      onTap: () => _navigateToJobDetails(r),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppTheme.green.withValues(alpha: 0.1),
              AppTheme.teal.withValues(alpha: 0.05),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.green.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.green.withValues(alpha: 0.15),
              ),
              child: const Icon(Icons.meeting_room_rounded,
                  color: AppTheme.green, size: 22),
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
                          color: Colors.white)),
                  const SizedBox(height: 3),
                  Text(r.tasksSummary,
                      style: const TextStyle(
                          color: AppTheme.subtext0, fontSize: 13)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: r.status == RequestStatus.inProgress
                    ? AppTheme.peach
                    : AppTheme.teal,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                r.status.displayLabel,
                style: const TextStyle(
                    color: AppTheme.crust,
                    fontSize: 11,
                    fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOpenRequestCard(CleaningRequest r) {
    final isAccepting = _acceptingRequestId == r.id;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.base,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: r.isUrgent
              ? AppTheme.red.withValues(alpha: 0.4)
              : AppTheme.surface0,
          width: r.isUrgent ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Room label
              Text('Room ${r.roomLabel}',
                  style: GoogleFonts.outfit(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: Colors.white)),
              const Spacer(),
              if (r.isUrgent)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.red,
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
              style: const TextStyle(color: AppTheme.teal, fontSize: 14)),
          if (r.notes != null && r.notes!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(r.notes!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppTheme.subtext0, fontSize: 13)),
          ],
          const SizedBox(height: 14),

          // Accept button
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton.icon(
              onPressed: isAccepting ? null : () => _acceptRequest(r),
              icon: isAccepting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppTheme.crust))
                  : const Icon(Icons.check_rounded, size: 20),
              label: Text(isAccepting ? 'Accepting...' : 'Accept',
                  style: GoogleFonts.outfit(
                      fontSize: 15, fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.green,
                foregroundColor: AppTheme.crust,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyRadar() {
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
                    color: AppTheme.green
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
                      color: AppTheme.green.withValues(alpha: 0.1),
                    ),
                    child:
                        const Icon(Icons.radar, color: AppTheme.green, size: 24),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          Text('Scanning for requests...',
              style: GoogleFonts.outfit(color: AppTheme.overlay0, fontSize: 15)),
          const SizedBox(height: 4),
          const Text('New requests will pop up here',
              style: TextStyle(color: AppTheme.surface1, fontSize: 13)),
        ],
      ),
    );
  }
}
