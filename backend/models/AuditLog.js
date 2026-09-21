// ============================================================
//  CleanIT — Audit Log Model (Mongoose / MongoDB)
// ============================================================
//
//  DBMS Concepts Demonstrated:
//  ─────────────────────────────────────────────────────────────
//  • TTL Index            — Documents automatically expire after
//                           90 days. MongoDB's background TTL thread
//                           removes expired documents periodically.
//                           This is a powerful DBMS feature for
//                           managing data lifecycle without cron jobs.
//  • Capped-style Logging — Write-heavy, read-infrequent pattern.
//  • Compound Indexes     — For efficient querying by collection
//                           name, document ID, and timestamp.
//  • Change Tracking      — Records old → new value transitions
//                           for every state change in the system.
// ============================================================

const mongoose = require('mongoose');

const auditLogSchema = new mongoose.Schema(
  {
    // Which collection was modified
    collection: {
      type: String,
      required: true,
      enum: ['users', 'requests', 'feedback'],
      index: true,
    },
    // The _id of the modified document
    documentId: {
      type: mongoose.Schema.Types.ObjectId,
      required: true,
    },
    // What type of operation
    action: {
      type: String,
      required: true,
      enum: ['CREATE', 'UPDATE', 'DELETE'],
    },
    // Who performed the action
    performedBy: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      default: null,
    },
    performedByName: {
      type: String,
      default: 'system',
    },
    // What changed (for UPDATE actions)
    changes: {
      type: mongoose.Schema.Types.Mixed,
      default: null,
    },
    // Human-readable summary
    summary: {
      type: String,
      required: true,
    },
    // Timestamp of the action
    timestamp: {
      type: Date,
      default: Date.now,
    },
    // ★ TTL field — document auto-expires at this date
    expireAt: {
      type: Date,
      default: () => new Date(Date.now() + 90 * 24 * 60 * 60 * 1000), // 90 days
    },
  },
  {
    // No updatedAt needed for immutable log entries
    timestamps: false,

    toJSON: {
      transform: (doc, ret) => {
        ret.id = ret._id.toString();
        delete ret._id;
        delete ret.__v;
        if (ret.documentId) ret.documentId = ret.documentId.toString();
        if (ret.performedBy) ret.performedBy = ret.performedBy.toString();
        return ret;
      },
    },
  }
);

// ─────────────────────────────────────────────────────────────
//  Indexes
// ─────────────────────────────────────────────────────────────

// ★ TTL Index — Auto-delete documents 90 days after expireAt
//   MongoDB's TTL monitor thread runs every 60 seconds and removes
//   documents whose expireAt field is past the current time.
auditLogSchema.index(
  { expireAt: 1 },
  { expireAfterSeconds: 0, name: 'idx_ttl_auto_expire' }
);

// Compound index for querying logs by collection + document
auditLogSchema.index(
  { collection: 1, documentId: 1, timestamp: -1 },
  { name: 'idx_audit_lookup' }
);

// Index for recent logs (admin dashboard)
auditLogSchema.index(
  { timestamp: -1 },
  { name: 'idx_audit_recent' }
);

const AuditLog = mongoose.model('AuditLog', auditLogSchema);

module.exports = AuditLog;
