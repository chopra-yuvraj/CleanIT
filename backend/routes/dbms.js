// ============================================================
//  CleanIT — DBMS Feature Showcase Routes
// ============================================================
//
//  Dedicated endpoints to demonstrate MongoDB DBMS capabilities
//  for project evaluation. Each endpoint showcases a specific
//  database concept with real data and explanations.
// ============================================================

const express = require('express');
const mongoose = require('mongoose');
const Request = require('../models/Request');
const User = require('../models/User');
const Feedback = require('../models/Feedback');
const AuditLog = require('../models/AuditLog');
const auth = require('../middleware/auth');
const { logAudit } = require('../utils/auditLogger');

const router = express.Router();

// ─────────────────────────────────────────────────────────────
//  GET /api/dbms/explain — Query Execution Plan Analysis
//
//  ★ DBMS Feature: Query Optimization / COLLSCAN vs IXSCAN
//  Runs explain() on common queries to show whether MongoDB
//  uses an index scan (IXSCAN) or full collection scan (COLLSCAN).
// ─────────────────────────────────────────────────────────────
router.get('/explain', auth, async (req, res) => {
  try {
    const db = mongoose.connection.db;

    // Query 1: Find open requests (uses idx_open_requests_broadcast)
    const openRequestsExplain = await db
      .collection('requests')
      .find({ status: 'OPEN', isDeleted: { $ne: true } })
      .sort({ isUrgent: -1, createdAt: 1 })
      .explain('executionStats');

    // Query 2: Find user by email (uses unique email index)
    const emailLookupExplain = await db
      .collection('users')
      .find({ email: 'rahul@vit.edu' })
      .explain('executionStats');

    // Query 3: Student request history (uses idx_student_history)
    const studentHistoryExplain = await db
      .collection('requests')
      .find({ studentId: new mongoose.Types.ObjectId() })
      .sort({ createdAt: -1 })
      .explain('executionStats');

    // Helper to extract key stats from explain output
    const extractStats = (explain) => {
      const stats = explain.executionStats || {};
      const stage = stats.executionStages || {};
      return {
        executionTimeMs: stats.executionTimeMillis,
        totalDocsExamined: stats.totalDocsExamined,
        totalKeysExamined: stats.totalKeysExamined,
        nReturned: stats.nReturned,
        winningPlan: explain.queryPlanner?.winningPlan?.stage || stage.stage || 'N/A',
        indexUsed: explain.queryPlanner?.winningPlan?.inputStage?.indexName
          || stage.inputStage?.indexName || 'NONE (COLLSCAN)',
        explanation: stats.totalKeysExamined > 0
          ? 'IXSCAN — Index was used. Only relevant index entries were scanned.'
          : 'COLLSCAN — Full collection scan. Every document was examined.',
      };
    };

    res.json({
      success: true,
      explainResults: [
        {
          query: 'Find all OPEN requests sorted by urgency',
          filter: '{ status: "OPEN", isDeleted: { $ne: true } }',
          sort: '{ isUrgent: -1, createdAt: 1 }',
          expectedIndex: 'idx_open_requests_broadcast',
          stats: extractStats(openRequestsExplain),
        },
        {
          query: 'Find user by email',
          filter: '{ email: "rahul@vit.edu" }',
          expectedIndex: 'email_1 (unique)',
          stats: extractStats(emailLookupExplain),
        },
        {
          query: 'Student request history',
          filter: '{ studentId: ObjectId(...) }',
          sort: '{ createdAt: -1 }',
          expectedIndex: 'idx_student_history',
          stats: extractStats(studentHistoryExplain),
        },
      ],
      note: 'IXSCAN = Index Scan (fast). COLLSCAN = Collection Scan (slow, examines every document).',
    });
  } catch (error) {
    console.error('Explain error:', error);
    res.status(500).json({ error: 'Failed to run explain' });
  }
});

