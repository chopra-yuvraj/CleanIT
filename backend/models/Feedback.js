// ============================================================
//  CleanIT — Feedback Model (Mongoose / MongoDB)
// ============================================================
//
//  DBMS Concepts Demonstrated:
//  ─────────────────────────────────────────────────────────────
//  • Referential Integrity — requestId and studentId reference
//                            the Request and User collections.
//  • Unique Constraint     — Only one feedback per request,
//                            enforced via unique index on requestId.
//  • Range Validation      — Rating must be between 1 and 5.
//  • $lookup Joins         — Used in analytics to join feedback
//                            with requests for average ratings.
// ============================================================

const mongoose = require('mongoose');

const feedbackSchema = new mongoose.Schema(
  {
    requestId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Request',
      required: [true, 'Request ID is required'],
      index: true,
    },
    studentId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: [true, 'Student ID is required'],
      index: true,
    },
    rating: {
      type: Number,
      required: [true, 'Rating is required'],
      min: [1, 'Rating must be at least 1'],
      max: [5, 'Rating cannot exceed 5'],
      validate: {
        validator: Number.isInteger,
        message: 'Rating must be a whole number',
      },
    },
    comment: {
      type: String,
      trim: true,
      maxlength: [500, 'Comment cannot exceed 500 characters'],
      default: null,
    },
  },
  {
    timestamps: true,

    toJSON: {
      transform: (doc, ret) => {
        ret.id = ret._id.toString();
        delete ret._id;
        delete ret.__v;
        if (ret.requestId) ret.requestId = ret.requestId.toString();
        if (ret.studentId) ret.studentId = ret.studentId.toString();
        return ret;
      },
    },
  }
);

// ★ Unique Index — One feedback per request (DBMS: Unique Constraint)
feedbackSchema.index({ requestId: 1 }, { unique: true, name: 'idx_one_feedback_per_request' });

// Compound index for student's feedback history
feedbackSchema.index({ studentId: 1, createdAt: -1 }, { name: 'idx_student_feedback' });

const Feedback = mongoose.model('Feedback', feedbackSchema);

module.exports = Feedback;
