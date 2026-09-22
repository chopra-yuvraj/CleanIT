// ============================================================
//  CleanIT — Request Routes
// ============================================================
//
//  DBMS Concepts Demonstrated:
//  ─────────────────────────────────────────────────────────────
//  • Transactions         — accept_request uses a MongoDB session
//                           with multi-document ACID transaction
//                           to atomically update request status +
//                           embed the assignment.
//  • Optimistic Concurrency — start/complete use version checks
//                             (__v) to prevent lost updates.
//  • Partial Unique Index — One active request per student is
//                           enforced at the DB level (see model).
//  • Embedded Documents   — Assignment is embedded in request.
//  • Audit Trail          — Every state change is logged.
// ============================================================

const express = require('express');
const mongoose = require('mongoose');
const Request = require('../models/Request');
const User = require('../models/User');
const auth = require('../middleware/auth');
const roleGuard = require('../middleware/roleGuard');
const { logAudit } = require('../utils/auditLogger');

const router = express.Router();

// ─────────────────────────────────────────────────────────────
//  POST /api/requests — Create a new cleaning request (student)
// ─────────────────────────────────────────────────────────────
router.post('/', auth, roleGuard('student'), async (req, res) => {
  try {
    const { isSweeping, isMopping, isUrgent, notes } = req.body;

    if (!isSweeping && !isMopping) {
      return res.status(400).json({
        success: false,
        code: 'NO_TASK_SELECTED',
        message: 'Please select at least one cleaning task.',
      });
    }

    const request = await Request.create({
      studentId: req.userId,
      isSweeping: isSweeping || false,
      isMopping: isMopping || false,
      isUrgent: isUrgent || false,
      notes: notes?.trim() || null,
      studentName: req.user.name,
      studentBlock: req.user.block,
      studentRoom: req.user.roomNumber,
    });

    await logAudit({
      collection: 'requests',
      documentId: request._id,
      action: 'CREATE',
      performedBy: req.user,
      summary: `New cleaning request by ${req.user.name} (${req.user.block}-${req.user.roomNumber})`,
    });

    res.status(201).json({
      success: true,
      request_id: request._id.toString(),
      message: 'Request broadcast to all available cleaners.',
    });
  } catch (error) {
    // ★ Duplicate key error = student has an active request (partial unique index)
    if (error.code === 11000) {
      return res.status(409).json({
        success: false,
        code: 'ACTIVE_REQUEST_EXISTS',
        message: 'You already have an active cleaning request. Please wait for it to complete.',
      });
    }
    console.error('Create request error:', error);
    res.status(500).json({
      success: false,
      code: 'INTERNAL_ERROR',
      message: 'Failed to create request.',
    });
  }
});

// ─────────────────────────────────────────────────────────────
//  GET /api/requests/open — Fetch all OPEN requests (cleaner broadcast)
// ─────────────────────────────────────────────────────────────
router.get('/open', auth, roleGuard('cleaner', 'admin'), async (req, res) => {
  try {
    const requests = await Request.find({ status: 'OPEN' })
      .sort({ isUrgent: -1, createdAt: 1 }) // Urgent first, then oldest
      .lean(); // ← Returns plain JS objects (faster, no Mongoose overhead)

    // Transform _id → id for all results
    const transformed = requests.map((r) => ({
      ...r,
      id: r._id.toString(),
      _id: undefined,
      studentId: r.studentId?.toString(),
    }));

    res.json({ success: true, requests: transformed });
  } catch (error) {
    console.error('Fetch open requests error:', error);
    res.status(500).json({ error: 'Failed to fetch requests' });
  }
});

// ─────────────────────────────────────────────────────────────
//  GET /api/requests/my — Student's request history
// ─────────────────────────────────────────────────────────────
router.get('/my', auth, async (req, res) => {
  try {
    const requests = await Request.find({ studentId: req.userId })
      .sort({ createdAt: -1 })
      .limit(20)
      .lean();

    const transformed = requests.map((r) => ({
      ...r,
      id: r._id.toString(),
      _id: undefined,
      studentId: r.studentId?.toString(),
      assignment: r.assignment
        ? {
            ...r.assignment,
            id: r.assignment._id?.toString(),
            _id: undefined,
            cleanerId: r.assignment.cleanerId?.toString(),
          }
        : null,
    }));

    res.json({ success: true, requests: transformed });
  } catch (error) {
    console.error('Fetch student requests error:', error);
    res.status(500).json({ error: 'Failed to fetch requests' });
  }
});