// ─────────────────────────────────────────────────────────────
//  GET /api/dbms/indexes — Complete Index Catalog
//
//  ★ DBMS Feature: Index Management & Documentation
//  Lists every index across all collections with type, purpose,
//  and the query pattern it optimizes.
// ─────────────────────────────────────────────────────────────
router.get('/indexes', auth, async (req, res) => {
  try {
    const db = mongoose.connection.db;
    const collections = ['users', 'requests', 'feedbacks', 'auditlogs'];
    const catalog = {};

    const indexPurposes = {
      // Users
      'email_1': 'Fast login lookup by email. Unique constraint prevents duplicate registrations.',
      'role_1_isOnDuty_1': 'Compound index for fetching on-duty cleaners without scanning all users.',
      'idx_user_text_search': 'Full-text search on name and email for admin user search.',
      'fcmToken_1': 'Sparse index — only indexes users with push tokens, saving RAM.',
      // Requests
      'idx_one_active_request_per_student': 'Partial unique index: enforces one active request per student at the DB level.',
      'idx_open_requests_broadcast': 'Compound index for the cleaner broadcast query (open + urgent first).',
      'idx_student_history': 'Compound index for student request history (sorted by date).',
      'idx_cleaner_jobs': 'Compound index for finding a cleaner\'s active jobs.',
      'idx_notes_text_search': 'Text index enabling full-text search on request notes.',
      // Feedback
      'idx_one_feedback_per_request': 'Unique index: prevents duplicate feedback per request.',
      'idx_student_feedback': 'Compound index for student feedback history.',
      // Audit
      'idx_ttl_auto_expire': 'TTL index: auto-deletes audit logs after 90 days.',
      'idx_audit_lookup': 'Compound index for querying logs by collection + document.',
      'idx_audit_recent': 'Index for fetching recent audit logs (admin dashboard).',
    };

    for (const name of collections) {
      try {
        const indexes = await db.collection(name).indexes();
        catalog[name] = indexes.map((idx) => {
          const flags = [];
          if (idx.unique) flags.push('UNIQUE');
          if (idx.sparse) flags.push('SPARSE');
          if (idx.partialFilterExpression) flags.push('PARTIAL');
          if (idx.expireAfterSeconds != null) flags.push(`TTL(${idx.expireAfterSeconds}s)`);
          if (Object.values(idx.key).includes('text')) flags.push('TEXT');

          return {
            name: idx.name,
            keys: idx.key,
            flags: flags.length ? flags : ['STANDARD'],
            partialFilter: idx.partialFilterExpression || null,
            purpose: indexPurposes[idx.name] || 'Default _id index',
          };
        });
      } catch {
        catalog[name] = [{ note: 'Collection not yet created' }];
      }
    }

    res.json({
      success: true,
      totalIndexes: Object.values(catalog).flat().length,
      catalog,
      indexTypes: {
        'Single-field': 'Index on one field (e.g., email_1)',
        'Compound': 'Index on multiple fields (e.g., role_1_isOnDuty_1)',
        'Unique': 'Prevents duplicate values',
        'Partial': 'Only indexes documents matching a filter expression',
        'Sparse': 'Only indexes documents where the field exists',
        'Text': 'Enables $text full-text search queries',
        'TTL': 'Time-To-Live — auto-deletes documents after expiry',
      },
    });
  } catch (error) {
    console.error('Indexes error:', error);
    res.status(500).json({ error: 'Failed to fetch indexes' });
  }
});

// ─────────────────────────────────────────────────────────────
//  GET /api/dbms/collection-stats — Detailed Collection Statistics
//
//  ★ DBMS Feature: Database Introspection
// ─────────────────────────────────────────────────────────────
router.get('/collection-stats', auth, async (req, res) => {
  try {
    const db = mongoose.connection.db;
    const collections = ['users', 'requests', 'feedbacks', 'auditlogs'];
    const stats = {};

    for (const name of collections) {
      try {
        const collStats = await db.command({ collStats: name });
        const indexes = await db.collection(name).indexes();

        stats[name] = {
          documentCount: collStats.count,
          avgDocumentSizeBytes: collStats.avgObjSize || 0,
          totalDataSizeBytes: collStats.size || 0,
          totalIndexSizeBytes: collStats.totalIndexSize || 0,
          indexCount: indexes.length,
          storageEngine: collStats.wiredTiger ? 'WiredTiger' : 'Unknown',
          capped: collStats.capped || false,
        };
      } catch {
        stats[name] = { documentCount: 0, note: 'Collection may not exist yet' };
      }
    }

    res.json({
      success: true,
      database: mongoose.connection.name,
      host: mongoose.connection.host,
      readyState: mongoose.connection.readyState === 1 ? 'connected' : 'disconnected',
      stats,
    });
  } catch (error) {
    console.error('Collection stats error:', error);
    res.status(500).json({ error: 'Failed to fetch collection stats' });
  }
});

