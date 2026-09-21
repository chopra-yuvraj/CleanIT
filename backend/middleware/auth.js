// ============================================================
//  CleanIT — JWT Authentication Middleware
// ============================================================

const jwt = require('jsonwebtoken');
const User = require('../models/User');

const auth = async (req, res, next) => {
  try {
    // 1. Extract token from Authorization header
    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return res.status(401).json({
        error: 'Authentication required',
        message: 'Please provide a valid Bearer token.',
      });
    }

    const token = authHeader.split(' ')[1];

    // 2. Verify JWT
    const decoded = jwt.verify(token, process.env.JWT_SECRET);

    // 3. Find user in database
    const user = await User.findById(decoded.userId);
    if (!user) {
      return res.status(401).json({
        error: 'User not found',
        message: 'The user associated with this token no longer exists.',
      });
    }

    // 4. Attach user to request object
    req.user = user;
    req.userId = user._id;

    next();
  } catch (error) {
    if (error.name === 'TokenExpiredError') {
      return res.status(401).json({
        error: 'Token expired',
        message: 'Your session has expired. Please sign in again.',
      });
    }
    if (error.name === 'JsonWebTokenError') {
      return res.status(401).json({
        error: 'Invalid token',
        message: 'The provided token is invalid.',
      });
    }
    return res.status(500).json({ error: 'Authentication failed' });
  }
};

module.exports = auth;
