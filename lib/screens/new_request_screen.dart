/// CleanIT — New Request Screen
///
/// Student creates a new cleaning request with:
/// - Two massive toggle buttons: Floor Sweeping | Wet Mopping
/// - Urgent switch (UI accents turn red when toggled)
/// - Notes text box
/// - "Broadcast Request to Cleaners" submit button

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

  Color get _accentColor => _isUrgent ? AppTheme.red : AppTheme.blue;

  Future<void> _submit() async {
    if (!_isSweeping && !_isMopping) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least one task.'),
          backgroundColor: AppTheme.peach,
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Request broadcast to cleaners! 🧹'),
            backgroundColor: AppTheme.green,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
        Navigator.pop(context, true); // Return true to refresh parent
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? 'Failed to create request.'),
            backgroundColor: AppTheme.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: AppTheme.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.crust,
      appBar: AppBar(
        backgroundColor: AppTheme.base,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: AppTheme.text),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('New Request',
            style: GoogleFonts.outfit(
                fontWeight: FontWeight.w600, color: Colors.white)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Room Info (auto-filled) ──
            _buildRoomInfo(),
            const SizedBox(height: 28),

            // ── Task Selection ──
            _buildSectionLabel('Select Tasks'),
            const SizedBox(height: 14),
            _buildTaskToggles(),
            const SizedBox(height: 28),

            // ── Urgent Toggle ──
            _buildUrgentToggle(),
            const SizedBox(height: 28),

            // ── Notes ──
            _buildSectionLabel('Notes for Cleaner (Optional)'),
            const SizedBox(height: 12),
            _buildNotesField(),
            const SizedBox(height: 36),

            // ── Submit ──
            _buildSubmitButton(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildRoomInfo() {
    final profile = AuthService.instance.currentProfile;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.base,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.surface0),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _accentColor.withOpacity(0.15),
            ),
            child: Icon(Icons.meeting_room_rounded,
                color: _accentColor, size: 22),
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
                  color: Colors.white,
                ),
              ),
              Text(
                'Auto-filled from your profile',
                style: TextStyle(fontSize: 12, color: AppTheme.overlay0),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String text) {
    return Text(
      text,
      style: GoogleFonts.outfit(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppTheme.overlay0,
        letterSpacing: 0.8,
      ),
    );
  }

  Widget _buildTaskToggles() {
    return Row(
      children: [
        Expanded(
          child: _taskToggle(
            label: 'Floor\nSweeping',
            icon: Icons.cleaning_services_rounded,
            isSelected: _isSweeping,
            onTap: () => setState(() => _isSweeping = !_isSweeping),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _taskToggle(
            label: 'Wet\nMopping',
            icon: Icons.water_drop_rounded,
            isSelected: _isMopping,
            onTap: () => setState(() => _isMopping = !_isMopping),
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
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        height: 130,
        decoration: BoxDecoration(
          color: isSelected
              ? _accentColor.withOpacity(0.12)
              : AppTheme.base,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? _accentColor : AppTheme.surface0,
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
                    ? _accentColor.withOpacity(0.2)
                    : AppTheme.surface0.withOpacity(0.5),
              ),
              child: Icon(
                icon,
                color: isSelected ? _accentColor : AppTheme.overlay0,
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
                color: isSelected ? Colors.white : AppTheme.subtext0,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUrgentToggle() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        gradient: _isUrgent
            ? LinearGradient(
                colors: [
                  AppTheme.red.withOpacity(0.15),
                  AppTheme.red.withOpacity(0.05),
                ],
              )
            : null,
        color: _isUrgent ? null : AppTheme.base,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _isUrgent
              ? AppTheme.red.withOpacity(0.4)
              : AppTheme.surface0,
          width: _isUrgent ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            _isUrgent
                ? Icons.warning_amber_rounded
                : Icons.schedule_rounded,
            color: _isUrgent ? AppTheme.red : AppTheme.overlay0,
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
                    color: _isUrgent ? AppTheme.red : Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Spills, accidents, etc.',
                  style: TextStyle(
                    fontSize: 12,
                    color: _isUrgent
                        ? AppTheme.red.withOpacity(0.7)
                        : AppTheme.overlay0,
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: _isUrgent,
            onChanged: (v) => setState(() => _isUrgent = v),
            activeColor: AppTheme.red,
            activeTrackColor: AppTheme.red.withOpacity(0.3),
          ),
        ],
      ),
    );
  }

  Widget _buildNotesField() {
    return TextField(
      controller: _notesController,
      maxLines: 4,
      maxLength: 500,
      style: const TextStyle(color: Colors.white, fontSize: 15),
      decoration: InputDecoration(
        hintText:
            'e.g., "Please be mindful of the glass on the floor" or "I am studying, please be quiet"',
        hintStyle: TextStyle(color: AppTheme.overlay0.withOpacity(0.6)),
        counterStyle: const TextStyle(color: AppTheme.overlay0),
      ),
    );
  }

  Widget _buildSubmitButton() {
    return SizedBox(
      width: double.infinity,
      height: 58,
      child: ElevatedButton.icon(
        onPressed: _isLoading ? null : _submit,
        icon: _isLoading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2.5, color: AppTheme.crust),
              )
            : const Icon(Icons.broadcast_on_personal_rounded, size: 22),
        label: Text(
          _isLoading ? 'Broadcasting...' : 'Broadcast Request to Cleaners',
          style: GoogleFonts.outfit(
              fontSize: 16, fontWeight: FontWeight.w700),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: _accentColor,
          foregroundColor: AppTheme.crust,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          elevation: 0,
        ),
      ),
    );
  }
}