// ─────────────────────────────────────────────────────────────
//  POST /api/dbms/transaction-demo — Transaction with Rollback
//
//  ★ DBMS Feature: Multi-Document ACID Transactions
//  Creates a request + audit log atomically. If the audit log
//  write fails, the entire transaction rolls back.
//
//  This is a safe read-only demo: it performs the transaction
//  then rolls it back intentionally to demonstrate ACID behavior.
// ─────────────────────────────────────────────────────────────
router.post('/transaction-demo', auth, async (req, res) => {
  const session = await mongoose.startSession();
  const steps = [];

  try {
    steps.push({ step: 1, action: 'Session started', timestamp: new Date() });

    await session.withTransaction(async () => {
      // Step 2: Create a temporary request within the transaction
      const tempRequest = await Request.create(
        [{
          studentId: req.userId,
          status: 'OPEN',
          isSweeping: true,
          isMopping: false,
          isUrgent: false,
          notes: '[TRANSACTION DEMO] This request was created inside a transaction.',
          studentName: req.user.name,
          studentBlock: req.user.block || 'DEMO',
          studentRoom: req.user.roomNumber || '000',
        }],
        { session }
      );

      steps.push({
        step: 2,
        action: 'Request created (inside transaction)',
        documentId: tempRequest[0]._id.toString(),
        timestamp: new Date(),
      });

      // Step 3: Create audit log entry within the same transaction
      await AuditLog.create(
        [{
          collection: 'requests',
          documentId: tempRequest[0]._id,
          action: 'CREATE',
          performedBy: req.userId,
          performedByName: req.user.name,
          summary: '[TRANSACTION DEMO] Request created atomically with audit log.',
        }],
        { session }
      );

      steps.push({
        step: 3,
        action: 'Audit log created (inside same transaction)',
        timestamp: new Date(),
      });

      // Step 4: INTENTIONAL ABORT — Demonstrate rollback
      // By throwing an error, MongoDB rolls back ALL changes in this transaction
      throw new Error('INTENTIONAL_ROLLBACK');
    });
  } catch (error) {
    if (error.message === 'INTENTIONAL_ROLLBACK') {
      steps.push({
        step: 4,
        action: 'Transaction ABORTED (intentional rollback)',
        result: 'Both the request and audit log were rolled back. No data was persisted.',
        timestamp: new Date(),
      });
    } else {
      steps.push({
        step: 4,
        action: 'Transaction ABORTED (unexpected error)',
        error: error.message,
        timestamp: new Date(),
      });
    }
  } finally {
    await session.endSession();
    steps.push({
      step: 5,
      action: 'Session ended',
      timestamp: new Date(),
    });
  }

  res.json({
    success: true,
    title: 'Multi-Document ACID Transaction Demo',
    explanation: [
      'This endpoint demonstrates MongoDB ACID transactions.',
      'Steps 2 and 3 create a request and audit log inside a single transaction.',
      'Step 4 intentionally aborts the transaction, causing a ROLLBACK.',
      'Neither the request nor the audit log is persisted — proving atomicity.',
      'In production, accept_request uses real transactions to atomically assign cleaners.',
    ],
    steps,
    concepts: {
      Atomicity: 'Either all operations succeed or none do.',
      Consistency: 'The database moves from one valid state to another.',
      Isolation: 'Other queries cannot see uncommitted transaction data.',
      Durability: 'Once committed, data survives crashes (handled by WiredTiger).',
    },
  });
});

