// ============================================================
//  CleanIT — Feedback Routes
// ============================================================

const express = require('express');
const Feedback = require('../models/Feedback');
const Request = require('../models/Request');
const auth = require('../middleware/auth');
const { logAudit } = require('../utils/auditLogger');

const router = express.Router();

// ─────────────────────────────────────────────────────────────
//  POST /api/feedback — Submit feedback for a completed request
// ─────────────────────────────────────────────────────────────
router.post('/', auth, async (req, res) => {
  try {
    const { requestId, rating, comment } = req.body;

    if (!requestId || !rating) {
      return res.status(400).json({
        error: 'Missing fields',
        message: 'requestId and rating are required.',
      });
    }

    // Verify the request is COMPLETED and belongs to this student
    const request = await Request.findOne({
      _id: requestId,
      studentId: req.userId,
      status: 'COMPLETED',
    });

    if (!request) {
      return res.status(404).json({
        error: 'Not found',
        message: 'No completed request found with this ID for your account.',
      });
    }

    const feedback = await Feedback.create({
      requestId,
      studentId: req.userId,
      rating,
      comment: comment?.trim() || null,
    });

    await logAudit({
      collection: 'feedback',
      documentId: feedback._id,
      action: 'CREATE',
      performedBy: req.user,
      summary: `Feedback submitted: ${rating}/5 stars for request ${requestId}`,
    });

    res.status(201).json({
      success: true,
      feedback: feedback.toJSON(),
      message: 'Feedback submitted. Thank you!',
    });
  } catch (error) {
    // Duplicate feedback (unique index on requestId)
    if (error.code === 11000) {
      return res.status(409).json({
        error: 'Already submitted',
        message: 'You have already submitted feedback for this request.',
      });
    }
    console.error('Submit feedback error:', error);
    res.status(500).json({ error: 'Failed to submit feedback' });
  }
});

// ─────────────────────────────────────────────────────────────
//  GET /api/feedback/:requestId — Get feedback for a request
// ─────────────────────────────────────────────────────────────
router.get('/:requestId', auth, async (req, res) => {
  try {
    const feedback = await Feedback.findOne({
      requestId: req.params.requestId,
    }).lean();

    if (!feedback) {
      return res.json({ success: true, feedback: null });
    }

    res.json({
      success: true,
      feedback: {
        ...feedback,
        id: feedback._id.toString(),
        _id: undefined,
        requestId: feedback.requestId?.toString(),
        studentId: feedback.studentId?.toString(),
      },
    });
  } catch (error) {
    console.error('Fetch feedback error:', error);
    res.status(500).json({ error: 'Failed to fetch feedback' });
  }
});

// ─────────────────────────────────────────────────────────────
//  PUT /api/feedback/:id — Update feedback
//
//  ★ DBMS Feature: UPDATE operation with validation
// ─────────────────────────────────────────────────────────────
router.put('/:id', auth, async (req, res) => {
  try {
    const { rating, comment } = req.body;

    const feedback = await Feedback.findOne({
      _id: req.params.id,
      studentId: req.userId,
    });

    if (!feedback) {
      return res.status(404).json({
        error: 'Not found',
        message: 'Feedback not found or you do not own it.',
      });
    }

    const changes = {};
    if (rating !== undefined) {
      changes.rating = { from: feedback.rating, to: rating };
      feedback.rating = rating;
    }
    if (comment !== undefined) {
      changes.comment = { from: feedback.comment, to: comment?.trim() || null };
      feedback.comment = comment?.trim() || null;
    }

    await feedback.save();

    await logAudit({
      collection: 'feedback',
      documentId: feedback._id,
      action: 'UPDATE',
      performedBy: req.user,
      changes,
      summary: `Feedback updated: ${feedback.rating}/5 stars`,
    });

    res.json({
      success: true,
      feedback: feedback.toJSON(),
      message: 'Feedback updated.',
    });
  } catch (error) {
    console.error('Update feedback error:', error);
    res.status(500).json({ error: 'Failed to update feedback' });
  }
});

// ─────────────────────────────────────────────────────────────
//  DELETE /api/feedback/:id — Delete feedback
//
//  ★ DBMS Feature: DELETE operation (hard delete — feedback
//    has no referential integrity concerns)
// ─────────────────────────────────────────────────────────────
router.delete('/:id', auth, async (req, res) => {
  try {
    const feedback = await Feedback.findOneAndDelete({
      _id: req.params.id,
      studentId: req.userId,
    });

    if (!feedback) {
      return res.status(404).json({
        error: 'Not found',
        message: 'Feedback not found or you do not own it.',
      });
    }

    await logAudit({
      collection: 'feedback',
      documentId: feedback._id,
      action: 'DELETE',
      performedBy: req.user,
      summary: `Feedback deleted (was ${feedback.rating}/5 stars)`,
    });

    res.json({ success: true, message: 'Feedback deleted.' });
  } catch (error) {
    console.error('Delete feedback error:', error);
    res.status(500).json({ error: 'Failed to delete feedback' });
  }
});

// ─────────────────────────────────────────────────────────────
//  GET /api/feedback/details/:requestId — Feedback with full
//    request details via $lookup
//
//  ★ DBMS Feature: Aggregation $lookup (cross-collection join)
// ─────────────────────────────────────────────────────────────
router.get('/details/:requestId', auth, async (req, res) => {
  try {
    const [result] = await Feedback.aggregate([
      {
        $match: {
          requestId: new (require('mongoose').Types.ObjectId)(req.params.requestId),
        },
      },
      {
        $lookup: {
          from: 'requests',
          localField: 'requestId',
          foreignField: '_id',
          as: 'request',
        },
      },
      { $unwind: { path: '$request', preserveNullAndEmptyArrays: true } },
      {
        $lookup: {
          from: 'users',
          localField: 'studentId',
          foreignField: '_id',
          as: 'student',
        },
      },
      { $unwind: { path: '$student', preserveNullAndEmptyArrays: true } },
      {
        $project: {
          _id: 0,
          feedbackId: { $toString: '$_id' },
          rating: 1,
          comment: 1,
          createdAt: 1,
          requestStatus: '$request.status',
          requestTasks: {
            sweeping: '$request.isSweeping',
            mopping: '$request.isMopping',
          },
          requestRoom: {
            $concat: [
              { $ifNull: ['$request.studentBlock', '?'] },
              '-',
              { $ifNull: ['$request.studentRoom', '?'] },
            ],
          },
          studentName: { $ifNull: ['$student.name', 'Unknown'] },
          studentEmail: { $ifNull: ['$student.email', 'Unknown'] },
        },
      },
    ]);

    if (!result) {
      return res.json({ success: true, feedback: null });
    }

    res.json({ success: true, feedback: result });
  } catch (error) {
    console.error('Feedback details error:', error);
    res.status(500).json({ error: 'Failed to fetch feedback details' });
  }
});

module.exports = router;
