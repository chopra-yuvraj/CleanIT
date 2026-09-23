// CleanIT — New Request Screen
//
// Student creates a new cleaning request with:
// - Two massive toggle buttons: Floor Sweeping | Wet Mopping
// - Urgent switch (UI accents turn red when toggled)
// - Notes text box
// - "Broadcast Request to Cleaners" submit button

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../config/app_theme.dart';
import '../services/services.dart';

class NewRequestScreen extends StatefulWidget {
  const NewRequestScreen({super.key});

  @override
  State<NewRequestScreen> createState() => _NewRequestScreenState();
}

class _NewRequestScreenState extends State<NewRequestScreen> {
  bool _isSweeping = false;
  bool _isMopping = false;
  bool _isUrgent = false;
  bool _isLoading = false;
  final _notesController = TextEditingController();

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_isSweeping && !_isMopping) {
      SoundService.instance.play(AppSound.error);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please select at least one task.',
              style: TextStyle(color: Color(0xFF1E1E2E), fontWeight: FontWeight.w600)),
          backgroundColor: AppTheme.peach,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final result = await RequestService.instance.createRequest(
        isSweeping: _isSweeping,
        isMopping: _isMopping,
        isUrgent: _isUrgent,
        notes: _notesController.text.trim().isNotEmpty
            ? _notesController.text.trim()
            : null,
      );

      if (!mounted) return;

      if (result['success'] == true) {
        SoundService.instance.play(AppSound.requestCreated);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Request broadcast to cleaners! 🧹',
                style: TextStyle(color: Color(0xFF1E1E2E), fontWeight: FontWeight.w600)),
            backgroundColor: AppTheme.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
        Navigator.pop(context, true);
      } else {
        SoundService.instance.play(AppSound.error);
        final code = result['code'] as String?;
        String message;
        switch (code) {
          case 'ACTIVE_REQUEST_EXISTS':
            message = 'You already have an active request. Please wait for it to complete.';
            break;
          default:
            message = result['message'] ?? 'Something went wrong. Please try again.';
        }
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
    } catch (e) {
      if (!mounted) return;
      SoundService.instance.play(AppSound.error);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Could not create request. Check your connection and try again.',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
          backgroundColor: AppTheme.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final accentColor = _isUrgent ? c.red : c.blue;

    return Scaffold(
      backgroundColor: c.crust,
      appBar: AppBar(
        backgroundColor: c.base,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, color: c.text),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('New Request',
            style: GoogleFonts.outfit(
                fontWeight: FontWeight.w600, color: c.text)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Room Info (auto-filled) ──
            _buildRoomInfo(c, accentColor),
            const SizedBox(height: 28),

            // ── Task Selection ──
            _buildSectionLabel('Select Tasks', c),
            const SizedBox(height: 14),
            _buildTaskToggles(c, accentColor),
            const SizedBox(height: 28),

            // ── Urgent Toggle ──
            _buildUrgentToggle(c),
            const SizedBox(height: 28),

            // ── Notes ──
            _buildSectionLabel('Notes for Cleaner (Optional)', c),
            const SizedBox(height: 12),
            _buildNotesField(c),
            const SizedBox(height: 36),

            // ── Submit ──
            _buildSubmitButton(c, accentColor),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildRoomInfo(ThemeColors c, Color accentColor) {
    final profile = AuthService.instance.currentProfile;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: c.base,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.surface0),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accentColor.withValues(alpha: 0.15),
            ),
            child: Icon(Icons.meeting_room_rounded,
                color: accentColor, size: 22),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Room ${profile?.roomLabel ?? 'N/A'}',
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: c.text,
                ),
              ),
              Text(
                'Auto-filled from your profile',
                style: TextStyle(fontSize: 12, color: c.overlay0),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String text, ThemeColors c) {
    return Text(
      text,
      style: GoogleFonts.outfit(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: c.overlay0,
        letterSpacing: 0.8,
      ),
    );
  }

  Widget _buildTaskToggles(ThemeColors c, Color accentColor) {
    return Row(
      children: [
        Expanded(
          child: _taskToggle(
            label: 'Floor\nSweeping',
            icon: Icons.cleaning_services_rounded,
            isSelected: _isSweeping,
            onTap: () => setState(() => _isSweeping = !_isSweeping),
            c: c,
            accentColor: accentColor,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _taskToggle(
            label: 'Wet\nMopping',
            icon: Icons.water_drop_rounded,
            isSelected: _isMopping,
            onTap: () => setState(() => _isMopping = !_isMopping),
            c: c,
            accentColor: accentColor,
          ),
        ),
      ],
    );
  }

  Widget _taskToggle({
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
    required ThemeColors c,
    required Color accentColor,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        height: 130,
        decoration: BoxDecoration(
          color: isSelected
              ? accentColor.withValues(alpha: 0.12)
              : c.base,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? accentColor : c.surface0,
            width: isSelected ? 2.5 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected
                    ? accentColor.withValues(alpha: 0.2)
                    : c.surface0.withValues(alpha: 0.5),
              ),
              child: Icon(
                icon,
                color: isSelected ? accentColor : c.overlay0,
                size: 24,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? c.text : c.subtext0,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUrgentToggle(ThemeColors c) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        gradient: _isUrgent
            ? LinearGradient(
                colors: [
                  c.red.withValues(alpha: 0.15),
                  c.red.withValues(alpha: 0.05),
                ],
              )
            : null,
        color: _isUrgent ? null : c.base,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _isUrgent
              ? c.red.withValues(alpha: 0.4)
              : c.surface0,
          width: _isUrgent ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            _isUrgent
                ? Icons.warning_amber_rounded
                : Icons.schedule_rounded,
            color: _isUrgent ? c.red : c.overlay0,
            size: 24,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Mark as Urgent',
                  style: GoogleFonts.outfit(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: _isUrgent ? c.red : c.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Spills, accidents, etc.',
                  style: TextStyle(
                    fontSize: 12,
                    color: _isUrgent
                        ? c.red.withValues(alpha: 0.7)
                        : c.overlay0,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: _isUrgent,
            onChanged: (v) => setState(() => _isUrgent = v),
            thumbColor: WidgetStateProperty.resolveWith<Color>((states) {
              if (states.contains(WidgetState.selected)) {
                return c.red;
              }
              return Colors.grey;
            }),
            activeTrackColor: c.red.withValues(alpha: 0.3),
          ),
        ],
      ),
    );
  }

  Widget _buildNotesField(ThemeColors c) {
    return TextField(
      controller: _notesController,
      maxLines: 4,
      maxLength: 500,
      style: TextStyle(color: c.text, fontSize: 15),
      decoration: InputDecoration(
        hintText:
            'e.g., "Please be mindful of the glass on the floor" or "I am studying, please be quiet"',
        hintStyle: TextStyle(color: c.overlay0.withValues(alpha: 0.6)),
        counterStyle: TextStyle(color: c.overlay0),
      ),
    );
  }

  Widget _buildSubmitButton(ThemeColors c, Color accentColor) {
    return SizedBox(
      width: double.infinity,
      height: 58,
      child: ElevatedButton.icon(
        onPressed: _isLoading ? null : _submit,
        icon: _isLoading
            ? SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2.5, color: c.crust),
              )
            : const Icon(Icons.broadcast_on_personal_rounded, size: 22),
        label: Text(
          _isLoading ? 'Broadcasting...' : 'Broadcast Request to Cleaners',
          style: GoogleFonts.outfit(
              fontSize: 16, fontWeight: FontWeight.w700),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: accentColor,
          foregroundColor: c.crust,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          elevation: 0,
        ),
      ),
    );
  }
}