// ─────────────────────────────────────────────────────────────
//  GET /api/dbms/aggregation-showcase — Aggregation Pipeline Examples
//
//  ★ DBMS Feature: Aggregation Framework
//  Demonstrates multiple aggregation pipelines with explanations.
// ─────────────────────────────────────────────────────────────
router.get('/aggregation-showcase', auth, async (req, res) => {
  try {
    // Pipeline 1: Task type distribution ($group + $project)
    const taskDistribution = await Request.aggregate([
      { $match: { isDeleted: { $ne: true } } },
      {
        $group: {
          _id: {
            sweepingOnly: { $and: [{ $eq: ['$isSweeping', true] }, { $eq: ['$isMopping', false] }] },
            moppingOnly: { $and: [{ $eq: ['$isSweeping', false] }, { $eq: ['$isMopping', true] }] },
            both: { $and: [{ $eq: ['$isSweeping', true] }, { $eq: ['$isMopping', true] }] },
          },
          count: { $sum: 1 },
        },
      },
    ]);

    // Simplified task distribution
    const taskStats = await Request.aggregate([
      { $match: { isDeleted: { $ne: true } } },
      {
        $facet: {
          sweepingOnly: [
            { $match: { isSweeping: true, isMopping: false } },
            { $count: 'count' },
          ],
          moppingOnly: [
            { $match: { isSweeping: false, isMopping: true } },
            { $count: 'count' },
          ],
          both: [
            { $match: { isSweeping: true, isMopping: true } },
            { $count: 'count' },
          ],
        },
      },
      {
        $project: {
          sweepingOnly: { $arrayElemAt: ['$sweepingOnly.count', 0] },
          moppingOnly: { $arrayElemAt: ['$moppingOnly.count', 0] },
          both: { $arrayElemAt: ['$both.count', 0] },
        },
      },
    ]);

    // Pipeline 2: Feedback rating distribution ($group + $sort)
    const ratingDistribution = await Feedback.aggregate([
      {
        $group: {
          _id: '$rating',
          count: { $sum: 1 },
        },
      },
      { $sort: { _id: 1 } },
      {
        $project: {
          _id: 0,
          rating: '$_id',
          count: 1,
          label: { $concat: [{ $toString: '$_id' }, ' ★'] },
        },
      },
    ]);

    // Pipeline 3: Cleaner efficiency with $lookup
    const cleanerEfficiency = await Request.aggregate([
      {
        $match: {
          status: 'COMPLETED',
          'assignment.cleanerId': { $ne: null },
          'assignment.assignedAt': { $ne: null },
          'assignment.completedAt': { $ne: null },
          isDeleted: { $ne: true },
        },
      },
      {
        $group: {
          _id: '$assignment.cleanerId',
          completedJobs: { $sum: 1 },
          avgAcceptToCompleteMs: {
            $avg: { $subtract: ['$assignment.completedAt', '$assignment.assignedAt'] },
          },
          avgAcceptToStartMs: {
            $avg: {
              $cond: [
                { $ne: ['$assignment.startedAt', null] },
                { $subtract: ['$assignment.startedAt', '$assignment.assignedAt'] },
                null,
              ],
            },
          },
        },
      },
      {
        $lookup: {
          from: 'users',
          localField: '_id',
          foreignField: '_id',
          as: 'cleaner',
        },
      },
      { $unwind: { path: '$cleaner', preserveNullAndEmptyArrays: true } },
      {
        $project: {
          _id: 0,
          cleanerId: { $toString: '$_id' },
          cleanerName: { $ifNull: ['$cleaner.name', 'Unknown'] },
          completedJobs: 1,
          avgAcceptToCompleteMinutes: {
            $round: [{ $divide: [{ $ifNull: ['$avgAcceptToCompleteMs', 0] }, 60000] }, 1],
          },
          avgAcceptToStartMinutes: {
            $round: [{ $divide: [{ $ifNull: ['$avgAcceptToStartMs', 0] }, 60000] }, 1],
          },
        },
      },
      { $sort: { completedJobs: -1 } },
    ]);

    // Pipeline 4: Request volume by day of week ($dayOfWeek)
    const dayOfWeekStats = await Request.aggregate([
      { $match: { isDeleted: { $ne: true } } },
      {
        $group: {
          _id: { $dayOfWeek: '$createdAt' },
          count: { $sum: 1 },
        },
      },
      { $sort: { _id: 1 } },
      {
        $project: {
          _id: 0,
          dayNumber: '$_id',
          dayName: {
            $arrayElemAt: [
              ['', 'Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'],
              '$_id',
            ],
          },
          count: 1,
        },
      },
    ]);

    res.json({
      success: true,
      title: 'MongoDB Aggregation Pipeline Showcase',
      pipelines: [
        {
          name: 'Task Type Distribution',
          stages: ['$match', '$facet', '$count', '$project'],
          description: 'Uses $facet to run multiple sub-pipelines in parallel, counting sweeping-only, mopping-only, and combo requests.',
          result: taskStats[0] || { sweepingOnly: 0, moppingOnly: 0, both: 0 },
        },
        {
          name: 'Feedback Rating Distribution',
          stages: ['$group', '$sort', '$project'],
          description: 'Groups feedback by rating (1-5 stars) and counts occurrences for a histogram.',
          result: ratingDistribution,
        },
        {
          name: 'Cleaner Efficiency Analysis',
          stages: ['$match', '$group', '$lookup', '$unwind', '$project', '$sort'],
          description: 'Calculates average accept-to-complete time per cleaner, using $lookup to join with users collection.',
          result: cleanerEfficiency,
        },
        {
          name: 'Request Volume by Day of Week',
          stages: ['$match', '$group ($dayOfWeek)', '$sort', '$project'],
          description: 'Uses $dayOfWeek to extract the day from timestamps and group request volume.',
          result: dayOfWeekStats,
        },
      ],
    });
  } catch (error) {
    console.error('Aggregation showcase error:', error);
    res.status(500).json({ error: 'Failed to run aggregation showcase' });
  }
});

