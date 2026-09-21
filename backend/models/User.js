// ============================================================
//  CleanIT — User Model (Mongoose / MongoDB)
// ============================================================
//
//  DBMS Concepts Demonstrated:
//  ─────────────────────────────────────────────────────────────
//  • Schema Validation    — Enforced at the database level via
//                           Mongoose validators (required, enum,
//                           match, minlength).
//  • Unique Indexes       — email field has a unique index to
//                           prevent duplicate registrations.
//  • Compound Indexes     — {role, isOnDuty} index speeds up
//                           queries for on-duty cleaners.
//  • Password Hashing     — Pre-save hook hashes passwords with
//                           bcrypt (12 salt rounds) before storage.
//  • Instance Methods     — comparePassword() for login verification.
//  • Timestamps           — Auto-managed createdAt / updatedAt.
// ============================================================

const mongoose = require('mongoose');
const bcrypt = require('bcryptjs');

const userSchema = new mongoose.Schema(
  {
    email: {
      type: String,
      required: [true, 'Email is required'],
      unique: true,
      lowercase: true,
      trim: true,
      match: [/^\S+@\S+\.\S+$/, 'Please enter a valid email'],
      index: true, // ← Single-field index for fast lookups
    },
    password: {
      type: String,
      required: [true, 'Password is required'],
      minlength: [6, 'Password must be at least 6 characters'],
      select: false, // ← Never return password in queries by default
    },
    name: {
      type: String,
      required: [true, 'Name is required'],
      trim: true,
      minlength: [2, 'Name must be at least 2 characters'],
      maxlength: [100, 'Name cannot exceed 100 characters'],
    },
    role: {
      type: String,
      enum: {
        values: ['student', 'cleaner', 'admin'],
        message: 'Role must be student, cleaner, or admin',
      },
      default: 'student',
      index: true, // ← Index for role-based queries
    },
    block: {
      type: String,
      trim: true,
      default: null,
    },
    roomNumber: {
      type: String,
      trim: true,
      default: null,
    },
    fcmToken: {
      type: String,
      default: null,
      sparse: true, // ← Sparse index: only indexes docs where field exists
    },
    isOnDuty: {
      type: Boolean,
      default: false,
    },
  },
  {
    // ── Schema Options ──
    timestamps: true,    // Auto createdAt + updatedAt fields
    versionKey: '__v',   // Optimistic concurrency version key

    // ── JSON Transform ──
    // Remap _id → id and strip sensitive fields when serializing
    toJSON: {
      transform: (doc, ret) => {
        ret.id = ret._id.toString();
        delete ret._id;
        delete ret.password;
        delete ret.__v;
        return ret;
      },
    },
  }
);

// ─────────────────────────────────────────────────────────────
//  Compound Indexes (DBMS Feature: Indexing)
// ─────────────────────────────────────────────────────────────
// Fast lookup for "find all on-duty cleaners"
userSchema.index({ role: 1, isOnDuty: 1 });

// ★ Text Index — Full-text search on name + email (admin user search)
userSchema.index(
  { name: 'text', email: 'text' },
  { name: 'idx_user_text_search' }
);

// ─────────────────────────────────────────────────────────────
//  Pre-save Hook: Password Hashing (DBMS Feature: Data Integrity)
// ─────────────────────────────────────────────────────────────
userSchema.pre('save', async function (next) {
  // Only hash if password was modified (or new)
  if (!this.isModified('password')) return next();

  const salt = await bcrypt.genSalt(12);
  this.password = await bcrypt.hash(this.password, salt);
  next();
});

// ─────────────────────────────────────────────────────────────
//  Instance Method: Password Comparison
// ─────────────────────────────────────────────────────────────
userSchema.methods.comparePassword = async function (candidatePassword) {
  return bcrypt.compare(candidatePassword, this.password);
};

// ─────────────────────────────────────────────────────────────
//  Static Method: Find on-duty cleaners
// ─────────────────────────────────────────────────────────────
userSchema.statics.findOnDutyCleaners = function () {
  return this.find({ role: 'cleaner', isOnDuty: true });
};

const User = mongoose.model('User', userSchema);

module.exports = User;
