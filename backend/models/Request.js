// ============================================================
//  CleanIT — Request Model (Mongoose / MongoDB)
// ============================================================
//
//  DBMS Concepts Demonstrated:
//  ─────────────────────────────────────────────────────────────
//  • Embedded Documents   — The assignment is embedded inside the
//                           request document (vs. a separate collection).
//                           This is the MongoDB "denormalized" pattern,
//                           chosen because an assignment always belongs
//                           to exactly one request (1:1 relationship).
//  • Referenced Documents — studentId and cleanerId store ObjectId
//                           references to the Users collection,
//                           demonstrating the "normalized" pattern.
//  • Schema Validation    — Status enum, boolean defaults, and
//                           required fields enforce data integrity.
//  • Compound Indexes     — Optimized for common query patterns:
//                           open requests, student history, etc.
//  • Partial Unique Index — Ensures one active request per student
//                           (only applied to OPEN/ASSIGNED/IN_PROGRESS).
//  • Text Index           — Full-text search on the notes field.
//  • Optimistic Concurrency — Version key (__v) prevents lost updates.
//  • Timestamps           — Auto-managed createdAt / updatedAt.
// ============================================================

const mongoose = require('mongoose');

// ── Assignment Sub-document Schema (Embedded Document Pattern) ──
const assignmentSchema = new mongoose.Schema(
  {
    cleanerId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
    },
    cleanerName: {
      type: String,
      default: null,
    },
    assignedAt: {
      type: Date,
      default: Date.now,
    },
    startedAt: {
      type: Date,
      default: null,
    },
    completedAt: {
      type: Date,
      default: null,
    },
    failureReason: {
      type: String,
      default: null,
    },
    proofImageUrl: {
      type: String,
      default: null,
    },
  },
  { _id: true }
);

// ── Main Request Schema ──
const requestSchema = new mongoose.Schema(
  {
    studentId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: [true, 'Student ID is required'],
      index: true,
    },
    status: {
      type: String,
      enum: {
        values: ['OPEN', 'ASSIGNED', 'IN_PROGRESS', 'COMPLETED', 'CANCELLED_ROOM_LOCKED'],
        message: 'Invalid request status: {VALUE}',
      },
      default: 'OPEN',
      index: true,
    },
    isSweeping: {
      type: Boolean,
      default: false,
    },
    isMopping: {
      type: Boolean,
      default: false,
    },
    isUrgent: {
      type: Boolean,
      default: false,
    },
    notes: {
      type: String,
      trim: true,
      maxlength: [500, 'Notes cannot exceed 500 characters'],
      default: null,
    },

    // ── Embedded Assignment (DBMS: Embedded Document Pattern) ──
    // Instead of a separate 'assignments' collection, the assignment
    // is embedded directly within the request. This eliminates the
    // need for $lookup joins for the most common query pattern.
    assignment: {
      type: assignmentSchema,
      default: null,
    },

    // ── Denormalized Student Info (for fast reads without joins) ──
    studentName: { type: String, default: null },
    studentBlock: { type: String, default: null },
    studentRoom: { type: String, default: null },

    // ── Soft Delete (DBMS Feature: Logical Deletion) ──
    // Instead of permanently removing documents, we flag them as deleted.
    // This preserves data integrity and enables audit/recovery workflows.
    isDeleted: {
      type: Boolean,
      default: false,
      index: true,
    },
    deletedAt: {
      type: Date,
      default: null,
    },
    deletedBy: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      default: null,
    },
  },
  {
    timestamps: true,
    versionKey: '__v', // ← Optimistic concurrency control

    toJSON: {
      transform: (doc, ret) => {
        ret.id = ret._id.toString();
        delete ret._id;
        delete ret.__v;
        // Transform assignment sub-doc ID too
        if (ret.assignment && ret.assignment._id) {
          ret.assignment.id = ret.assignment._id.toString();
          delete ret.assignment._id;
          if (ret.assignment.cleanerId) {
            ret.assignment.cleanerId = ret.assignment.cleanerId.toString();
          }
        }
        if (ret.studentId) {
          ret.studentId = ret.studentId.toString();
        }
        return ret;
      },
    },
  }
);

// ─────────────────────────────────────────────────────────────
//  Indexes (DBMS Feature: Indexing Strategies)
// ─────────────────────────────────────────────────────────────

// ★ Partial Unique Index — One active request per student
//   This is the MongoDB equivalent of PostgreSQL's partial unique index.
//   Only enforced for documents where status is OPEN, ASSIGNED, or IN_PROGRESS.
requestSchema.index(
  { studentId: 1 },
  {
    unique: true,
    partialFilterExpression: {
      status: { $in: ['OPEN', 'ASSIGNED', 'IN_PROGRESS'] },
    },
    name: 'idx_one_active_request_per_student',
  }
);

// Compound index for cleaner broadcast query (open requests, urgent first)
requestSchema.index(
  { status: 1, isUrgent: -1, createdAt: 1 },
  { name: 'idx_open_requests_broadcast' }
);

// Compound index for student history
requestSchema.index(
  { studentId: 1, createdAt: -1 },
  { name: 'idx_student_history' }
);

// Index for cleaner's active jobs
requestSchema.index(
  { 'assignment.cleanerId': 1, status: 1 },
  { name: 'idx_cleaner_jobs' }
);

// ★ Text Index — Full-text search on notes (DBMS Feature: Text Search)
requestSchema.index(
  { notes: 'text' },
  { name: 'idx_notes_text_search' }
);

// ─────────────────────────────────────────────────────────────
//  Virtuals (computed fields — not stored in DB)
// ─────────────────────────────────────────────────────────────
requestSchema.virtual('isActive').get(function () {
  return ['OPEN', 'ASSIGNED', 'IN_PROGRESS'].includes(this.status);
});

requestSchema.virtual('roomLabel').get(function () {
  return this.studentBlock && this.studentRoom
    ? `${this.studentBlock}-${this.studentRoom}`
    : 'N/A';
});

const Request = mongoose.model('Request', requestSchema);

module.exports = Request;