// ─────────────────────────────────────────────────────────────
//  GET /api/dbms/lookup-demo — $lookup Multi-Collection Join
//
//  ★ NoSQL Functionality: $lookup (MongoDB's JOIN equivalent)
//  Joins requests → users (student) → feedback in a single
//  aggregation pipeline, demonstrating how MongoDB handles
//  cross-collection relationships without traditional SQL JOINs.
// ─────────────────────────────────────────────────────────────
router.get('/lookup-demo', auth, async (req, res) => {
  try {
    const results = await Request.aggregate([
      // Only completed, non-deleted requests
      { $match: { status: 'COMPLETED', isDeleted: { $ne: true } } },
      { $limit: 10 },

      // ★ $lookup #1 — Join with Users to get student details
      {
        $lookup: {
          from: 'users',
          localField: 'studentId',
          foreignField: '_id',
          as: 'studentDetails',
        },
      },
      { $unwind: { path: '$studentDetails', preserveNullAndEmptyArrays: true } },

      // ★ $lookup #2 — Join with Users to get cleaner details
      {
        $lookup: {
          from: 'users',
          localField: 'assignment.cleanerId',
          foreignField: '_id',
          as: 'cleanerDetails',
        },
      },
      { $unwind: { path: '$cleanerDetails', preserveNullAndEmptyArrays: true } },

      // ★ $lookup #3 — Join with Feedback
      {
        $lookup: {
          from: 'feedbacks',
          localField: '_id',
          foreignField: 'requestId',
          as: 'feedback',
        },
      },
      { $unwind: { path: '$feedback', preserveNullAndEmptyArrays: true } },

      // Shape the output
      {
        $project: {
          _id: 0,
          requestId: { $toString: '$_id' },
          room: {
            $concat: [
              { $ifNull: ['$studentBlock', '?'] },
              '-',
              { $ifNull: ['$studentRoom', '?'] },
            ],
          },
          studentName: { $ifNull: ['$studentDetails.name', '$studentName'] },
          studentEmail: { $ifNull: ['$studentDetails.email', 'N/A'] },
          cleanerName: { $ifNull: ['$cleanerDetails.name', 'N/A'] },
          cleanerOnDuty: { $ifNull: ['$cleanerDetails.isOnDuty', false] },
          feedbackRating: { $ifNull: ['$feedback.rating', null] },
          feedbackComment: { $ifNull: ['$feedback.comment', null] },
          completedAt: '$assignment.completedAt',
        },
      },
    ]);

    res.json({
      success: true,
      title: '$lookup Multi-Collection Join Demo',
      description: [
        'This pipeline performs THREE $lookup operations in a single query:',
        '1. requests → users (student details)',
        '2. requests → users (cleaner details)',
        '3. requests → feedbacks (student rating)',
        'In SQL, this would require 3 JOIN clauses. MongoDB executes them sequentially in the pipeline.',
      ],
      lookupCount: 3,
      resultCount: results.length,
      results,
    });
  } catch (error) {
    console.error('Lookup demo error:', error);
    res.status(500).json({ error: 'Failed to run lookup demo' });
  }
});

