// ============================================================
//  CleanIT — Admin Routes
// ============================================================
//
//  DBMS Concepts Demonstrated:
//  ─────────────────────────────────────────────────────────────
//  • Full-text Search  — $text / $search on notes field
//  • Data Export       — JSON export simulating mongodump
//  • DB Statistics     — Collection stats, index info
//  • Audit Log Query   — Querying TTL-indexed collection
// ============================================================

const express = require('express');
const mongoose = require('mongoose');
const Request = require('../models/Request');
const User = require('../models/User');
const Feedback = require('../models/Feedback');
const AuditLog = require('../models/AuditLog');
const auth = require('../middleware/auth');
const roleGuard = require('../middleware/roleGuard');

const router = express.Router();

// ─────────────────────────────────────────────────────────────
//  GET /api/admin/users — List all users with filters
// ─────────────────────────────────────────────────────────────
router.get('/users', auth, async (req, res) => {
  try {
    const { role, search, page = 1, limit = 50 } = req.query;
    const query = {};

    if (role) query.role = role;
    if (search) {
      query.$or = [
        { name: { $regex: search, $options: 'i' } },
        { email: { $regex: search, $options: 'i' } },
      ];
    }

    const skip = (parseInt(page) - 1) * parseInt(limit);

    const [users, total] = await Promise.all([
      User.find(query)
        .sort({ createdAt: -1 })
        .skip(skip)
        .limit(parseInt(limit))
        .lean(),
      User.countDocuments(query),
    ]);

    const transformed = users.map((u) => ({
      ...u,
      id: u._id.toString(),
      _id: undefined,
      password: undefined,
      __v: undefined,
    }));

    res.json({
      success: true,
      users: transformed,
      pagination: {
        page: parseInt(page),
        limit: parseInt(limit),
        total,
        pages: Math.ceil(total / parseInt(limit)),
      },
    });
  } catch (error) {
    console.error('List users error:', error);
    res.status(500).json({ error: 'Failed to list users' });
  }
});

// ─────────────────────────────────────────────────────────────
//  GET /api/admin/audit-logs — Fetch audit trail
//
//  ★ DBMS Feature: Querying TTL-indexed collection
// ─────────────────────────────────────────────────────────────
router.get('/audit-logs', auth, async (req, res) => {
  try {
    const { collection, action, page = 1, limit = 50 } = req.query;
    const query = {};

    if (collection) query.collection = collection;
    if (action) query.action = action;

    const skip = (parseInt(page) - 1) * parseInt(limit);

    const [logs, total] = await Promise.all([
      AuditLog.find(query)
        .sort({ timestamp: -1 })
        .skip(skip)
        .limit(parseInt(limit))
        .lean(),
      AuditLog.countDocuments(query),
    ]);

    const transformed = logs.map((l) => ({
      ...l,
      id: l._id.toString(),
      _id: undefined,
      __v: undefined,
      documentId: l.documentId?.toString(),
      performedBy: l.performedBy?.toString(),
    }));

    res.json({
      success: true,
      logs: transformed,
      pagination: {
        page: parseInt(page),
        limit: parseInt(limit),
        total,
        pages: Math.ceil(total / parseInt(limit)),
      },
    });
  } catch (error) {
    console.error('Fetch audit logs error:', error);
    res.status(500).json({ error: 'Failed to fetch audit logs' });
  }
});

