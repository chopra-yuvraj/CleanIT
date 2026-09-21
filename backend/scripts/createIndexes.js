// ============================================================
//  CleanIT — Index Creation Script
// ============================================================
//  Run: node scripts/createIndexes.js
//
//  ★ DBMS Feature: Index Management
//  Creates all indexes programmatically and displays the full
//  index catalog for each collection.
//
//  Index Types Demonstrated:
//  ─────────────────────────────────────────────────────────────
//  • Single-field index     — { email: 1 }
//  • Compound index         — { role: 1, isOnDuty: 1 }
//  • Unique index           — { email: 1 } with unique: true
//  • Partial unique index   — One active request per student
//  • Sparse index           — { fcmToken: 1 } (only indexes docs with field)
//  • Text index             — { notes: "text" } for full-text search
//  • TTL index              — { expireAt: 1 } with expireAfterSeconds: 0
//  • Descending index       — { isUrgent: -1 } for sorting
// ============================================================

require('dotenv').config();
const mongoose = require('mongoose');
const connectDB = require('../config/db');

// Import all models to register schemas (indexes are defined in models)
require('../models/User');
require('../models/Request');
require('../models/Feedback');
require('../models/AuditLog');

const createIndexes = async () => {
  await connectDB();
  console.log('📋 Creating indexes...\n');

  const db = mongoose.connection.db;
  const collections = ['users', 'requests', 'feedbacks', 'auditlogs'];

  // Ensure all model indexes are synced to MongoDB
  await mongoose.model('User').syncIndexes();
  await mongoose.model('Request').syncIndexes();
  await mongoose.model('Feedback').syncIndexes();
  await mongoose.model('AuditLog').syncIndexes();

  console.log('✅ All indexes synced!\n');
  console.log('═══════════════════════════════════════════════════');
  console.log('  INDEX CATALOG — CleanIT Database');
  console.log('═══════════════════════════════════════════════════\n');

  for (const name of collections) {
    try {
      const indexes = await db.collection(name).indexes();
      console.log(`── ${name.toUpperCase()} (${indexes.length} indexes) ──`);

      indexes.forEach((idx, i) => {
        const flags = [];
        if (idx.unique) flags.push('UNIQUE');
        if (idx.sparse) flags.push('SPARSE');
        if (idx.partialFilterExpression) flags.push('PARTIAL');
        if (idx.expireAfterSeconds != null) flags.push(`TTL(${idx.expireAfterSeconds}s)`);
        if (Object.values(idx.key).includes('text')) flags.push('TEXT');

        console.log(`  ${i + 1}. ${idx.name}`);
        console.log(`     Keys: ${JSON.stringify(idx.key)}`);
        if (flags.length) console.log(`     Flags: ${flags.join(', ')}`);
        if (idx.partialFilterExpression) {
          console.log(`     Filter: ${JSON.stringify(idx.partialFilterExpression)}`);
        }
      });
      console.log();
    } catch {
      console.log(`── ${name.toUpperCase()} — Collection not yet created ──\n`);
    }
  }

  console.log('═══════════════════════════════════════════════════\n');

  await mongoose.disconnect();
  process.exit(0);
};

createIndexes().catch((err) => {
  console.error('Index creation error:', err);
  process.exit(1);
});