// ─────────────────────────────────────────────────────────────
//  GET /api/dbms/random-sample — $sample Random Sampling
//
//  ★ NoSQL Functionality: $sample (Random Document Selection)
//  Uses MongoDB's $sample stage to fetch random documents.
//  Useful for QA auditing or random spot-checks.
//  This is a NoSQL-native feature not easily replicated in SQL.
// ─────────────────────────────────────────────────────────────
router.get('/random-sample', auth, async (req, res) => {
  try {
    const sampleSize = Math.min(parseInt(req.query.size) || 5, 20);

    // ★ $sample — Randomly selects documents from the collection
    const randomRequests = await Request.aggregate([
      { $match: { isDeleted: { $ne: true } } },
      { $sample: { size: sampleSize } },
      {
        $project: {
          _id: 0,
          requestId: { $toString: '$_id' },
          status: 1,
          room: {
            $concat: [
              { $ifNull: ['$studentBlock', '?'] },
              '-',
              { $ifNull: ['$studentRoom', '?'] },
            ],
          },
          studentName: 1,
          isUrgent: 1,
          createdAt: 1,
          tasks: {
            sweeping: '$isSweeping',
            mopping: '$isMopping',
          },
        },
      },
    ]);

    const randomFeedback = await Feedback.aggregate([
      { $sample: { size: sampleSize } },
      {
        $project: {
          _id: 0,
          feedbackId: { $toString: '$_id' },
          rating: 1,
          comment: 1,
          createdAt: 1,
        },
      },
    ]);

    res.json({
      success: true,
      title: '$sample Random Sampling Demo',
      description: [
        'MongoDB\'s $sample stage uses a pseudo-random cursor to select documents.',
        'When N < 5% of collection, it uses a random sort. Otherwise, it does a random walk.',
        'This is useful for QA auditing, A/B testing, or data sampling.',
        'Equivalent SQL (non-standard): SELECT * FROM table ORDER BY RANDOM() LIMIT N',
      ],
      sampleSize,
      randomRequests,
      randomFeedback,
    });
  } catch (error) {
    console.error('Random sample error:', error);
    res.status(500).json({ error: 'Failed to run random sample' });
  }
});

