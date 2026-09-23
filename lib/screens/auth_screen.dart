// CleanIT — Auth Screen
//
// Login / Sign-up screen with role selection (Student or Cleaner).
// Premium glassmorphic card design with animated transitions.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../config/app_theme.dart';
import '../config/theme_notifier.dart';
import '../models/models.dart';
import '../services/services.dart';
import 'student_home_screen.dart';
import 'cleaner_dashboard_screen.dart';
import 'admin_dashboard_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen>
    with SingleTickerProviderStateMixin {
  bool _isLogin = true;
  bool _isLoading = false;
  UserRole _selectedRole = UserRole.student;

  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _blockController = TextEditingController();
  final _roomController = TextEditingController();

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    );
    _fadeController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _blockController.dispose();
    _roomController.dispose();
    super.dispose();
  }

  void _toggleMode() {
    _fadeController.reverse().then((_) {
      setState(() => _isLogin = !_isLogin);
      _fadeController.forward();
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final auth = AuthService.instance;

      if (_isLogin) {
        await auth.signIn(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
      }
      AppUser? profile;
      if (_isLogin) {
        profile = auth.currentProfile ?? await auth.fetchProfile();
      } else {
        profile = await auth.signUp(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          name: _nameController.text.trim(),
          role: _selectedRole,
          block: _selectedRole == UserRole.student
              ? _blockController.text.trim()
              : null,
          roomNumber: _selectedRole == UserRole.student
              ? _roomController.text.trim()
              : null,
        );
      }

      if (!mounted) return;

      if (profile == null) {
        // Sign up was successful but email needs confirmation
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Account created! Please check your email to verify.',
                style: TextStyle(color: Color(0xFF1E1E2E), fontWeight: FontWeight.w600)),
            backgroundColor: AppTheme.green,
            duration: const Duration(seconds: 6),
          ),
        );
        _toggleMode(); // Switch back to login page
        return;
      }

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) {
            final role = profile!.role;
            if (role == UserRole.admin) {
              return const AdminDashboardScreen();
            } else if (role == UserRole.student) {
              return const StudentHomeScreen();
            } else {
              return const CleanerDashboardScreen();
            }
          },
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', ''),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
          backgroundColor: AppTheme.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    return Scaffold(
      backgroundColor: c.crust,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
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
                  themeNotifier.value = themeNotifier.value == ThemeMode.dark
                      ? ThemeMode.light
                      : ThemeMode.dark;
                },
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // ── Logo / Title ──
                  _buildHeader(c),
                  const SizedBox(height: 40),

                  // ── Auth Card ──
                  _buildAuthCard(c),
                  const SizedBox(height: 24),

                  // ── Toggle Login / Sign Up ──
                  _buildToggle(c),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeColors c) {
    return Column(
      children: [
        // App icon
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                c.blue.withValues(alpha: 0.3),
                c.mauve.withValues(alpha: 0.2),
              ],
            ),
            border: Border.all(color: c.blue.withValues(alpha: 0.4)),
          ),
          child: Icon(
            Icons.cleaning_services_rounded,
            color: c.blue,
            size: 40,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'CleanIT',
          style: GoogleFonts.outfit(
            fontSize: 36,
            fontWeight: FontWeight.w800,
            color: c.text,
            letterSpacing: -1,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Hostel room cleaning, simplified.',
          style: GoogleFonts.outfit(
            fontSize: 15,
            color: c.overlay0,
          ),
        ),
      ],
    );
  }

  Widget _buildAuthCard(ThemeColors c) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: c.base,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: c.surface0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 30,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title
            Text(
              _isLogin ? 'Welcome back' : 'Create account',
              style: GoogleFonts.outfit(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: c.text,
              ),
            ),
            const SizedBox(height: 24),

            // Name (sign up only)
            if (!_isLogin) ...[
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: 'Full Name',
                  labelStyle: TextStyle(color: c.overlay0),
                  prefixIcon: Icon(Icons.person_outline, color: c.overlay0),
                ),
                style: TextStyle(color: c.text),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Name is required' : null,
              ),
              const SizedBox(height: 16),
            ],

            // Email
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: 'Email',
                labelStyle: TextStyle(color: c.overlay0),
                prefixIcon: Icon(Icons.email_outlined, color: c.overlay0),
              ),
              style: TextStyle(color: c.text),
              validator: (v) =>
                  (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
            ),
            const SizedBox(height: 16),

            // Password
            TextFormField(
              controller: _passwordController,
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'Password',
                labelStyle: TextStyle(color: c.overlay0),
                prefixIcon: Icon(Icons.lock_outline, color: c.overlay0),
              ),
              style: TextStyle(color: c.text),
              validator: (v) =>
                  (v == null || v.length < 6) ? 'Min 6 characters' : null,
            ),

            // Role selector (sign up only)
            if (!_isLogin) ...[
              const SizedBox(height: 20),
              Text(
                'I am a...',
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: c.subtext0,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _roleChip(UserRole.student, 'Student', Icons.school_rounded, c),
                  const SizedBox(width: 12),
                  _roleChip(
                      UserRole.cleaner, 'Cleaner', Icons.cleaning_services, c),
                ],
              ),
            ],

            // Block & Room (student sign up only)
            if (!_isLogin && _selectedRole == UserRole.student) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _blockController,
                      decoration: InputDecoration(
                        labelText: 'Block',
                        labelStyle: TextStyle(color: c.overlay0),
                        hintText: 'A',
                        hintStyle: TextStyle(color: c.surface1),
                        prefixIcon:
                            Icon(Icons.apartment, color: c.overlay0),
                      ),
                      style: TextStyle(color: c.text),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Required'
                          : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _roomController,
                      decoration: InputDecoration(
                        labelText: 'Room',
                        labelStyle: TextStyle(color: c.overlay0),
                        hintText: '101',
                        hintStyle: TextStyle(color: c.surface1),
                        prefixIcon: Icon(Icons.meeting_room_outlined,
                            color: c.overlay0),
                      ),
                      style: TextStyle(color: c.text),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Required'
                          : null,
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 28),

            // Submit button
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: c.blue,
                  foregroundColor: c.crust,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: _isLoading
                    ? SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: c.crust,
                        ),
                      )
                    : Text(
                        _isLogin ? 'Sign In' : 'Create Account',
                        style: GoogleFonts.outfit(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _roleChip(UserRole role, String label, IconData icon, ThemeColors c) {
    final isSelected = _selectedRole == role;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedRole = role),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: isSelected
                ? c.blue.withValues(alpha: 0.15)
                : c.surface0.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected ? c.blue : c.surface0,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 20,
                  color: isSelected ? c.blue : c.overlay0),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? c.blue : c.text,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToggle(ThemeColors c) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          _isLogin ? "Don't have an account? " : 'Already have an account? ',
          style: TextStyle(color: c.overlay0, fontSize: 14),
        ),
        GestureDetector(
          onTap: _toggleMode,
          child: Text(
            _isLogin ? 'Sign Up' : 'Sign In',
            style: TextStyle(
              color: c.blue,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}
