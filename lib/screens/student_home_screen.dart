// CleanIT — Student Home Screen
//
// Main dashboard for students with:
// - "Request Room Cleaning" hero button
// - Alert banner for failed/cancelled requests
// - Active job card (if a request is in progress)
// - Recent request history

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../config/app_theme.dart';
import '../config/theme_notifier.dart';
import '../models/models.dart';
import '../services/services.dart';
import 'new_request_screen.dart';
import 'active_job_screen.dart';
import 'auth_screen.dart';

class StudentHomeScreen extends StatefulWidget {
  const StudentHomeScreen({super.key});

  @override
  State<StudentHomeScreen> createState() => _StudentHomeScreenState();
}

class _StudentHomeScreenState extends State<StudentHomeScreen> {
  final _auth = AuthService.instance;
  final _requestService = RequestService.instance;

  AppUser? _profile;
  CleaningRequest? _activeRequest;
  List<CleaningRequest> _history = [];
  bool _isLoading = true;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _loadData();

    // ── Auto-poll every 5 seconds for seamless status updates ──
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) _pollRefresh();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      _profile = _auth.currentProfile ?? await _auth.fetchProfile();
      _activeRequest =
          await _requestService.fetchActiveStudentRequest(_profile!.id);
      _history = await _requestService.fetchStudentRequests(_profile!.id);
    } catch (e) {
      debugPrint('Error loading data: $e');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  /// Silent poll refresh — no loading spinner, just updates data.
  Future<void> _pollRefresh() async {
    try {
      if (_profile == null) return;
      final activeRequest =
          await _requestService.fetchActiveStudentRequest(_profile!.id);
      final history = await _requestService.fetchStudentRequests(_profile!.id);
      if (mounted) {
        setState(() {
          _activeRequest = activeRequest;
          _history = history;
        });
      }
    } catch (e) {
      debugPrint('Poll refresh error: $e');
    }
  }

  CleaningRequest? get _lastCancelledRequest {
    try {
      return _history.firstWhere(
        (r) => r.status == RequestStatus.cancelledRoomLocked,
      );
    } catch (_) {
      return null;
    }
  }

  void _navigateToNewRequest() async {
    if (_activeRequest != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You already have an active request.'),
          backgroundColor: AppTheme.peach,
        ),
      );
      return;
    }

    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const NewRequestScreen()),
    );

    if (result == true) _loadData();
  }

  void _navigateToActiveJob() {
    if (_activeRequest == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ActiveJobScreen(request: _activeRequest!),
      ),
    ).then((_) => _loadData());
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
            Icon(Icons.cleaning_services_rounded, color: c.blue, size: 24),
            const SizedBox(width: 10),
            Text('CleanIT',
                style: GoogleFonts.outfit(
                    fontWeight: FontWeight.w800, color: c.text)),
          ],
        ),
        actions: [
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
              child: CircularProgressIndicator(color: c.blue))
          : RefreshIndicator(
              onRefresh: _loadData,
              color: c.blue,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
                children: [
                  // ── Greeting ──
                  _buildGreeting(c),
                  const SizedBox(height: 20),

                  // ── Alert Banner (last cancelled request) ──
                  if (_lastCancelledRequest != null) ...[
                    _buildAlertBanner(c),
                    const SizedBox(height: 20),
                  ],

                  // ── Active Request Card ──
                  if (_activeRequest != null) ...[
                    _buildActiveRequestCard(c),
                    const SizedBox(height: 24),
                  ],

                  // ── Hero Button ──
                  _buildHeroButton(c),
                  const SizedBox(height: 32),

                  // ── Recent History ──
                  _buildSectionTitle('Recent History', c),
                  const SizedBox(height: 14),
                  if (_history.isEmpty)
                    _buildEmptyState(c)
                  else
                    ..._history
                        .where((r) => !r.status.isActive)
                        .take(10)
                        .map((r) => _buildHistoryCard(r, c)),
                ],
              ),
            ),
    );
  }

  Widget _buildGreeting(ThemeColors c) {
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 17
            ? 'Good afternoon'
            : 'Good evening';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          greeting,
          style: GoogleFonts.outfit(
            fontSize: 15,
            color: c.overlay0,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _profile?.name ?? 'Student',
          style: GoogleFonts.outfit(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: c.text,
          ),
        ),
        if (_profile?.roomLabel != null)
          Text(
            'Room ${_profile!.roomLabel}',
            style: GoogleFonts.outfit(
              fontSize: 14,
              color: c.subtext0,
            ),
          ),
      ],
    );
  }

  Widget _buildAlertBanner(ThemeColors c) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            c.red.withValues(alpha: 0.15),
            c.red.withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.red.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: c.red.withValues(alpha: 0.2),
            ),
            child: Icon(Icons.warning_amber_rounded,
                color: c.red, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Last request cancelled',
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: c.red,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Your cleaner arrived, but your room was locked.',
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    color: c.text.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveRequestCard(ThemeColors c) {
    final r = _activeRequest!;
    return GestureDetector(
      onTap: _navigateToActiveJob,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              c.blue.withValues(alpha: 0.15),
              c.mauve.withValues(alpha: 0.1),
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: c.blue.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _statusColor(r.status, c),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    r.status.displayLabel,
                    style: GoogleFonts.outfit(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: c.crust),
                  ),
                ),
                const Spacer(),
                Icon(Icons.arrow_forward_ios_rounded,
                    color: c.overlay0, size: 16),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              'Active Request',
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: c.text,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              r.tasksSummary,
              style: TextStyle(color: c.subtext0, fontSize: 14),
            ),
            if (r.cleanerName != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.person, color: c.green, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    'Cleaner: ${r.cleanerName}',
                    style: TextStyle(color: c.green, fontSize: 13),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeroButton(ThemeColors c) {
    final hasActive = _activeRequest != null;
    return GestureDetector(
      onTap: hasActive ? _navigateToActiveJob : _navigateToNewRequest,
      child: Container(
        height: 140,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: hasActive
                ? [
                    c.green.withValues(alpha: 0.2),
                    c.teal.withValues(alpha: 0.1),
                  ]
                : [
                    c.blue.withValues(alpha: 0.25),
                    c.mauve.withValues(alpha: 0.15),
                  ],
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: hasActive
                ? c.green.withValues(alpha: 0.3)
                : c.blue.withValues(alpha: 0.3),
            width: 1.5,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                hasActive
                    ? Icons.qr_code_2_rounded
                    : Icons.add_circle_rounded,
                size: 44,
                color: hasActive ? c.green : c.blue,
              ),
              const SizedBox(height: 12),
              Text(
                hasActive
                    ? 'View Active Job'
                    : 'Request Room Cleaning',
                style: GoogleFonts.outfit(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  color: c.text,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title, ThemeColors c) {
    return Text(
      title,
      style: GoogleFonts.outfit(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: c.overlay0,
        letterSpacing: 1.1,
      ),
    );
  }

  Widget _buildEmptyState(ThemeColors c) {
    return Container(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Icon(Icons.inbox_rounded, size: 48, color: c.surface1),
          const SizedBox(height: 12),
          Text(
            'No cleaning requests yet',
            style: GoogleFonts.outfit(color: c.overlay0, fontSize: 15),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryCard(CleaningRequest r, ThemeColors c) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.base,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.surface0),
      ),
      child: Row(
        children: [
          // Status icon
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _statusColor(r.status, c).withValues(alpha: 0.15),
            ),
            child: Icon(
              r.status == RequestStatus.completed
                  ? Icons.check_circle_rounded
                  : Icons.cancel_rounded,
              color: _statusColor(r.status, c),
              size: 20,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.tasksSummary,
                  style: GoogleFonts.outfit(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: c.text,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  r.status.displayLabel,
                  style: TextStyle(
                    fontSize: 12,
                    color: _statusColor(r.status, c),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          // Time
          Text(
            _timeAgo(r.createdAt),
            style: TextStyle(color: c.overlay0, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Color _statusColor(RequestStatus status, ThemeColors c) {
    switch (status) {
      case RequestStatus.open:
        return c.blue;
      case RequestStatus.assigned:
        return c.teal;
      case RequestStatus.inProgress:
        return c.peach;
      case RequestStatus.completed:
        return c.green;
      case RequestStatus.cancelledRoomLocked:
        return c.red;
    }
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