// ─────────────────────────────────────────────────────────────
//  GET /api/admin/search — Full-text search across request notes
//
//  ★ DBMS Feature: Text Index / Full-text Search
//  Uses the text index on the `notes` field for $text queries.
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

    // ★ $text search — uses the text index on notes
    const [results, total] = await Promise.all([
      Request.find(
        { $text: { $search: q } },
        { score: { $meta: 'textScore' } } // ← Include relevance score
      )
        .sort({ score: { $meta: 'textScore' } }) // ← Sort by relevance
        .skip(skip)
        .limit(parseInt(limit))
        .lean(),
      Request.countDocuments({ $text: { $search: q } }),
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

// ─────────────────────────────────────────────────────────────
//  GET /api/admin/export/:collection — Export collection as JSON
//
//  ★ DBMS Feature: Data Export / Backup
//  Simulates mongodump by exporting entire collections as JSON.
// ─────────────────────────────────────────────────────────────
router.get('/export/:collection', auth, async (req, res) => {
  try {
    const collectionName = req.params.collection;
    const validCollections = ['users', 'requests', 'feedbacks', 'auditlogs'];

    if (!validCollections.includes(collectionName)) {
      return res.status(400).json({
        error: 'Invalid collection',
        message: `Valid collections: ${validCollections.join(', ')}`,
      });
    }

    // Get the Mongoose model for the collection
    const models = {
      users: User,
      requests: Request,
      feedbacks: Feedback,
      auditlogs: AuditLog,
    };

    const Model = models[collectionName];
    const data = await Model.find({}).lean();

    // Set headers for file download
    res.setHeader('Content-Type', 'application/json');
    res.setHeader(
      'Content-Disposition',
      `attachment; filename=cleanit_${collectionName}_${new Date().toISOString().split('T')[0]}.json`
    );

    res.json({
      collection: collectionName,
      exportedAt: new Date().toISOString(),
      count: data.length,
      data,
    });
  } catch (error) {
    console.error('Export error:', error);
    res.status(500).json({ error: 'Failed to export data' });
  }
});

// ─────────────────────────────────────────────────────────────
//  GET /api/admin/db-stats — Database statistics
//
//  ★ DBMS Feature: Database Introspection
//  Returns collection counts, index information, and sizes.
// ─────────────────────────────────────────────────────────────
router.get('/db-stats', auth, async (req, res) => {
  try {
    const db = mongoose.connection.db;

    // Get collection stats
    const collections = ['users', 'requests', 'feedbacks', 'auditlogs'];
    const stats = {};

    for (const name of collections) {
      try {
        const collStats = await db.collection(name).stats();
        const indexes = await db.collection(name).indexes();

        stats[name] = {
          documentCount: collStats.count,
          avgDocumentSize: collStats.avgObjSize || 0,
          totalSize: collStats.size || 0,
          indexCount: indexes.length,
          indexes: indexes.map((idx) => ({
            name: idx.name,
            keys: idx.key,
            unique: idx.unique || false,
            sparse: idx.sparse || false,
            partialFilter: idx.partialFilterExpression || null,
            ttl: idx.expireAfterSeconds != null ? `${idx.expireAfterSeconds}s` : null,
          })),
        };
      } catch {
        stats[name] = { documentCount: 0, note: 'Collection may not exist yet' };
      }
    }

    res.json({
      success: true,
      database: mongoose.connection.name,
      stats,
    });
  } catch (error) {
    console.error('DB stats error:', error);
    res.status(500).json({ error: 'Failed to fetch DB stats' });
  }
});

// ─────────────────────────────────────────────────────────────
//  PUT /api/admin/users/:id/role — Update user role (transactional)
//
//  ★ DBMS Feature: Multi-document Transaction
//  Changes user role and creates audit log atomically.
// ─────────────────────────────────────────────────────────────
router.put('/users/:id/role', auth, async (req, res) => {
  const session = await mongoose.startSession();
  try {
    const { role } = req.body;
    if (!['student', 'cleaner', 'admin'].includes(role)) {
      return res.status(400).json({ error: 'Invalid role' });
    }

    let result;
    await session.withTransaction(async () => {
      const user = await User.findById(req.params.id).session(session);
      if (!user) throw new Error('USER_NOT_FOUND');

      const oldRole = user.role;
      user.role = role;
      await user.save({ session });

      await AuditLog.create(
        [{
          collection: 'users',
          documentId: user._id,
          action: 'UPDATE',
          performedBy: req.userId,
          performedByName: req.user.name,
          changes: { role: { from: oldRole, to: role } },
          summary: `Role changed from ${oldRole} to ${role} for ${user.name}`,
        }],
        { session }
      );

      result = { id: user._id.toString(), name: user.name, oldRole, newRole: role };
    });

    res.json({ success: true, ...result });
  } catch (error) {
    if (error.message === 'USER_NOT_FOUND') {
      return res.status(404).json({ error: 'User not found' });
    }
    console.error('Role update error:', error);
    res.status(500).json({ error: 'Failed to update role' });
  } finally {
    await session.endSession();
  }
});

// ─────────────────────────────────────────────────────────────
//  GET /api/admin/deleted-requests — List soft-deleted requests
//
//  ★ DBMS Feature: Soft Delete Query
// ─────────────────────────────────────────────────────────────
router.get('/deleted-requests', auth, async (req, res) => {
  try {
    const { page = 1, limit = 20 } = req.query;
    const skip = (parseInt(page) - 1) * parseInt(limit);

    const [requests, total] = await Promise.all([
      Request.find({ isDeleted: true })
        .sort({ deletedAt: -1 })
        .skip(skip)
        .limit(parseInt(limit))
        .lean(),
      Request.countDocuments({ isDeleted: true }),
    ]);

    const transformed = requests.map((r) => ({
      ...r,
      id: r._id.toString(),
      _id: undefined,
      __v: undefined,
      studentId: r.studentId?.toString(),
      deletedBy: r.deletedBy?.toString(),
    }));

    res.json({
      success: true,
      requests: transformed,
      pagination: {
        page: parseInt(page),
        limit: parseInt(limit),
        total,
        pages: Math.ceil(total / parseInt(limit)),
      },
    });
  } catch (error) {
    console.error('Deleted requests error:', error);
    res.status(500).json({ error: 'Failed to fetch deleted requests' });
  }
});

// ─────────────────────────────────────────────────────────────
//  PUT /api/admin/bulk-cancel — Bulk cancel stale OPEN requests
//
//  ★ DBMS Feature: Bulk Write Operations
//  Cancels all OPEN requests older than a specified number of hours.
// ─────────────────────────────────────────────────────────────
router.put('/bulk-cancel', auth, async (req, res) => {
  try {
    const { olderThanHours = 24 } = req.body;
    const cutoff = new Date(Date.now() - olderThanHours * 60 * 60 * 1000);

    const result = await Request.updateMany(
      {
        status: 'OPEN',
        createdAt: { $lt: cutoff },
        isDeleted: { $ne: true },
      },
      {
        $set: {
          status: 'CANCELLED_ROOM_LOCKED',
          isDeleted: true,
          deletedAt: new Date(),
          deletedBy: req.userId,
        },
      }
    );

    if (result.modifiedCount > 0) {
      await AuditLog.create({
        collection: 'requests',
        documentId: null,
        action: 'BULK_CANCEL',
        performedBy: req.userId,
        performedByName: req.user.name,
        summary: `Bulk cancelled ${result.modifiedCount} stale requests older than ${olderThanHours}h`,
        changes: { cutoffDate: cutoff.toISOString(), modifiedCount: result.modifiedCount },
      });
    }

    res.json({
      success: true,
      message: `Cancelled ${result.modifiedCount} stale requests older than ${olderThanHours} hours.`,
      modifiedCount: result.modifiedCount,
      matchedCount: result.matchedCount,
    });
  } catch (error) {
    console.error('Bulk cancel error:', error);
    res.status(500).json({ error: 'Failed to bulk cancel' });
  }
});

// ─────────────────────────────────────────────────────────────
//  GET /api/admin/user-search — Full-text search on users
//
//  ★ DBMS Feature: Text Index Search
//  Uses the text index on name + email fields.
// ─────────────────────────────────────────────────────────────
router.get('/user-search', auth, async (req, res) => {
  try {
    const { q } = req.query;
    if (!q || q.trim().length === 0) {
      return res.status(400).json({ error: 'Missing query' });
    }

    const users = await User.find(
      { $text: { $search: q } },
      { score: { $meta: 'textScore' }, password: 0 }
    )
      .sort({ score: { $meta: 'textScore' } })
      .limit(20)
      .lean();

    const transformed = users.map((u) => ({
      ...u,
      id: u._id.toString(),
      _id: undefined,
      __v: undefined,
    }));

    res.json({ success: true, users: transformed });
  } catch (error) {
    console.error('User search error:', error);
    res.status(500).json({ error: 'Failed to search users' });
  }
});

module.exports = router;

