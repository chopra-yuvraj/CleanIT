// CleanIT — Admin Analytics Dashboard
//
// Showcases MongoDB aggregation pipeline results:
// - Overview stats cards
// - Requests by hostel block
// - Cleaner leaderboard
// - Peak hours distribution
// - Audit log viewer
// - Full-text search demo
// - Database stats

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../config/app_theme.dart';
import '../config/theme_notifier.dart';
import '../models/analytics_model.dart';
import '../services/analytics_service.dart';
import '../services/auth_service.dart';
import 'auth_screen.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen>
    with SingleTickerProviderStateMixin {
  final _analytics = AnalyticsService.instance;
  final _auth = AuthService.instance;

  bool _isLoading = true;
  AnalyticsOverview? _overview;
  List<BlockStat> _blockStats = [];
  List<LeaderboardEntry> _leaderboard = [];
  List<HourlyStat> _peakHours = [];
  List<StatusStat> _statusDist = [];
  List<AuditLogEntry> _auditLogs = [];

  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadAllData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAllData() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        _analytics.fetchOverview(),
        _analytics.fetchByBlock(),
        _analytics.fetchLeaderboard(),
        _analytics.fetchPeakHours(),
        _analytics.fetchStatusDistribution(),
        _analytics.fetchAuditLogs(),
      ]);

      if (mounted) {
        setState(() {
          _overview = results[0] as AnalyticsOverview;
          _blockStats = results[1] as List<BlockStat>;
          _leaderboard = results[2] as List<LeaderboardEntry>;
          _peakHours = results[3] as List<HourlyStat>;
          _statusDist = results[4] as List<StatusStat>;
          _auditLogs = results[5] as List<AuditLogEntry>;
        });
      }
    } catch (e) {
      debugPrint('Analytics load error: $e');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _signOut() async {
    await _auth.signOut();
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const AuthScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.crust,
      appBar: AppBar(
        backgroundColor: AppTheme.base,
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.mauve.withValues(alpha: 0.15),
              ),
              child: const Icon(Icons.analytics_rounded, color: AppTheme.mauve, size: 20),
            ),
            const SizedBox(width: 12),
            Text(
              'Admin Dashboard',
              style: GoogleFonts.outfit(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () {
              themeNotifier.value = themeNotifier.value == ThemeMode.dark
                  ? ThemeMode.light
                  : ThemeMode.dark;
            },
            icon: const Icon(Icons.brightness_6_rounded, color: AppTheme.subtext0),
          ),
          IconButton(
            onPressed: _loadAllData,
            icon: const Icon(Icons.refresh_rounded, color: AppTheme.subtext0),
          ),
          IconButton(
            onPressed: _signOut,
            icon: const Icon(Icons.logout_rounded, color: AppTheme.subtext0),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppTheme.mauve,
          labelColor: AppTheme.mauve,
          unselectedLabelColor: AppTheme.overlay0,
          labelStyle: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 13),
          tabs: const [
            Tab(text: 'Overview', icon: Icon(Icons.dashboard_rounded, size: 18)),
            Tab(text: 'Blocks', icon: Icon(Icons.apartment_rounded, size: 18)),
            Tab(text: 'Cleaners', icon: Icon(Icons.leaderboard_rounded, size: 18)),
            Tab(text: 'Audit Log', icon: Icon(Icons.history_rounded, size: 18)),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.mauve))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildOverviewTab(),
                _buildBlocksTab(),
                _buildCleanersTab(),
                _buildAuditTab(),
              ],
            ),
    );
  }

  // ─────────────────────────────────────────────────────────
  //  Overview Tab
  // ─────────────────────────────────────────────────────────
  Widget _buildOverviewTab() {
    final o = _overview;
    if (o == null) return const Center(child: Text('No data', style: TextStyle(color: AppTheme.subtext0)));

    return RefreshIndicator(
      onRefresh: _loadAllData,
      color: AppTheme.mauve,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Stat Cards Grid ──
          _sectionTitle('📊 Overview Statistics', 'Powered by MongoDB Aggregation Pipeline'),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.5,
            children: [
              _statCard('Total Requests', '${o.totalRequests}', Icons.cleaning_services_rounded, AppTheme.blue),
              _statCard('Completed', '${o.completedRequests}', Icons.check_circle_rounded, AppTheme.green),
              _statCard('Active', '${o.activeRequests}', Icons.pending_rounded, AppTheme.peach),
              _statCard('Cancelled', '${o.cancelledRequests}', Icons.cancel_rounded, AppTheme.red),
              _statCard('Completion Rate', '${o.completionRate.toStringAsFixed(1)}%', Icons.trending_up_rounded, AppTheme.mauve),
              _statCard('Avg Time', '${o.avgCompletionMinutes.toStringAsFixed(0)} min', Icons.timer_rounded, AppTheme.yellow),
              _statCard('Students', '${o.totalStudents}', Icons.school_rounded, AppTheme.blue),
              _statCard('Cleaners', '${o.totalCleaners}', Icons.people_rounded, AppTheme.teal),
            ],
          ),
          const SizedBox(height: 24),

          // ── Status Distribution ──
          _sectionTitle('📈 Status Distribution', '\$group aggregation'),
          const SizedBox(height: 12),
          ..._statusDist.map((s) => _statusBar(s)),
          const SizedBox(height: 24),

          // ── Peak Hours ──
          _sectionTitle('🕐 Peak Hours', '\$project + \$group by hour'),
          const SizedBox(height: 12),
          SizedBox(
            height: 160,
            child: _peakHours.isEmpty
                ? const Center(child: Text('No data yet', style: TextStyle(color: AppTheme.subtext0)))
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: _peakHours.map((h) {
                      final maxCount = _peakHours.fold<int>(0, (m, e) => e.count > m ? e.count : m);
                      final height = maxCount > 0 ? (h.count / maxCount) * 120 : 0.0;
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text('${h.count}', style: TextStyle(color: AppTheme.subtext0, fontSize: 10)),
                              const SizedBox(height: 4),
                              Container(
                                height: height,
                                decoration: BoxDecoration(
                                  color: AppTheme.mauve.withValues(alpha: 0.7),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text('${h.hour}', style: TextStyle(color: AppTheme.overlay0, fontSize: 9)),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  //  Blocks Tab
  // ─────────────────────────────────────────────────────────
  Widget _buildBlocksTab() {
    return RefreshIndicator(
      onRefresh: _loadAllData,
      color: AppTheme.mauve,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionTitle('🏢 Requests by Hostel Block', '\$group by studentBlock'),
          const SizedBox(height: 12),
          if (_blockStats.isEmpty)
            const Center(child: Padding(
              padding: EdgeInsets.all(40),
              child: Text('No block data yet', style: TextStyle(color: AppTheme.subtext0)),
            )),
          ..._blockStats.map((b) => _blockCard(b)),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  //  Cleaners Tab (Leaderboard)
  // ─────────────────────────────────────────────────────────
  Widget _buildCleanersTab() {
    return RefreshIndicator(
      onRefresh: _loadAllData,
      color: AppTheme.mauve,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionTitle('🏆 Cleaner Leaderboard', '\$lookup + \$group + \$sort pipeline'),
          const SizedBox(height: 12),
          if (_leaderboard.isEmpty)
            const Center(child: Padding(
              padding: EdgeInsets.all(40),
              child: Text('No completed jobs yet', style: TextStyle(color: AppTheme.subtext0)),
            )),
          ..._leaderboard.asMap().entries.map((e) => _leaderboardTile(e.key, e.value)),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  //  Audit Log Tab
  // ─────────────────────────────────────────────────────────
  Widget _buildAuditTab() {
    return RefreshIndicator(
      onRefresh: _loadAllData,
      color: AppTheme.mauve,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionTitle('📋 Audit Trail', 'TTL-indexed collection (auto-expires in 90 days)'),
          const SizedBox(height: 12),
          if (_auditLogs.isEmpty)
            const Center(child: Padding(
              padding: EdgeInsets.all(40),
              child: Text('No audit logs yet', style: TextStyle(color: AppTheme.subtext0)),
            )),
          ..._auditLogs.map((log) => _auditLogTile(log)),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  //  Widget Helpers
  // ─────────────────────────────────────────────────────────

  Widget _sectionTitle(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
        const SizedBox(height: 4),
        Text(subtitle, style: GoogleFonts.outfit(fontSize: 12, color: AppTheme.overlay0, fontStyle: FontStyle.italic)),
      ],
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.base,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(value, style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white)),
          Text(label, style: GoogleFonts.outfit(fontSize: 12, color: AppTheme.subtext0)),
        ],
      ),
    );
  }

  Widget _statusBar(StatusStat stat) {
    final total = _statusDist.fold<int>(0, (s, e) => s + e.count);
    final pct = total > 0 ? stat.count / total : 0.0;
    final color = _statusColor(stat.status);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.base,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.surface0),
        ),
        child: Row(
          children: [
            Container(
              width: 10, height: 10,
              decoration: BoxDecoration(shape: BoxShape.circle, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(stat.status, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: pct,
                      backgroundColor: AppTheme.surface0,
                      valueColor: AlwaysStoppedAnimation(color),
                      minHeight: 6,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text('${stat.count}', style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 16)),
          ],
        ),
      ),
    );
  }

  Widget _blockCard(BlockStat stat) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.base,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.surface0),
      ),
      child: Row(
        children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              color: AppTheme.blue.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                stat.block,
                style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.w800, color: AppTheme.blue),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Block ${stat.block}', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
                const SizedBox(height: 4),
                Text(
                  '${stat.totalRequests} total · ${stat.completedRequests} completed · ${stat.urgentRequests} urgent',
                  style: TextStyle(color: AppTheme.subtext0, fontSize: 12),
                ),
              ],
            ),
          ),
          Text(
            '${stat.totalRequests}',
            style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.w800, color: AppTheme.blue),
          ),
        ],
      ),
    );
  }

  Widget _leaderboardTile(int index, LeaderboardEntry entry) {
    final medals = ['🥇', '🥈', '🥉'];
    final medal = index < 3 ? medals[index] : '${index + 1}';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.base,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: index == 0 ? AppTheme.yellow.withValues(alpha: 0.5) : AppTheme.surface0,
        ),
      ),
      child: Row(
        children: [
          Text(medal, style: const TextStyle(fontSize: 24)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.cleanerName, style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white)),
                const SizedBox(height: 2),
                Text(
                  '${entry.completedJobs} jobs · avg ${entry.avgCompletionMinutes.toStringAsFixed(0)} min',
                  style: TextStyle(color: AppTheme.subtext0, fontSize: 12),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppTheme.green.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '${entry.completedJobs}',
              style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.green),
            ),
          ),
        ],
      ),
    );
  }

  Widget _auditLogTile(AuditLogEntry log) {
    final actionColor = log.action == 'CREATE'
        ? AppTheme.green
        : log.action == 'UPDATE'
            ? AppTheme.blue
            : AppTheme.red;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.base,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.surface0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: actionColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(log.action, style: TextStyle(color: actionColor, fontSize: 11, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.surface0,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(log.collection, style: TextStyle(color: AppTheme.subtext0, fontSize: 11)),
              ),
              const Spacer(),
              Text(
                _formatTimestamp(log.timestamp),
                style: TextStyle(color: AppTheme.overlay0, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(log.summary, style: TextStyle(color: Colors.white, fontSize: 13)),
          const SizedBox(height: 4),
          Text('by ${log.performedByName}', style: TextStyle(color: AppTheme.overlay0, fontSize: 11)),
        ],
      ),
    );
  }

  String _formatTimestamp(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'OPEN': return AppTheme.blue;
      case 'ASSIGNED': return AppTheme.peach;
      case 'IN_PROGRESS': return AppTheme.yellow;
      case 'COMPLETED': return AppTheme.green;
      case 'CANCELLED_ROOM_LOCKED': return AppTheme.red;
      default: return AppTheme.overlay0;
    }
  }
}
