// ============================================================
//  CleanIT Backend — Express Server Entry Point
// ============================================================

require('dotenv').config();
const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const morgan = require('morgan');
const connectDB = require('./config/db');

const app = express();
const PORT = process.env.PORT || 3000;

// ── Connect to MongoDB ──
connectDB();

// ── Middleware ──
app.use(helmet());                          // Security headers
app.use(cors());                            // Cross-origin requests
app.use(express.json({ limit: '10mb' }));   // JSON body parser
app.use(morgan('dev'));                      // Request logging

// ── Health Check ──
app.get('/api/health', (req, res) => {
  res.json({
    status: 'ok',
    service: 'CleanIT API',
    timestamp: new Date().toISOString(),
    dbState: require('mongoose').connection.readyState === 1 ? 'connected' : 'disconnected',
  });
});

// ── API Routes ──
app.use('/api/auth',      require('./routes/auth'));
app.use('/api/requests',  require('./routes/requests'));
app.use('/api/feedback',  require('./routes/feedback'));
app.use('/api/analytics', require('./routes/analytics'));
app.use('/api/admin',     require('./routes/admin'));
app.use('/api/dbms',      require('./routes/dbms'));

// ── 404 Handler ──
app.use((req, res) => {
  res.status(404).json({ error: 'Route not found' });
});

// ── Global Error Handler ──
app.use((err, req, res, _next) => {
  console.error('Unhandled error:', err);
  res.status(500).json({
    error: 'Internal server error',
    message: process.env.NODE_ENV === 'development' ? err.message : undefined,
  });
});

// ── Start Server ──
if (require.main === module) {
  app.listen(PORT, () => {
    console.log(`🚀 CleanIT API running on port ${PORT}`);
    console.log(`   Health: http://localhost:${PORT}/api/health`);
  });
}

module.exports = app;
