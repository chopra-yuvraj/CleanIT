// ============================================================
//  CleanIT Backend — MongoDB Connection Configuration
// ============================================================
//
//  DBMS Concepts Demonstrated:
//  ─────────────────────────────────────────────────────────────
//  • Connection Pooling   — Mongoose maintains a pool of reusable
//                           TCP connections (default: 100) to avoid
//                           per-request connection overhead.
//  • Event-Driven Monitoring — Listens to connected/error/disconnected
//                              events for observability.
//  • Retry Logic          — retryWrites=true in connection string
//                           ensures transient network failures don't
//                           lose acknowledged writes.
// ============================================================

const mongoose = require('mongoose');

const connectDB = async () => {
  try {
    const conn = await mongoose.connect(process.env.MONGODB_URI, {
      // ── Connection Pool Settings ──
      maxPoolSize: 10,         // Max connections in the pool
      minPoolSize: 2,          // Keep at least 2 connections warm
      serverSelectionTimeoutMS: 5000,  // Timeout for server selection
      socketTimeoutMS: 45000,          // Close sockets after 45s of inactivity
    });

    console.log(`✅ MongoDB Connected: ${conn.connection.host}`);
    console.log(`   Database: ${conn.connection.name}`);
    console.log(`   Pool Size: min=2, max=10`);

    // ── Connection Event Listeners ──
    mongoose.connection.on('error', (err) => {
      console.error('❌ MongoDB connection error:', err);
    });

    mongoose.connection.on('disconnected', () => {
      console.warn('⚠️  MongoDB disconnected');
    });

    mongoose.connection.on('reconnected', () => {
      console.log('🔄 MongoDB reconnected');
    });

  } catch (error) {
    console.error('❌ MongoDB connection failed:', error.message);
    process.exit(1);
  }
};

module.exports = connectDB;
