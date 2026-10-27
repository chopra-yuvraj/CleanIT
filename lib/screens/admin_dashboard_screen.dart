// CleanIT — Admin Analytics & DBMS Dashboard
//
// Showcases all Review 3 Admin and DBMS requirements:
// - Feature 1.1: Settings / Profile button leading to Secure Password Change
// - Feature 1.5: Clickable Cleaner Leaderboard navigating to CleanerPerformanceScreen
// - Feature 1.6: Analytics Overview Dashboard (Total, Completed, Cancelled, Active, Urgent, Completion Rate, Avg Time, Students, Cleaners, Avg Rating)
// - Feature 1.7: User Role Management with Mongoose ACID Multi-Document Transactions
// - Feature 2.2: Full-Text Search with Text Index (notes search with textScore ranking)
// - Feature 2.3: $facet Parallel Sub-Pipelines Task Distribution
// - Feature 2.4: Time-Series Grouping with $dateToString 30-Day Trends
// - Feature 2.6: Bulk Write Operations with updateMany (Bulk Cancel Stale Requests)
// - Feature 2.7: Query Optimization with explain(): IXSCAN vs COLLSCAN Analysis

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../config/app_theme.dart';
import '../config/theme_notifier.dart';
import '../models/analytics_model.dart';
import '../models/request_model.dart';
import '../models/user_model.dart';
import '../services/analytics_service.dart';
import '../services/auth_service.dart';
import 'auth_screen.dart';
import 'cleaner_performance_screen.dart';
import 'profile_settings_screen.dart';

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
  TaskDistribution? _taskDistribution;
  List<BlockStat> _blockStats = [];
  List<LeaderboardEntry> _leaderboard = [];
  List<HourlyStat> _peakHours = [];
  List<StatusStat> _statusDist = [];
  List<TrendPoint> _trends = [];
  List<AuditLogEntry> _auditLogs = [];
  List<CleaningRequest> _deletedRequests = [];
  List<AppUser> _users = [];
  List<ExplainResultItem> _explainResults = [];

  // Users tab state
  String _userRoleFilter = 'ALL';
  final _userSearchController = TextEditingController();

  // DBMS tab state
  final _textSearchController = TextEditingController();
  bool _isSearchingText = false;
  List<dynamic> _searchResults = [];
  bool _isBulkCancelling = false;
  int _bulkCancelHours = 24;
  bool _isLoadingExplain = false;

  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 7, vsync: this);
    _loadAllData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _userSearchController.dispose();
    _textSearchController.dispose();
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
        _analytics.fetchDeletedRequests(),
        _analytics.fetchTaskDistribution(),
        _analytics.fetchTrends(),
        _analytics.fetchUsers(),
      ]);

      if (mounted) {
        setState(() {
          _overview = results[0] as AnalyticsOverview;
          _blockStats = results[1] as List<BlockStat>;
          _leaderboard = results[2] as List<LeaderboardEntry>;
          _peakHours = results[3] as List<HourlyStat>;
          _statusDist = results[4] as List<StatusStat>;
          _auditLogs = results[5] as List<AuditLogEntry>;
          _deletedRequests = results[6] as List<CleaningRequest>;
          _taskDistribution = results[7] as TaskDistribution;
          _trends = results[8] as List<TrendPoint>;
          _users = results[9] as List<AppUser>;
        });
      }
    } catch (e) {
      debugPrint('Admin analytics load error: $e');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _loadExplainStats() async {
    setState(() => _isLoadingExplain = true);
    try {
      final results = await _analytics.fetchExplain();
      if (mounted) {
        setState(() {
          _explainResults = results;
          _isLoadingExplain = false;
        });
      }
    } catch (e) {
      debugPrint('Explain error: $e');
      if (mounted) setState(() => _isLoadingExplain = false);
    }
  }

  Future<void> _runFullTextSearch() async {
    final query = _textSearchController.text.trim();
    if (query.isEmpty) return;

    setState(() => _isSearchingText = true);
    try {
      final res = await _analytics.searchRequests(query);
      if (mounted) {
        setState(() {
          _searchResults = res['results'] as List<dynamic>? ?? [];
          _isSearchingText = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSearchingText = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Search error: $e'),
            backgroundColor: AppTheme.of(context).red,
          ),
        );
      }
    }
  }

  Future<void> _triggerBulkCancel() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final c = AppTheme.of(ctx);
        return AlertDialog(
          backgroundColor: c.surface0,
          title: Text(
            'Confirm Bulk Cancellation',
            style: GoogleFonts.outfit(fontWeight: FontWeight.w700, color: c.text),
          ),
          content: Text(
            'This will atomically cancel all OPEN requests created more than $_bulkCancelHours hours ago using MongoDB updateMany and log the action to auditlogs.\n\nProceed?',
            style: TextStyle(color: c.subtext0, fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel', style: TextStyle(color: c.overlay0)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: c.red,
                foregroundColor: c.crust,
              ),
              child: const Text('Execute Bulk Cancel'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    setState(() => _isBulkCancelling = true);
    try {
      final res = await _analytics.bulkCancelRequests(olderThanHours: _bulkCancelHours);
      if (mounted) {
        setState(() => _isBulkCancelling = false);
        final matched = res['matchedCount'] ?? 0;
        final modified = res['modifiedCount'] ?? 0;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Bulk Cancel complete: $matched matched, $modified modified.'),
            backgroundColor: AppTheme.of(context).green,
          ),
        );
        _loadAllData();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isBulkCancelling = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Bulk cancel failed: $e'),
            backgroundColor: AppTheme.of(context).red,
          ),
        );
      }
    }
  }

  Future<void> _changeUserRole(AppUser user, String newRole) async {
    if (user.role.name.toLowerCase() == newRole.toLowerCase()) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final c = AppTheme.of(ctx);
        return AlertDialog(
          backgroundColor: c.surface0,
          title: Text(
            'Change User Role',
            style: GoogleFonts.outfit(fontWeight: FontWeight.w700, color: c.text),
          ),
          content: Text(
            'Update role for "${user.name}" (${user.email}) from "${user.role.name.toUpperCase()}" to "${newRole.toUpperCase()}"?\n\nThis executes inside a MongoDB ACID transaction with an audit log record.',
            style: TextStyle(color: c.subtext0, fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel', style: TextStyle(color: c.overlay0)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: c.mauve,
                foregroundColor: c.crust,
              ),
              child: const Text('Confirm Update'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      await _analytics.updateUserRole(userId: user.id, role: newRole);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Role updated to ${newRole.toUpperCase()} (ACID Transaction logged)'),
            backgroundColor: AppTheme.of(context).green,
          ),
        );
        final updatedUsers = await _analytics.fetchUsers();
        final updatedLogs = await _analytics.fetchAuditLogs();
        setState(() {
          _users = updatedUsers;
          _auditLogs = updatedLogs;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update role: $e'),
            backgroundColor: AppTheme.of(context).red,
          ),
        );
      }
    }
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
    final c = AppTheme.of(context);
    return Scaffold(
      backgroundColor: c.crust,
      appBar: AppBar(
        backgroundColor: c.base,
        elevation: 0,
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: c.mauve.withValues(alpha: 0.15),
              ),
              child: Icon(Icons.analytics_rounded, color: c.mauve, size: 20),
            ),
            const SizedBox(width: 12),
            Text(
              'Admin Dashboard',
              style: GoogleFonts.outfit(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: c.text,
              ),
            ),
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
                  color: c.subtext0,
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
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProfileSettingsScreen()),
              );
            },
            icon: Icon(Icons.manage_accounts_rounded, color: c.subtext0),
            tooltip: 'Profile & Settings (Password Change)',
          ),
          IconButton(
            onPressed: _loadAllData,
            icon: Icon(Icons.refresh_rounded, color: c.subtext0),
            tooltip: 'Refresh',
          ),
          IconButton(
            onPressed: _signOut,
            icon: Icon(Icons.logout_rounded, color: c.subtext0),
            tooltip: 'Sign Out',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          indicatorColor: c.mauve,
          labelColor: c.mauve,
          unselectedLabelColor: c.overlay0,
          labelStyle: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 13),
          tabs: const [
            Tab(text: 'Overview', icon: Icon(Icons.dashboard_rounded, size: 18)),
            Tab(text: 'Blocks', icon: Icon(Icons.apartment_rounded, size: 18)),
            Tab(text: 'Cleaners', icon: Icon(Icons.leaderboard_rounded, size: 18)),
            Tab(text: 'Users & Roles', icon: Icon(Icons.people_alt_rounded, size: 18)),
            Tab(text: 'DBMS & Explain', icon: Icon(Icons.speed_rounded, size: 18)),
            Tab(text: 'Audit Log', icon: Icon(Icons.history_rounded, size: 18)),
            Tab(text: 'Trash', icon: Icon(Icons.delete_outline_rounded, size: 18)),
          ],
        ),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: c.mauve))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildOverviewTab(c),
                _buildBlocksTab(c),
                _buildCleanersTab(c),
                _buildUsersTab(c),
                _buildDbmsTab(c),
                _buildAuditTab(c),
                _buildTrashTab(c),
              ],
            ),
    );
  }

  // ─────────────────────────────────────────────────────────
  //  1. Overview Tab (Feature 1.6 + 2.3 + 2.4)
  // ─────────────────────────────────────────────────────────
  Widget _buildOverviewTab(ThemeColors c) {
    final o = _overview;
    if (o == null) {
      return Center(child: Text('No data available', style: TextStyle(color: c.subtext0)));
    }

    return RefreshIndicator(
      onRefresh: _loadAllData,
      color: c.mauve,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Stat Cards Grid (Feature 1.6) ──
          _sectionTitle('📊 Analytics Overview', 'MongoDB \$group aggregation with conditional accumulators', c),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.45,
            children: [
              _statCard('Total Requests', '${o.totalRequests}', Icons.cleaning_services_rounded, c.blue, c),
              _statCard('Completed', '${o.completedRequests}', Icons.check_circle_rounded, c.green, c),
              _statCard('Active', '${o.activeRequests}', Icons.pending_actions_rounded, c.peach, c),
              _statCard('Cancelled', '${o.cancelledRequests}', Icons.cancel_rounded, c.red, c),
              _statCard('Urgent Requests', '${o.urgentRequests}', Icons.bolt_rounded, c.red, c),
              _statCard('Completion Rate', '${o.completionRate.toStringAsFixed(1)}%', Icons.trending_up_rounded, c.mauve, c),
              _statCard('Avg Time', '${o.avgCompletionMinutes.toStringAsFixed(0)} min', Icons.timer_rounded, c.yellow, c),
              _statCard('Avg Rating', '${o.avgRating != '0.0' ? o.avgRating : '5.0'} ★', Icons.star_rounded, c.yellow, c),
              _statCard('Students', '${o.totalStudents}', Icons.school_rounded, c.teal, c),
              _statCard('Cleaners', '${o.totalCleaners}', Icons.people_rounded, c.teal, c),
            ],
          ),
          const SizedBox(height: 24),

          // ── Feature 2.3: $facet Parallel Sub-Pipelines Task Distribution ──
          _sectionTitle('⚡ Task Distribution (\$facet Pipeline)', 'Computed simultaneously in 4 isolated sub-pipelines', c),
          const SizedBox(height: 12),
          _buildTaskDistributionCard(c),
          const SizedBox(height: 24),

          // ── Status Distribution ──
          _sectionTitle('📈 Status Distribution', '\$group aggregation across all requests', c),
          const SizedBox(height: 12),
          ..._statusDist.map((s) => _statusBar(s, c)),
          const SizedBox(height: 24),

          // ── Feature 2.4: 30-Day Trends with $dateToString ──
          _sectionTitle('📅 30-Day Request Trends', 'Aggregated with \$dateToString (YYYY-MM-DD)', c),
          const SizedBox(height: 12),
          _buildTrendsCard(c),
          const SizedBox(height: 24),

          // ── Peak Hours ──
          _sectionTitle('🕐 Peak Request Hours', '\$project + \$group by hour', c),
          const SizedBox(height: 12),
          _buildPeakHoursChart(c),
        ],
      ),
    );
  }

  Widget _buildTaskDistributionCard(ThemeColors c) {
    final td = _taskDistribution;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.base,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.mauve.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.hub_rounded, color: c.mauve, size: 20),
              const SizedBox(width: 8),
              Text(
                'MongoDB \$facet Parallel Facets',
                style: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 14, color: c.text),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: c.mauve.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('Feature 2.3', style: TextStyle(color: c.mauve, fontSize: 10, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _facetMetricBox(
                  'Sweeping Only',
                  '${td?.sweepingOnly ?? 0}',
                  Icons.cleaning_services_rounded,
                  c.teal,
                  c,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _facetMetricBox(
                  'Mopping Only',
                  '${td?.moppingOnly ?? 0}',
                  Icons.water_drop_rounded,
                  c.blue,
                  c,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _facetMetricBox(
                  'Both Tasks',
                  '${td?.both ?? 0}',
                  Icons.auto_awesome_rounded,
                  c.green,
                  c,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _facetMetricBox(
                  'Urgent Marked',
                  '${td?.urgent ?? 0}',
                  Icons.bolt_rounded,
                  c.red,
                  c,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _facetMetricBox(String label, String value, IconData icon, Color color, ThemeColors c) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.surface0,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w800, color: c.text)),
                Text(label, style: TextStyle(fontSize: 11, color: c.subtext0)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrendsCard(ThemeColors c) {
    if (_trends.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: c.base,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.surface0),
        ),
        child: Center(
          child: Text('No request trend data in last 30 days', style: TextStyle(color: c.subtext0)),
        ),
      );
    }

    final maxVal = _trends.fold<int>(1, (prev, elem) => elem.count > prev ? elem.count : prev);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.base,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.surface0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Recent Daily Volume (${_trends.length} active dates)',
                style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w600, color: c.text),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: c.blue.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('Feature 2.4', style: TextStyle(color: c.blue, fontSize: 10, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ..._trends.take(7).map((pt) {
            final pct = pt.count / maxVal;
            final completedPct = pt.count > 0 ? pt.completed / pt.count : 0.0;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 80,
                    child: Text(
                      pt.date,
                      style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w500, color: c.subtext0),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Stack(
                      children: [
                        Container(
                          height: 12,
                          decoration: BoxDecoration(
                            color: c.surface0,
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        FractionallySizedBox(
                          widthFactor: pct.clamp(0.05, 1.0),
                          child: Container(
                            height: 12,
                            decoration: BoxDecoration(
                              color: c.blue.withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                        ),
                        FractionallySizedBox(
                          widthFactor: (pct * completedPct).clamp(0.0, 1.0),
                          child: Container(
                            height: 12,
                            decoration: BoxDecoration(
                              color: c.green,
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${pt.completed}/${pt.count}',
                    style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w700, color: c.text),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildPeakHoursChart(ThemeColors c) {
    if (_peakHours.isEmpty) {
      return Center(child: Text('No hourly data yet', style: TextStyle(color: c.subtext0)));
    }

    final maxCount = _peakHours.fold<int>(0, (m, e) => e.count > m ? e.count : m);

    return SizedBox(
      height: 160,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: _peakHours.map((h) {
          final height = maxCount > 0 ? (h.count / maxCount) * 110 : 0.0;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text('${h.count}', style: TextStyle(color: c.subtext0, fontSize: 10)),
                  const SizedBox(height: 4),
                  Container(
                    height: height < 4 ? 4 : height,
                    decoration: BoxDecoration(
                      color: c.mauve.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text('${h.hour}', style: TextStyle(color: c.overlay0, fontSize: 9)),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  //  2. Blocks Tab
  // ─────────────────────────────────────────────────────────
  Widget _buildBlocksTab(ThemeColors c) {
    return RefreshIndicator(
      onRefresh: _loadAllData,
      color: c.mauve,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionTitle('🏢 Requests by Hostel Block', 'Aggregated with \$group on studentBlock', c),
          const SizedBox(height: 12),
          if (_blockStats.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: Text('No block data available', style: TextStyle(color: c.subtext0)),
              ),
            ),
          ..._blockStats.map((b) => _blockCard(b, c)),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  //  3. Cleaners Tab (Feature 1.5 Integration)
  // ─────────────────────────────────────────────────────────
  Widget _buildCleanersTab(ThemeColors c) {
    return RefreshIndicator(
      onRefresh: _loadAllData,
      color: c.mauve,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionTitle('🏆 Cleaner Leaderboard', 'Tap any cleaner to view full performance analytics', c),
          const SizedBox(height: 12),
          if (_leaderboard.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: Text('No completed cleaner jobs yet', style: TextStyle(color: c.subtext0)),
              ),
            ),
          ..._leaderboard.asMap().entries.map((e) => _leaderboardTile(e.key, e.value, c)),
        ],
      ),
    );
  }

  Widget _leaderboardTile(int index, LeaderboardEntry entry, ThemeColors c) {
    final medals = ['🥇', '🥈', '🥉'];
    final medal = index < 3 ? medals[index] : '${index + 1}';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: c.base,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: index == 0 ? c.yellow.withValues(alpha: 0.5) : c.surface0,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => CleanerPerformanceScreen(
                cleanerId: entry.cleanerId,
                cleanerName: entry.cleanerName,
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Text(medal, style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.cleanerName,
                      style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w600, color: c.text),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${entry.completedJobs} jobs · avg ${entry.avgCompletionMinutes.toStringAsFixed(0)} min',
                      style: TextStyle(color: c.subtext0, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: c.green.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${entry.completedJobs} done',
                  style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w700, color: c.green),
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded, color: c.overlay0, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  //  4. Users & Roles Tab (Feature 1.7)
  // ─────────────────────────────────────────────────────────
  Widget _buildUsersTab(ThemeColors c) {
    final filteredUsers = _users.where((u) {
      if (_userRoleFilter != 'ALL' && u.role.name.toUpperCase() != _userRoleFilter) {
        return false;
      }
      final query = _userSearchController.text.trim().toLowerCase();
      if (query.isNotEmpty) {
        final matchName = u.name.toLowerCase().contains(query);
        final matchEmail = u.email.toLowerCase().contains(query);
        return matchName || matchEmail;
      }
      return true;
    }).toList();

    return RefreshIndicator(
      onRefresh: _loadAllData,
      color: c.mauve,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionTitle('👥 User Role Management', 'Mongoose multi-document ACID transactions with audit logging', c),
          const SizedBox(height: 12),

          // Search bar
          TextField(
            controller: _userSearchController,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Search by user name or email...',
              hintStyle: TextStyle(color: c.overlay0, fontSize: 13),
              prefixIcon: Icon(Icons.search_rounded, color: c.subtext0),
              filled: true,
              fillColor: c.base,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.surface0)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.surface0)),
            ),
          ),
          const SizedBox(height: 10),

          // Role filter chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: ['ALL', 'STUDENT', 'CLEANER', 'ADMIN'].map((role) {
                final isSelected = _userRoleFilter == role;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(role, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: isSelected ? c.crust : c.text)),
                    selected: isSelected,
                    onSelected: (_) => setState(() => _userRoleFilter = role),
                    selectedColor: c.mauve,
                    backgroundColor: c.base,
                    checkmarkColor: c.crust,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: isSelected ? c.mauve : c.surface0)),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 16),

          if (filteredUsers.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: Text('No users matching criteria', style: TextStyle(color: c.subtext0)),
              ),
            ),

          ...filteredUsers.map((user) => _userCard(user, c)),
        ],
      ),
    );
  }

  Widget _userCard(AppUser user, ThemeColors c) {
    final roleColor = user.role.name.toLowerCase() == 'admin'
        ? c.mauve
        : user.role.name.toLowerCase() == 'cleaner'
            ? c.teal
            : c.blue;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.base,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.surface0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: roleColor.withValues(alpha: 0.15),
                child: Text(
                  user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                  style: GoogleFonts.outfit(color: roleColor, fontWeight: FontWeight.w700, fontSize: 16),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user.name, style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w600, color: c.text)),
                    Text(user.email, style: TextStyle(color: c.subtext0, fontSize: 12)),
                    if (user.block != null && user.roomNumber != null)
                      Text('Block ${user.block} · Room ${user.roomNumber}', style: TextStyle(color: c.overlay0, fontSize: 11)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: roleColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  user.role.name.toUpperCase(),
                  style: TextStyle(color: roleColor, fontSize: 11, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 10),
          Row(
            children: [
              Text('Change Role:', style: TextStyle(color: c.subtext0, fontSize: 12)),
              const Spacer(),
              _roleButton(user, 'student', c),
              const SizedBox(width: 6),
              _roleButton(user, 'cleaner', c),
              const SizedBox(width: 6),
              _roleButton(user, 'admin', c),
            ],
          ),
        ],
      ),
    );
  }

  Widget _roleButton(AppUser user, String targetRole, ThemeColors c) {
    final isCurrent = user.role.name.toLowerCase() == targetRole.toLowerCase();
    return OutlinedButton(
      onPressed: isCurrent ? null : () => _changeUserRole(user, targetRole),
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        side: BorderSide(color: isCurrent ? c.mauve : c.surface0),
        backgroundColor: isCurrent ? c.mauve.withValues(alpha: 0.1) : Colors.transparent,
      ),
      child: Text(
        targetRole[0].toUpperCase() + targetRole.substring(1),
        style: TextStyle(
          fontSize: 11,
          fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
          color: isCurrent ? c.mauve : c.subtext0,
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  //  5. DBMS & Explain Tab (Features 2.2, 2.6, 2.7)
  // ─────────────────────────────────────────────────────────
  Widget _buildDbmsTab(ThemeColors c) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── Feature 2.2: Full-Text Search with Text Index ──
        _sectionTitle('🔍 Full-Text Search (\$text Index)', 'Indexed on { notes: "text" } with relevance score ranking', c),
        const SizedBox(height: 12),
        _buildFullTextSearchCard(c),
        const SizedBox(height: 24),

        // ── Feature 2.6: Bulk Write Operations with updateMany ──
        _sectionTitle('⚡ Bulk Write Operations (updateMany)', 'Atomic mass-status transition and TTL audit log', c),
        const SizedBox(height: 12),
        _buildBulkCancelCard(c),
        const SizedBox(height: 24),

        // ── Feature 2.7: Query Optimization with explain() ──
        _sectionTitle('🔬 Query Optimization & Index Verification', 'Live explain("executionStats"): IXSCAN vs COLLSCAN analysis', c),
        const SizedBox(height: 12),
        _buildExplainAnalysisCard(c),
      ],
    );
  }

  Widget _buildFullTextSearchCard(ThemeColors c) {
    return Container(
      padding: const EdgeInsets.all(16),
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
              Expanded(
                child: TextField(
                  controller: _textSearchController,
                  decoration: InputDecoration(
                    hintText: 'Enter keyword, e.g. "urgent", "spill", "dust"...',
                    hintStyle: TextStyle(color: c.overlay0, fontSize: 13),
                    isDense: true,
                    filled: true,
                    fillColor: c.surface0,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _isSearchingText ? null : _runFullTextSearch,
                style: ElevatedButton.styleFrom(
                  backgroundColor: c.mauve,
                  foregroundColor: c.crust,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: _isSearchingText
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.search_rounded, size: 18),
                label: const Text('Search'),
              ),
            ],
          ),
          if (_searchResults.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text('Found ${_searchResults.length} match(es) sorted by textScore:', style: TextStyle(color: c.subtext0, fontSize: 12)),
            const SizedBox(height: 8),
            ..._searchResults.map((item) {
              final score = item['score'] ?? item['textScore'] ?? 1.0;
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: c.surface0,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${item["studentName"] ?? "Student"} (${item["room"] ?? "Room"})', style: TextStyle(fontWeight: FontWeight.w600, color: c.text, fontSize: 13)),
                          Text(item['notes'] ?? '', style: TextStyle(color: c.subtext0, fontSize: 12)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: c.yellow.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text('score: ${score.toStringAsFixed(1)}', style: TextStyle(color: c.yellow, fontSize: 10, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildBulkCancelCard(ThemeColors c) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.base,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.surface0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Batch-cancel expired open requests older than a specified duration using Request.updateMany.',
            style: TextStyle(color: c.subtext0, fontSize: 13),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text('Cutoff: $_bulkCancelHours hours', style: GoogleFonts.outfit(fontWeight: FontWeight.w600, color: c.text)),
              const Spacer(),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 12, label: Text('12h')),
                  ButtonSegment(value: 24, label: Text('24h')),
                  ButtonSegment(value: 48, label: Text('48h')),
                ],
                selected: {_bulkCancelHours},
                onSelectionChanged: (val) => setState(() => _bulkCancelHours = val.first),
                style: SegmentedButton.styleFrom(
                  selectedBackgroundColor: c.mauve,
                  selectedForegroundColor: c.crust,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isBulkCancelling ? null : _triggerBulkCancel,
              style: ElevatedButton.styleFrom(
                backgroundColor: c.red,
                foregroundColor: c.crust,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: _isBulkCancelling
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.auto_delete_rounded, size: 18),
              label: const Text('Execute updateMany Bulk Cancel'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExplainAnalysisCard(ThemeColors c) {
    return Container(
      padding: const EdgeInsets.all(16),
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
              Expanded(
                child: Text(
                  'Verify MongoDB indexes: IXSCAN verifies that queries scan only index entries rather than entire collections.',
                  style: TextStyle(color: c.subtext0, fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isLoadingExplain ? null : _loadExplainStats,
              style: ElevatedButton.styleFrom(
                backgroundColor: c.blue,
                foregroundColor: c.crust,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: _isLoadingExplain
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.play_arrow_rounded, size: 18),
              label: const Text('Run Live explain("executionStats")'),
            ),
          ),
          if (_explainResults.isNotEmpty) ...[
            const SizedBox(height: 16),
            ..._explainResults.map((ex) => _explainItemTile(ex, c)),
          ],
        ],
      ),
    );
  }

  Widget _explainItemTile(ExplainResultItem item, ThemeColors c) {
    final isIxScan = item.winningPlanStage.toUpperCase().contains('IXSCAN');
    final stageColor = isIxScan ? c.green : c.red;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.surface0,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: stageColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.query,
                  style: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 14, color: c.text),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: stageColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  item.winningPlanStage,
                  style: TextStyle(color: stageColor, fontWeight: FontWeight.w800, fontSize: 11),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text('Filter: ${item.filter}', style: TextStyle(color: c.subtext0, fontSize: 11, fontFamily: 'monospace')),
          if (item.sort != null)
            Text('Sort: ${item.sort}', style: TextStyle(color: c.subtext0, fontSize: 11, fontFamily: 'monospace')),
          const SizedBox(height: 6),
          Row(
            children: [
              Text('Keys Examined: ${item.totalKeysExamined}', style: TextStyle(color: c.overlay0, fontSize: 11)),
              const SizedBox(width: 12),
              Text('Docs Examined: ${item.totalDocsExamined}', style: TextStyle(color: c.overlay0, fontSize: 11)),
              const Spacer(),
              Text('${item.executionTimeMillis} ms', style: GoogleFonts.outfit(fontWeight: FontWeight.w700, color: c.text, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 4),
          Text(item.explanation, style: TextStyle(color: c.subtext0, fontSize: 11, fontStyle: FontStyle.italic)),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  //  6. Audit Log Tab
  // ─────────────────────────────────────────────────────────
  Widget _buildAuditTab(ThemeColors c) {
    return RefreshIndicator(
      onRefresh: _loadAllData,
      color: c.mauve,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionTitle('📋 Audit Trail', 'TTL-indexed collection with automated document lifecycle management', c),
          const SizedBox(height: 12),
          if (_auditLogs.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: Text('No audit logs yet', style: TextStyle(color: c.subtext0)),
              ),
            ),
          ..._auditLogs.map((log) => _auditLogTile(log, c)),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  //  7. Trash Tab (Soft-Deleted Requests)
  // ─────────────────────────────────────────────────────────
  Widget _buildTrashTab(ThemeColors c) {
    return RefreshIndicator(
      onRefresh: _loadAllData,
      color: c.mauve,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionTitle('🗑️ Soft-Deleted Requests', 'Preserved in MongoDB for audit and restored on demand', c),
          const SizedBox(height: 12),
          if (_deletedRequests.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: Text('No deleted requests in trash', style: TextStyle(color: c.subtext0)),
              ),
            ),
          ..._deletedRequests.map((req) => _deletedRequestTile(req, c)),
        ],
      ),
    );
  }

  Widget _deletedRequestTile(CleaningRequest req, ThemeColors c) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.base,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.surface0),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: c.red.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.delete_outline_rounded, color: c.red, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${req.studentName ?? "Student"} (${req.roomLabel})',
                  style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w600, color: c.text),
                ),
                const SizedBox(height: 4),
                Text(req.tasksSummary, style: TextStyle(color: c.subtext0, fontSize: 12)),
                if (req.notes != null && req.notes!.isNotEmpty)
                  Text('Notes: ${req.notes}', style: TextStyle(color: c.overlay0, fontSize: 11)),
              ],
            ),
          ),
          ElevatedButton.icon(
            onPressed: () => _restoreRequest(req.id),
            style: ElevatedButton.styleFrom(
              backgroundColor: c.mauve,
              foregroundColor: c.crust,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.restore_rounded, size: 16),
            label: const Text('Restore', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Future<void> _restoreRequest(String id) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final res = await _analytics.restoreRequest(id);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res['message'] ?? 'Restored successfully'),
            backgroundColor: AppTheme.of(context).green,
          ),
        );
        _loadAllData();
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to restore: $e'),
            backgroundColor: AppTheme.of(context).red,
          ),
        );
      }
    }
  }

  // ─────────────────────────────────────────────────────────
  //  Common UI Components
  // ─────────────────────────────────────────────────────────

  Widget _sectionTitle(String title, String subtitle, ThemeColors c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w700, color: c.text)),
        const SizedBox(height: 4),
        Text(subtitle, style: GoogleFonts.outfit(fontSize: 12, color: c.overlay0, fontStyle: FontStyle.italic)),
      ],
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color, ThemeColors c) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.base,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 6),
          Text(value, style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.w800, color: c.text)),
          Text(label, style: GoogleFonts.outfit(fontSize: 11, color: c.subtext0), maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  Widget _statusBar(StatusStat stat, ThemeColors c) {
    final total = _statusDist.fold<int>(0, (s, e) => s + e.count);
    final pct = total > 0 ? stat.count / total : 0.0;
    final color = _statusColor(stat.status, c);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: c.base,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.surface0),
        ),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(shape: BoxShape.circle, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(stat.status, style: TextStyle(color: c.text, fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: pct,
                      backgroundColor: c.surface0,
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

  Widget _blockCard(BlockStat stat, ThemeColors c) {
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
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: c.blue.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                stat.block,
                style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.w800, color: c.blue),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Block ${stat.block}', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w600, color: c.text)),
                const SizedBox(height: 4),
                Text(
                  '${stat.totalRequests} total · ${stat.completedRequests} completed · ${stat.urgentRequests} urgent',
                  style: TextStyle(color: c.subtext0, fontSize: 12),
                ),
              ],
            ),
          ),
          Text(
            '${stat.totalRequests}',
            style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.w800, color: c.blue),
          ),
        ],
      ),
    );
  }

  Widget _auditLogTile(AuditLogEntry log, ThemeColors c) {
    final actionColor = log.action == 'CREATE'
        ? c.green
        : log.action == 'UPDATE'
            ? c.blue
            : log.action == 'BULK_CANCEL'
                ? c.peach
                : c.red;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.base,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.surface0),
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
                  color: c.surface0,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(log.collection, style: TextStyle(color: c.subtext0, fontSize: 11)),
              ),
              const Spacer(),
              Text(
                _formatTimestamp(log.timestamp),
                style: TextStyle(color: c.overlay0, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(log.summary, style: TextStyle(color: c.text, fontSize: 13)),
          const SizedBox(height: 4),
          Text('by ${log.performedByName}', style: TextStyle(color: c.overlay0, fontSize: 11)),
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

  Color _statusColor(String status, ThemeColors c) {
    switch (status) {
      case 'OPEN':
        return c.blue;
      case 'ASSIGNED':
        return c.peach;
      case 'IN_PROGRESS':
        return c.yellow;
      case 'COMPLETED':
        return c.green;
      case 'CANCELLED_ROOM_LOCKED':
        return c.red;
      default:
        return c.overlay0;
    }
  }
}
