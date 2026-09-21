// ============================================================
//  CleanIT — Role-Based Access Control Middleware
// ============================================================
//
//  DBMS Concept: Authorization / Access Control
//  This is the application-layer equivalent of PostgreSQL's
//  Row Level Security (RLS). Since MongoDB doesn't have built-in
//  RLS, we enforce access control in the API middleware layer.
// ============================================================

/**
 * Creates a middleware that restricts access to specific roles.
 * Must be used AFTER the auth middleware.
 *
 * @param  {...string} roles - Allowed roles (e.g., 'cleaner', 'admin')
 * @returns {Function} Express middleware
 *
 * @example
 *   router.get('/admin-only', auth, roleGuard('admin'), handler);
 *   router.post('/clean', auth, roleGuard('cleaner', 'admin'), handler);
 */
const roleGuard = (...roles) => {
  return (req, res, next) => {
    if (!req.user) {
      return res.status(401).json({
        error: 'Authentication required',
        message: 'Please sign in first.',
      });
    }

    if (!roles.includes(req.user.role)) {
      return res.status(403).json({
        error: 'Forbidden',
        message: `This action requires one of these roles: ${roles.join(', ')}. Your role: ${req.user.role}.`,
      });
    }

    next();
  };
};

module.exports = roleGuard;
