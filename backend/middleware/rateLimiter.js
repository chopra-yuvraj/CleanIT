// ============================================================
//  CleanIT — Rate Limiter Middleware
// ============================================================
//
//  Project Enhancement: API Rate Limiting
//  Uses express-rate-limit to protect endpoints from abuse.
//  Auth endpoints get a stricter limit (10 req/min) to prevent
//  brute-force attacks. General API gets 100 req/min per IP.
// ============================================================

const rateLimit = require('express-rate-limit');

// ── Auth Rate Limiter (stricter — prevents brute-force) ──
const authLimiter = rateLimit({
  windowMs: 60 * 1000,   // 1 minute window
  max: 10,               // 10 requests per minute per IP
  standardHeaders: true,  // Return rate limit info in `RateLimit-*` headers
  legacyHeaders: false,
  message: {
    error: 'Too many requests',
    message: 'Too many authentication attempts. Please try again after 1 minute.',
  },
});

// ── General API Rate Limiter ──
const apiLimiter = rateLimit({
  windowMs: 60 * 1000,   // 1 minute window
  max: 100,              // 100 requests per minute per IP
  standardHeaders: true,
  legacyHeaders: false,
  message: {
    error: 'Too many requests',
    message: 'Rate limit exceeded. Please slow down.',
  },
});

module.exports = { authLimiter, apiLimiter };