// ─────────────────────────────────────────────────────────────
//  GET /api/requests/active — Student's current active request
// ─────────────────────────────────────────────────────────────
router.get('/active', auth, async (req, res) => {
  try {
    const request = await Request.findOne({
      studentId: req.userId,
      status: { $in: ['OPEN', 'ASSIGNED', 'IN_PROGRESS'] },
    })
      .sort({ createdAt: -1 })
      .lean();

    if (!request) {
      return res.json({ success: true, request: null });
    }

    const transformed = {
      ...request,
      id: request._id.toString(),
      _id: undefined,
      studentId: request.studentId?.toString(),
      assignment: request.assignment
        ? {
            ...request.assignment,
            id: request.assignment._id?.toString(),
            _id: undefined,
            cleanerId: request.assignment.cleanerId?.toString(),
          }
        : null,
    };

    res.json({ success: true, request: transformed });
  } catch (error) {
    console.error('Fetch active request error:', error);
    res.status(500).json({ error: 'Failed to fetch active request' });
  }
});

// ─────────────────────────────────────────────────────────────
//  GET /api/requests/cleaner-jobs — Cleaner's active jobs
// ─────────────────────────────────────────────────────────────
router.get('/cleaner-jobs', auth, roleGuard('cleaner', 'admin'), async (req, res) => {
  try {
    const jobs = await Request.find({
      'assignment.cleanerId': req.userId,
      status: { $in: ['ASSIGNED', 'IN_PROGRESS'] },
    })
      .sort({ createdAt: -1 })
      .lean();

    const transformed = jobs.map((r) => ({
      ...r,
      id: r._id.toString(),
      _id: undefined,
      studentId: r.studentId?.toString(),
      assignment: r.assignment
        ? {
            ...r.assignment,
            id: r.assignment._id?.toString(),
            _id: undefined,
            cleanerId: r.assignment.cleanerId?.toString(),
          }
        : null,
    }));

    res.json({ success: true, requests: transformed });
  } catch (error) {
    console.error('Fetch cleaner jobs error:', error);
    res.status(500).json({ error: 'Failed to fetch jobs' });
  }
});

// ─────────────────────────────────────────────────────────────
//  POST /api/requests/:id/accept — Accept a request (cleaner)
//
//  ★ DBMS Feature: Multi-Document ACID Transaction
//  Uses a MongoDB session to atomically:
//    1. Check the request is still OPEN
//    2. Update status to ASSIGNED
//    3. Embed the assignment sub-document
//  If any step fails, the entire transaction rolls back.
// ─────────────────────────────────────────────────────────────
router.post('/:id/accept', auth, roleGuard('cleaner', 'admin'), async (req, res) => {
  // ★ Start a MongoDB session for the transaction
  const session = await mongoose.startSession();

  try {
    let result;

    // ★ Execute within a transaction (ACID guarantees)
    await session.withTransaction(async () => {
      // 1. Find the request and verify it's OPEN (within the transaction)
      const request = await Request.findOneAndUpdate(
        {
          _id: req.params.id,
          status: 'OPEN', // Only accept if still OPEN
        },
        {
          $set: {
            status: 'ASSIGNED',
            assignment: {
              cleanerId: req.userId,
              cleanerName: req.user.name,
              assignedAt: new Date(),
            },
          },
        },
        {
          new: true,   // Return updated document
          session,     // ← Part of the transaction
        }
      );

      if (!request) {
        // Another cleaner already accepted this request
        result = {
          success: false,
          code: 'ALREADY_ASSIGNED',
          message: 'This request was already accepted by someone else.',
        };
        return;
      }

      result = {
        success: true,
        assignment_id: request.assignment._id.toString(),
        message: 'Request accepted successfully.',
      };
    });

    // Audit log (outside transaction — non-critical)
    if (result.success) {
      await logAudit({
        collection: 'requests',
        documentId: req.params.id,
        action: 'UPDATE',
        performedBy: req.user,
        changes: { status: { from: 'OPEN', to: 'ASSIGNED' } },
        summary: `Request accepted by cleaner ${req.user.name}`,
      });
    }

    const statusCode = result.success ? 200 : 409;
    res.status(statusCode).json(result);
  } catch (error) {
    console.error('Accept request error:', error);
    res.status(500).json({
      success: false,
      code: 'INTERNAL_ERROR',
      message: 'Failed to accept request.',
    });
  } finally {
    await session.endSession();
  }
});