// ─────────────────────────────────────────────────────────────
//  GET /api/dbms/bucket-analysis — $bucket Histogram
//
//  ★ NoSQL Functionality: $bucket (Data Distribution Analysis)
//  Uses $bucket to create completion-time histograms.
//  Groups requests into time-based buckets for analysis.
// ─────────────────────────────────────────────────────────────
router.get('/bucket-analysis', auth, async (req, res) => {
  try {
    // Calculate completion time and bucket it
    const completionBuckets = await Request.aggregate([
      {
        $match: {
          status: 'COMPLETED',
          'assignment.assignedAt': { $ne: null },
          'assignment.completedAt': { $ne: null },
          isDeleted: { $ne: true },
        },
      },
      {
        // ★ $addFields — Compute completion time in minutes
        $addFields: {
          completionMinutes: {
            $divide: [
              { $subtract: ['$assignment.completedAt', '$assignment.assignedAt'] },
              60000,
            ],
          },
        },
      },
      {
        // ★ $bucket — Group into time-based histogram buckets
        $bucket: {
          groupBy: '$completionMinutes',
          boundaries: [0, 15, 30, 60, 120, 1440], // 0-15min, 15-30min, 30-60min, 1-2hr, 2hr-24hr
          default: 'over_24h',
          output: {
            count: { $sum: 1 },
            avgMinutes: { $avg: '$completionMinutes' },
            requests: {
              $push: {
                id: { $toString: '$_id' },
                room: { $concat: [{ $ifNull: ['$studentBlock', '?'] }, '-', { $ifNull: ['$studentRoom', '?'] }] },
                minutes: { $round: ['$completionMinutes', 1] },
              },
            },
          },
        },
      },
      {
        $project: {
          _id: 0,
          bucketLabel: {
            $switch: {
              branches: [
                { case: { $eq: ['$_id', 0] }, then: '0-15 minutes' },
                { case: { $eq: ['$_id', 15] }, then: '15-30 minutes' },
                { case: { $eq: ['$_id', 30] }, then: '30-60 minutes' },
                { case: { $eq: ['$_id', 60] }, then: '1-2 hours' },
                { case: { $eq: ['$_id', 120] }, then: '2-24 hours' },
              ],
              default: 'Over 24 hours',
            },
          },
          count: 1,
          avgMinutes: { $round: ['$avgMinutes', 1] },
          sampleRequests: { $slice: ['$requests', 3] }, // Only show 3 samples per bucket
        },
      },
    ]);

    // Also demonstrate $bucketAuto for rating distribution
    const ratingBuckets = await Feedback.aggregate([
      {
        // ★ $bucketAuto — MongoDB automatically determines bucket boundaries
        $bucketAuto: {
          groupBy: '$rating',
          buckets: 3, // MongoDB determines optimal 3 groups
          output: {
            count: { $sum: 1 },
            avgRating: { $avg: '$rating' },
          },
        },
      },
    ]);

    res.json({
      success: true,
      title: '$bucket / $bucketAuto Histogram Analysis',
      description: [
        '$bucket groups documents into fixed, user-defined ranges (like a histogram).',
        '$bucketAuto lets MongoDB automatically determine optimal bucket boundaries.',
        'Both are NoSQL-specific aggregation stages for data distribution analysis.',
      ],
      completionTimeHistogram: completionBuckets,
      ratingAutoHistogram: ratingBuckets,
    });
  } catch (error) {
    console.error('Bucket analysis error:', error);
    res.status(500).json({ error: 'Failed to run bucket analysis' });
  }
});

// ─────────────────────────────────────────────────────────────
//  GET /api/dbms/graph-lookup — $graphLookup Recursive Audit Trail
//
//  ★ NoSQL Functionality: $graphLookup (Recursive Graph Traversal)
//  Uses $graphLookup to build a chain of all audit events related
//  to a specific document or set of documents. Demonstrates
//  MongoDB's ability to perform recursive/graph queries within
//  the aggregation framework.
// ─────────────────────────────────────────────────────────────
router.get('/graph-lookup', auth, async (req, res) => {
  try {
    // Find all audit events and recursively connect related events
    // by matching performedBy → documentId (who acted → what was affected)
    const auditChain = await AuditLog.aggregate([
      // Start from recent audit logs
      { $sort: { timestamp: -1 } },
      { $limit: 5 },

      // ★ $graphLookup — Recursively find related audit entries
      // Starting from a user (performedBy), find all documents they touched,
      // then find all other actions on those same documents by other users.
      {
        $graphLookup: {
          from: 'auditlogs',
          startWith: '$documentId',             // Start from this document ID
          connectFromField: 'documentId',       // Follow the documentId field
          connectToField: 'documentId',         // Match against documentId in other docs
          as: 'relatedEvents',                  // Output array
          maxDepth: 2,                          // Limit recursion depth
          depthField: 'depth',                  // Track the recursion depth
          restrictSearchWithMatch: {
            timestamp: { $gte: new Date(Date.now() - 30 * 24 * 60 * 60 * 1000) },
          },
        },
      },

      // Shape the output
      {
        $project: {
          _id: 0,
          originEvent: {
            id: { $toString: '$_id' },
            action: '$action',
            collection: '$collection',
            documentId: { $toString: '$documentId' },
            summary: '$summary',
            performedBy: '$performedByName',
            timestamp: '$timestamp',
          },
          relatedEventsCount: { $size: '$relatedEvents' },
          relatedEvents: {
            $map: {
              input: { $slice: ['$relatedEvents', 5] }, // Limit to 5 related events
              as: 'evt',
              in: {
                id: { $toString: '$$evt._id' },
                action: '$$evt.action',
                summary: '$$evt.summary',
                performedBy: '$$evt.performedByName',
                depth: '$$evt.depth',
                timestamp: '$$evt.timestamp',
              },
            },
          },
        },
      },
    ]);

    res.json({
      success: true,
      title: '$graphLookup Recursive Audit Trail',
      description: [
        '$graphLookup performs recursive searches, similar to SQL recursive CTEs.',
        'Starting from recent audit events, it finds ALL related events on the same document.',
        'This creates a full "event chain" showing every action taken on a document over time.',
        'Use case: Trace the complete lifecycle of a cleaning request from creation to completion.',
      ],
      maxRecursionDepth: 2,
      chains: auditChain,
    });
  } catch (error) {
    console.error('Graph lookup error:', error);
    res.status(500).json({ error: 'Failed to run graph lookup' });
  }
});

