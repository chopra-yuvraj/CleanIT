// ============================================================
//  CleanIT — Auth Routes
// ============================================================

const express = require('express');
const jwt = require('jsonwebtoken');
const User = require('../models/User');
const auth = require('../middleware/auth');
const { logAudit } = require('../utils/auditLogger');

const router = express.Router();

/**
 * Generate a JWT token for a user.
 */
const generateToken = (userId) => {
  return jwt.sign({ userId }, process.env.JWT_SECRET, {
    expiresIn: process.env.JWT_EXPIRY || '7d',
  });
};

// ─────────────────────────────────────────────────────────────
//  POST /api/auth/register — Create a new user account
// ─────────────────────────────────────────────────────────────
router.post('/register', async (req, res) => {
  try {
    const { email, password, name, role, block, roomNumber } = req.body;

    // Validate required fields
    if (!email || !password || !name) {
      return res.status(400).json({
        error: 'Missing required fields',
        message: 'Email, password, and name are required.',
      });
    }

    // Check if user already exists
    const existingUser = await User.findOne({ email: email.toLowerCase() });
    if (existingUser) {
      return res.status(409).json({
        error: 'Email already registered',
        message: 'An account with this email already exists.',
      });
    }

    // Create the user (password is auto-hashed by pre-save hook)
    const user = await User.create({
      email,
      password,
      name,
      role: role || 'student',
      block: role === 'student' ? block : null,
      roomNumber: role === 'student' ? roomNumber : null,
      isOnDuty: role === 'cleaner' ? true : false,
    });

    // Generate JWT
    const token = generateToken(user._id);

    // Audit log
    await logAudit({
      collection: 'users',
      documentId: user._id,
      action: 'CREATE',
      performedBy: user,
      summary: `New ${user.role} account created: ${user.name} (${user.email})`,
    });

    res.status(201).json({
      success: true,
      token,
      user: user.toJSON(),
      message: 'Account created successfully.',
    });
  } catch (error) {
    console.error('Register error:', error);

    // Handle Mongoose validation errors
    if (error.name === 'ValidationError') {
      const messages = Object.values(error.errors).map((e) => e.message);
      return res.status(400).json({
        error: 'Validation failed',
        message: messages.join('. '),
      });
    }

    // Handle duplicate key error (race condition on email)
    if (error.code === 11000) {
      return res.status(409).json({
        error: 'Email already registered',
        message: 'An account with this email already exists.',
      });
    }

    res.status(500).json({ error: 'Registration failed' });
  }
});

// ─────────────────────────────────────────────────────────────
//  POST /api/auth/login — Sign in with email & password
// ─────────────────────────────────────────────────────────────
router.post('/login', async (req, res) => {
  try {
    const { email, password } = req.body;

    if (!email || !password) {
      return res.status(400).json({
        error: 'Missing credentials',
        message: 'Email and password are required.',
      });
    }

    // Find user WITH password field (normally excluded by select: false)
    const user = await User.findOne({ email: email.toLowerCase() }).select('+password');
    if (!user) {
      return res.status(401).json({
        error: 'Invalid credentials',
        message: 'No account found with this email.',
      });
    }

    // Compare password
    const isMatch = await user.comparePassword(password);
    if (!isMatch) {
      return res.status(401).json({
        error: 'Invalid credentials',
        message: 'Incorrect password.',
      });
    }

    // Generate JWT
    const token = generateToken(user._id);

    res.json({
      success: true,
      token,
      user: user.toJSON(),
    });
  } catch (error) {
    console.error('Login error:', error);
    res.status(500).json({ error: 'Login failed' });
  }
});

// ─────────────────────────────────────────────────────────────
//  GET /api/auth/profile — Get current user profile
// ─────────────────────────────────────────────────────────────
router.get('/profile', auth, async (req, res) => {
  try {
    res.json({ success: true, user: req.user.toJSON() });
  } catch (error) {
    console.error('Profile error:', error);
    res.status(500).json({ error: 'Failed to fetch profile' });
  }
});

// ─────────────────────────────────────────────────────────────
//  PUT /api/auth/fcm-token — Update FCM token
// ─────────────────────────────────────────────────────────────
router.put('/fcm-token', auth, async (req, res) => {
  try {
    const { fcmToken } = req.body;
    await User.findByIdAndUpdate(req.userId, { fcmToken });
    res.json({ success: true, message: 'FCM token updated.' });
  } catch (error) {
    console.error('FCM token update error:', error);
    res.status(500).json({ error: 'Failed to update FCM token' });
  }
});

// ─────────────────────────────────────────────────────────────
//  PUT /api/auth/toggle-duty — Toggle cleaner on-duty status
// ─────────────────────────────────────────────────────────────
router.put('/toggle-duty', auth, async (req, res) => {
  try {
    const { isOnDuty } = req.body;
    const user = await User.findByIdAndUpdate(
      req.userId,
      { isOnDuty },
      { new: true }
    );

    await logAudit({
      collection: 'users',
      documentId: req.userId,
      action: 'UPDATE',
      performedBy: req.user,
      changes: { isOnDuty: { from: !isOnDuty, to: isOnDuty } },
      summary: `${req.user.name} toggled duty status to ${isOnDuty ? 'ON' : 'OFF'}`,
    });

    res.json({ success: true, user: user.toJSON() });
  } catch (error) {
    console.error('Toggle duty error:', error);
    res.status(500).json({ error: 'Failed to toggle duty status' });
  }
});

// ─────────────────────────────────────────────────────────────
//  PUT /api/auth/change-password — Change user password
//
//  ★ User-Defined Functionality: Password Management
//  Validates the current password before accepting the new one.
//  The pre-save hook on the User model auto-hashes the new password.
// ─────────────────────────────────────────────────────────────
router.put('/change-password', auth, async (req, res) => {
  try {
    const { currentPassword, newPassword } = req.body;

    if (!currentPassword || !newPassword) {
      return res.status(400).json({
        error: 'Missing fields',
        message: 'Both currentPassword and newPassword are required.',
      });
    }

    if (newPassword.length < 6) {
      return res.status(400).json({
        error: 'Weak password',
        message: 'New password must be at least 6 characters.',
      });
    }

    // Fetch user WITH password field (normally excluded by select: false)
    const user = await User.findById(req.userId).select('+password');
    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    // Verify current password
    const isMatch = await user.comparePassword(currentPassword);
    if (!isMatch) {
      return res.status(401).json({
        error: 'Incorrect password',
        message: 'Current password is incorrect.',
      });
    }

    // Update password (pre-save hook will hash it)
    user.password = newPassword;
    await user.save();

    // Audit log
    await logAudit({
      collection: 'users',
      documentId: user._id,
      action: 'UPDATE',
      performedBy: req.user,
      changes: { password: { from: '[REDACTED]', to: '[REDACTED]' } },
      summary: `Password changed by ${user.name}`,
    });

    res.json({ success: true, message: 'Password changed successfully.' });
  } catch (error) {
    console.error('Change password error:', error);
    res.status(500).json({ error: 'Failed to change password' });
  }
});

module.exports = router;