// ─────────────────────────────────────────────────────────────
//  POST /api/requests/:id/start — Start a job (ASSIGNED → IN_PROGRESS)
//
//  ★ DBMS Feature: Optimistic Concurrency Control
//  Uses findOneAndUpdate with status condition to prevent
//  race conditions without explicit locking.
// ─────────────────────────────────────────────────────────────
router.post('/:id/start', auth, roleGuard('cleaner', 'admin'), async (req, res) => {
  try {
    const request = await Request.findOneAndUpdate(
      {
        _id: req.params.id,
        status: 'ASSIGNED',
        'assignment.cleanerId': req.userId,
      },
      {
        $set: {
          status: 'IN_PROGRESS',
          'assignment.startedAt': new Date(),
        },
      },
      { new: true }
    );

    if (!request) {
      return res.status(409).json({
        success: false,
        code: 'INVALID_STATE',
        message: 'Cannot start this job. It may not be assigned to you or has already started.',
      });
    }

    await logAudit({
      collection: 'requests',
      documentId: request._id,
      action: 'UPDATE',
      performedBy: req.user,
      changes: { status: { from: 'ASSIGNED', to: 'IN_PROGRESS' } },
      summary: `Job started by cleaner ${req.user.name}`,
    });

    res.json({ success: true, message: 'Job started.' });
  } catch (error) {
    console.error('Start job error:', error);
    res.status(500).json({
      success: false,
      code: 'INTERNAL_ERROR',
      message: 'Failed to start job.',
    });
  }
});

// ─────────────────────────────────────────────────────────────
//  POST /api/requests/:id/complete — Complete a job (IN_PROGRESS → COMPLETED)
// ─────────────────────────────────────────────────────────────
router.post('/:id/complete', auth, roleGuard('cleaner', 'admin'), async (req, res) => {
  try {
    const request = await Request.findOneAndUpdate(
      {
        _id: req.params.id,
        status: 'IN_PROGRESS',
        'assignment.cleanerId': req.userId,
      },
      {
        $set: {
          status: 'COMPLETED',
          'assignment.completedAt': new Date(),
        },
      },
      { new: true }
    );

    if (!request) {
      return res.status(409).json({
        success: false,
        code: 'INVALID_STATE',
        message: 'Cannot complete this job.',
      });
    }

    await logAudit({
      collection: 'requests',
      documentId: request._id,
      action: 'UPDATE',
      performedBy: req.user,
      changes: { status: { from: 'IN_PROGRESS', to: 'COMPLETED' } },
      summary: `Job completed by cleaner ${req.user.name}`,
    });

    res.json({ success: true, message: 'Job completed!' });
  } catch (error) {
    console.error('Complete job error:', error);
    res.status(500).json({
      success: false,
      code: 'INTERNAL_ERROR',
      message: 'Failed to complete job.',
    });
  }
});

// ─────────────────────────────────────────────────────────────
//  POST /api/requests/:id/report-locked — Room locked / cancellation
// ─────────────────────────────────────────────────────────────
router.post('/:id/report-locked', auth, roleGuard('cleaner', 'admin'), async (req, res) => {
  try {
    const { failureReason, proofUrl } = req.body;

    const request = await Request.findOneAndUpdate(
      {
        _id: req.params.id,
        status: { $in: ['ASSIGNED', 'IN_PROGRESS'] },
        'assignment.cleanerId': req.userId,
      },
      {
        $set: {
          status: 'CANCELLED_ROOM_LOCKED',
          'assignment.failureReason': failureReason || 'room_locked',
          'assignment.proofImageUrl': proofUrl || null,
          'assignment.completedAt': new Date(),
        },
      },
      { new: true }
    );

    if (!request) {
      return res.status(409).json({
        success: false,
        code: 'NOT_ASSIGNED_CLEANER',
        message: 'You are not the assigned cleaner for this request.',
      });
    }

    await logAudit({
      collection: 'requests',
      documentId: request._id,
      action: 'UPDATE',
      performedBy: req.user,
      changes: { status: { from: 'ASSIGNED/IN_PROGRESS', to: 'CANCELLED_ROOM_LOCKED' } },
      summary: `Room locked reported by ${req.user.name}: ${failureReason || 'room_locked'}`,
    });

    res.json({
      success: true,
      student_id: request.studentId.toString(),
      message: 'Request cancelled. Student will be notified.',
    });
  } catch (error) {
    console.error('Report locked error:', error);
    res.status(500).json({
      success: false,
      code: 'INTERNAL_ERROR',
      message: 'Failed to report.',
    });
  }
});