// ─────────────────────────────────────────────────────────────
//  POST /api/dbms/materialized-view — $merge Materialized View
//
//  ★ NoSQL Functionality: $merge (Persist Aggregation Results)
//  Uses $merge to write aggregation results into a new collection
//  (request_summary_mv), creating a materialized view of
//  per-block request summaries for fast dashboard reads.
// ─────────────────────────────────────────────────────────────
router.post('/materialized-view', auth, async (req, res) => {
  try {
    const targetCollection = 'request_summary_mv';

    // ★ $merge — Persist aggregation results into a collection
    // This creates/updates a materialized view of block-level summaries
    await Request.aggregate([
      { $match: { isDeleted: { $ne: true } } },
      {
        $group: {
          _id: { $ifNull: ['$studentBlock', 'Unknown'] },
          totalRequests: { $sum: 1 },
          openRequests: {
            $sum: { $cond: [{ $eq: ['$status', 'OPEN'] }, 1, 0] },
          },
          completedRequests: {
            $sum: { $cond: [{ $eq: ['$status', 'COMPLETED'] }, 1, 0] },
          },
          cancelledRequests: {
            $sum: { $cond: [{ $eq: ['$status', 'CANCELLED_ROOM_LOCKED'] }, 1, 0] },
          },
          urgentRequests: {
            $sum: { $cond: [{ $eq: ['$isUrgent', true] }, 1, 0] },
          },
          avgCompletionMs: {
            $avg: {
              $cond: [
                {
                  $and: [
                    { $eq: ['$status', 'COMPLETED'] },
                    { $ne: ['$assignment.completedAt', null] },
                  ],
                },
                { $subtract: ['$assignment.completedAt', '$createdAt'] },
                null,
              ],
            },
          },
          lastRequestDate: { $max: '$createdAt' },
        },
      },
      {
        $project: {
          _id: 0,
          block: '$_id',
          totalRequests: 1,
          openRequests: 1,
          completedRequests: 1,
          cancelledRequests: 1,
          urgentRequests: 1,
          avgCompletionMinutes: {
            $round: [{ $divide: [{ $ifNull: ['$avgCompletionMs', 0] }, 60000] }, 1],
          },
          lastRequestDate: 1,
          generatedAt: new Date(),
        },
      },
      {
        // ★ $merge — Write results to a target collection
        // 'replace' mode: if a document with the same _id exists, replace it
        $merge: {
          into: targetCollection,
          on: '_id',
          whenMatched: 'replace',
          whenNotMatched: 'insert',
        },
      },
    ]);

    // Read back the materialized view to confirm
    const db = mongoose.connection.db;
    const materializedData = await db.collection(targetCollection).find({}).toArray();

    res.json({
      success: true,
      title: '$merge Materialized View Demo',
      description: [
        '$merge persists aggregation pipeline results into a target collection.',
        `The pipeline computed per-block summaries and wrote them to "${targetCollection}".`,
        'This creates a "materialized view" — pre-computed data for fast dashboard reads.',
        'Unlike regular views ($out), $merge can update existing documents incrementally.',
        'Refresh this endpoint anytime to update the materialized view with latest data.',
      ],
      targetCollection,
      documentCount: materializedData.length,
      materializedView: materializedData.map((d) => ({
        ...d,
        _id: d._id?.toString ? d._id.toString() : d._id,
      })),
    });
  } catch (error) {
    console.error('Materialized view error:', error);
    res.status(500).json({ error: 'Failed to create materialized view' });
  }
});

module.exports = router;
