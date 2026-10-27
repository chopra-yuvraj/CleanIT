// CleanIT — Cleaner Performance & Profile Screen
//
// Implements Feature 1.5: Cleaner Performance Summary
//
// Calls GET /api/analytics/cleaner-summary/:id
// Displays KPI cards/metrics for:
// - Total Jobs
// - Completed Jobs
// - Cancelled Jobs
// - Average Completion Time
// - Average Rating
// - Busiest Day of the Week

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../config/app_theme.dart';
import '../config/theme_notifier.dart';
import '../models/models.dart';
import '../services/services.dart';

class CleanerPerformanceScreen extends StatefulWidget {
  final String? cleanerId;
  final String? cleanerName;

  const CleanerPerformanceScreen({
    super.key,
    this.cleanerId,
    this.cleanerName,
  });

  @override
  State<CleanerPerformanceScreen> createState() => _CleanerPerformanceScreenState();
}

class _CleanerPerformanceScreenState extends State<CleanerPerformanceScreen> {
  final _analytics = AnalyticsService.instance;
  final _auth = AuthService.instance;

  CleanerSummary? _summary;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchSummary();
  }

  Future<void> _fetchSummary() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final targetId = widget.cleanerId ?? _auth.currentProfile?.id;
      if (targetId == null) {
        setState(() {
          _errorMessage = 'No cleaner selected';
          _isLoading = false;
        });
        return;
      }

      final summary = await _analytics.fetchCleanerSummary(targetId);
      if (mounted) {
        setState(() {
          _summary = summary;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load cleaner performance: $e';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final cleanerName = _summary?.cleanerName ?? widget.cleanerName ?? 'Cleaner Performance';

    return Scaffold(
      backgroundColor: c.crust,
      appBar: AppBar(
        backgroundColor: c.base,
        title: Text(
          cleanerName,
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.w700,
            color: c.text,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh_rounded, color: c.subtext0),
            onPressed: _fetchSummary,
            tooltip: 'Refresh metrics',
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
                  themeNotifier.value = themeNotifier.value == ThemeMode.dark
                      ? ThemeMode.light
                      : ThemeMode.dark;
                },
              );
            },
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: c.teal))
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline_rounded, color: c.red, size: 48),
                        const SizedBox(height: 16),
                        Text(
                          _errorMessage!,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: c.subtext0, fontSize: 14),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: _fetchSummary,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Try Again'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: c.teal,
                            foregroundColor: c.crust,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : _buildContent(c),
    );
  }

  Widget _buildContent(ThemeColors c) {
    final s = _summary!;

    return RefreshIndicator(
      onRefresh: _fetchSummary,
      color: c.teal,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // ── Header Card ──
          _buildHeaderCard(s, c),
          const SizedBox(height: 24),

          // ── Section Title ──
          Row(
            children: [
              Icon(Icons.insights_rounded, color: c.teal, size: 22),
              const SizedBox(width: 10),
              Text(
                'Performance Metrics',
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: c.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Aggregated via MongoDB pipeline: \$match + \$group + \$cond + \$lookup',
            style: GoogleFonts.outfit(fontSize: 12, color: c.overlay0),
          ),
          const SizedBox(height: 16),

          // ── 6 KPI Metric Cards Grid ──
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
            childAspectRatio: 1.35,
            children: [
              _metricCard(
                label: 'Total Jobs',
                value: '${s.totalJobs}',
                icon: Icons.work_outline_rounded,
                color: c.blue,
                c: c,
              ),
              _metricCard(
                label: 'Completed Jobs',
                value: '${s.completedJobs}',
                icon: Icons.check_circle_rounded,
                color: c.green,
                c: c,
              ),
              _metricCard(
                label: 'Cancelled Jobs',
                value: '${s.cancelledJobs}',
                icon: Icons.cancel_outlined,
                color: c.red,
                subtitle: 'Room Locked',
                c: c,
              ),
              _metricCard(
                label: 'Avg Completion',
                value: s.completedJobs > 0 ? '${s.avgCompletionMinutes.toStringAsFixed(0)}m' : 'N/A',
                icon: Icons.timer_rounded,
                color: c.yellow,
                subtitle: 'Accept → Finish',
                c: c,
              ),
              _metricCard(
                label: 'Average Rating',
                value: s.avgRating != null ? '${s.avgRating!.toStringAsFixed(1)} ★' : 'No ratings',
                icon: Icons.star_rounded,
                color: c.peach,
                subtitle: '${s.totalRatings} student reviews',
                c: c,
              ),
              _metricCard(
                label: 'Busiest Day',
                value: s.busiestDayName ?? 'None yet',
                icon: Icons.calendar_today_rounded,
                color: c.mauve,
                subtitle: s.busiestDayCount > 0 ? '${s.busiestDayCount} jobs finished' : null,
                c: c,
              ),
            ],
          ),
          const SizedBox(height: 24),

          // ── Aggregation Pipeline Architecture Box ──
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: c.base,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: c.surface0),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.data_object_rounded, color: c.teal, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'MongoDB Query Architecture',
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: c.text,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'Endpoint: GET /api/analytics/cleaner-summary/:id\n'
                  '• \$match: { "assignment.cleanerId": ObjectId, isDeleted: { \$ne: true } }\n'
                  '• \$group: totalJobs, completedJobs (\$cond), avgCompletionMs (\$subtract completedAt - assignedAt)\n'
                  '• \$lookup: Cross-collection join with feedbacks collection to compute average rating\n'
                  '• \$dayOfWeek: Groups by day of week to determine the peak work schedule',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: c.subtext0,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderCard(CleanerSummary s, ThemeColors c) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: c.base,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.teal.withValues(alpha: 0.3)),
        gradient: LinearGradient(
          colors: [
            c.teal.withValues(alpha: 0.08),
            c.base,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: c.teal.withValues(alpha: 0.15),
              border: Border.all(color: c.teal, width: 2),
            ),
            child: Center(
              child: Icon(Icons.person_outline_rounded, color: c.teal, size: 30),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.cleanerName,
                  style: GoogleFonts.outfit(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: c.text,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: s.isOnDuty ? c.green : c.surface1,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      s.isOnDuty ? 'On Duty' : 'Off Duty',
                      style: TextStyle(
                        fontSize: 12,
                        color: s.isOnDuty ? c.green : c.overlay0,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text('·', style: TextStyle(color: c.overlay0)),
                    const SizedBox(width: 12),
                    Text(
                      '${s.completedJobs} / ${s.totalJobs} completed',
                      style: TextStyle(fontSize: 12, color: c.subtext0),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricCard({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
    String? subtitle,
    required ThemeColors c,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.base,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: c.subtext0,
                ),
              ),
              Icon(icon, color: color, size: 20),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: GoogleFonts.outfit(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: c.text,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 10, color: c.overlay0),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