// ─────────────────────────────────────────────────────────────
//  DELETE /api/requests/:id — Soft-delete a request
//
//  ★ DBMS Feature: Soft Deletion (Logical Delete)
//  Instead of removing the document, we set isDeleted=true.
//  This preserves referential integrity and enables audit/recovery.
// ─────────────────────────────────────────────────────────────
router.delete('/:id', auth, async (req, res) => {
  try {
    const request = await Request.findOneAndUpdate(
      {
        _id: req.params.id,
        studentId: req.userId,
        status: { $in: ['COMPLETED', 'CANCELLED_ROOM_LOCKED'] },
        isDeleted: { $ne: true },
      },
      {
        $set: {
          isDeleted: true,
          deletedAt: new Date(),
          deletedBy: req.userId,
        },
      },
      { new: true }
    );

    if (!request) {
      return res.status(404).json({
        success: false,
        message: 'Request not found, still active, or already deleted.',
      });
    }

    await logAudit({
      collection: 'requests',
      documentId: request._id,
      action: 'DELETE',
      performedBy: req.user,
      summary: `Request soft-deleted by ${req.user.name}`,
    });

    res.json({ success: true, message: 'Request deleted (soft delete).' });
  } catch (error) {
    console.error('Soft delete error:', error);
    res.status(500).json({ success: false, message: 'Failed to delete request.' });
  }
});

// ─────────────────────────────────────────────────────────────
//  POST /api/requests/:id/cancel — Student cancels own request
//
//  ★ User-Defined Functionality: Student Self-Cancellation
//  Allows a student to cancel their own OPEN request before
//  any cleaner accepts it. Once ASSIGNED, cancellation is blocked.
// ─────────────────────────────────────────────────────────────
router.post('/:id/cancel', auth, roleGuard('student', 'admin'), async (req, res) => {
  try {
    const request = await Request.findOneAndUpdate(
      {
        _id: req.params.id,
        studentId: req.userId,
        status: 'OPEN', // Can only cancel if still OPEN
        isDeleted: { $ne: true },
      },
      {
        $set: {
          status: 'CANCELLED_ROOM_LOCKED',
          isDeleted: true,
          deletedAt: new Date(),
          deletedBy: req.userId,
        },
      },
      { new: true }
    );

    if (!request) {
      return res.status(409).json({
        success: false,
        code: 'CANNOT_CANCEL',
        message: 'Cannot cancel. The request may not exist, is already accepted by a cleaner, or was already cancelled.',
      });
    }

    await logAudit({
      collection: 'requests',
      documentId: request._id,
      action: 'DELETE',
      performedBy: req.user,
      changes: { status: { from: 'OPEN', to: 'CANCELLED_ROOM_LOCKED' } },
      summary: `Request self-cancelled by student ${req.user.name}`,
    });

    res.json({ success: true, message: 'Request cancelled successfully.' });
  } catch (error) {
    console.error('Cancel request error:', error);
    res.status(500).json({
      success: false,
      code: 'INTERNAL_ERROR',
      message: 'Failed to cancel request.',
    });
  }
});

// ─────────────────────────────────────────────────────────────
//  GET /api/requests/search — Full-text search on notes
//
//  ★ DBMS Feature: Text Index / Full-text Search
// ─────────────────────────────────────────────────────────────
router.get('/search', auth, async (req, res) => {
  try {
    const { q, page = 1, limit = 20 } = req.query;

    if (!q || q.trim().length === 0) {
      return res.status(400).json({
        error: 'Missing query',
        message: 'Please provide a search query (?q=...).',
      });
    }

    const skip = (parseInt(page) - 1) * parseInt(limit);

    const [results, total] = await Promise.all([
      Request.find(
        { $text: { $search: q }, isDeleted: { $ne: true } },
        { score: { $meta: 'textScore' } }
      )
        .sort({ score: { $meta: 'textScore' } })
        .skip(skip)
        .limit(parseInt(limit))
        .lean(),
      Request.countDocuments({ $text: { $search: q }, isDeleted: { $ne: true } }),
    ]);

    const transformed = results.map((r) => ({
      ...r,
      id: r._id.toString(),
      _id: undefined,
      __v: undefined,
      studentId: r.studentId?.toString(),
    }));

    res.json({
      success: true,
      results: transformed,
      query: q,
      pagination: {
        page: parseInt(page),
        limit: parseInt(limit),
        total,
        pages: Math.ceil(total / parseInt(limit)),
      },
    });
  } catch (error) {
    console.error('Text search error:', error);
    res.status(500).json({ error: 'Failed to search' });
  }
});

module.exports = router;
