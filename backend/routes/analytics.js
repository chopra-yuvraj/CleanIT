// ============================================================
//  CleanIT — Analytics Routes
// ============================================================
//
//  ★ DBMS Feature: Aggregation Pipeline
//  ─────────────────────────────────────────────────────────────
//  All analytics endpoints use MongoDB's aggregation framework,
//  which is one of the most powerful DBMS features in MongoDB.
//
//  Pipeline stages used:
//    $match    — Filter documents (like SQL WHERE)
//    $group    — Aggregate data (like SQL GROUP BY)
//    $lookup   — Left outer join with another collection (like SQL JOIN)
//    $unwind   — Flatten arrays from $lookup results
//    $project  — Shape the output (like SQL SELECT)
//    $sort     — Order results (like SQL ORDER BY)
//    $limit    — Limit results (like SQL LIMIT)
//    $count    — Count matching documents
//    $addFields — Add computed fields
//    $dateToString — Format dates for grouping
// ============================================================

const express = require('express');
const mongoose = require('mongoose');
const Request = require('../models/Request');
const Feedback = require('../models/Feedback');
const User = require('../models/User');
const auth = require('../middleware/auth');

const router = express.Router();

// ─────────────────────────────────────────────────────────────
//  GET /api/analytics/overview — High-level statistics
//
//  Aggregation: $match → $group → $project
// ─────────────────────────────────────────────────────────────
router.get('/overview', auth, async (req, res) => {
  try {
    const [stats] = await Request.aggregate([
      {
        // ★ $group — Aggregate across ALL requests
        $group: {
          _id: null,
          totalRequests: { $sum: 1 },
          completedRequests: {
            $sum: { $cond: [{ $eq: ['$status', 'COMPLETED'] }, 1, 0] },
          },
          cancelledRequests: {
            $sum: { $cond: [{ $eq: ['$status', 'CANCELLED_ROOM_LOCKED'] }, 1, 0] },
          },
          activeRequests: {
            $sum: {
              $cond: [
                { $in: ['$status', ['OPEN', 'ASSIGNED', 'IN_PROGRESS']] },
                1,
                0,
              ],
            },
          },
          urgentRequests: {
            $sum: { $cond: [{ $eq: ['$isUrgent', true] }, 1, 0] },
          },
          // Calculate average completion time (only for completed requests with assignment)
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
        },
      },
      {
        // ★ $project — Shape the output
        $project: {
          _id: 0,
          totalRequests: 1,
          completedRequests: 1,
          cancelledRequests: 1,
          activeRequests: 1,
          urgentRequests: 1,
          completionRate: {
            $cond: [
              { $eq: ['$totalRequests', 0] },
              0,
              {
                $multiply: [
                  { $divide: ['$completedRequests', '$totalRequests'] },
                  100,
                ],
              },
            ],
          },
          avgCompletionMinutes: {
            $cond: [
              { $eq: ['$avgCompletionMs', null] },
              0,
              { $divide: ['$avgCompletionMs', 60000] },
            ],
          },
        },
      },
    ]);

    // Get user counts
    const userStats = await User.aggregate([
      {
        $group: {
          _id: '$role',
          count: { $sum: 1 },
        },
      },
    ]);

    const users = {};
    userStats.forEach((s) => (users[s._id] = s.count));

    // Get average feedback rating using $lookup
    const [feedbackStats] = await Feedback.aggregate([
      {
        $group: {
          _id: null,
          avgRating: { $avg: '$rating' },
          totalFeedback: { $sum: 1 },
        },
      },
    ]);

    res.json({
      success: true,
      overview: {
        ...(stats || {
          totalRequests: 0,
          completedRequests: 0,
          cancelledRequests: 0,
          activeRequests: 0,
          urgentRequests: 0,
          completionRate: 0,
          avgCompletionMinutes: 0,
        }),
        totalStudents: users.student || 0,
        totalCleaners: users.cleaner || 0,
        avgRating: feedbackStats?.avgRating?.toFixed(1) || '0.0',
        totalFeedback: feedbackStats?.totalFeedback || 0,
      },
    });
  } catch (error) {
    console.error('Analytics overview error:', error);
    res.status(500).json({ error: 'Failed to fetch analytics' });
  }
});

// ─────────────────────────────────────────────────────────────
//  GET /api/analytics/by-block — Requests grouped by hostel block
//
//  ★ Aggregation: $group by studentBlock
// ─────────────────────────────────────────────────────────────
router.get('/by-block', auth, async (req, res) => {
  try {
    const blockStats = await Request.aggregate([
      {
        $group: {
          _id: { $ifNull: ['$studentBlock', 'Unknown'] },
          totalRequests: { $sum: 1 },
          completedRequests: {
            $sum: { $cond: [{ $eq: ['$status', 'COMPLETED'] }, 1, 0] },
          },
          urgentRequests: {
            $sum: { $cond: [{ $eq: ['$isUrgent', true] }, 1, 0] },
          },
        },
      },
      { $sort: { totalRequests: -1 } },
      {
        $project: {
          _id: 0,
          block: '$_id',
          totalRequests: 1,
          completedRequests: 1,
          urgentRequests: 1,
        },
      },
    ]);

    res.json({ success: true, blockStats });
  } catch (error) {
    console.error('Analytics by-block error:', error);
    res.status(500).json({ error: 'Failed to fetch block analytics' });
  }
});

// ─────────────────────────────────────────────────────────────
//  GET /api/analytics/cleaner-leaderboard — Top cleaners
//
//  ★ Aggregation: $match → $group → $lookup → $unwind → $sort
//  Demonstrates $lookup (MongoDB's JOIN equivalent)
// ─────────────────────────────────────────────────────────────
router.get('/cleaner-leaderboard', auth, async (req, res) => {
  try {
    const leaderboard = await Request.aggregate([
      // 1. Only completed requests with assignments
      {
        $match: {
          status: 'COMPLETED',
          'assignment.cleanerId': { $ne: null },
        },
      },
      // 2. Group by cleaner
      {
        $group: {
          _id: '$assignment.cleanerId',
          completedJobs: { $sum: 1 },
          cleanerName: { $first: '$assignment.cleanerName' },
          avgCompletionMs: {
            $avg: {
              $subtract: ['$assignment.completedAt', '$createdAt'],
            },
          },
        },
      },
      // 3. ★ $lookup — Join with Users collection to get cleaner details
      {
        $lookup: {
          from: 'users',              // Target collection
          localField: '_id',          // Field from Request aggregation
          foreignField: '_id',        // Field in Users collection
          as: 'cleanerDetails',       // Output array field
        },
      },
      // 4. ★ $unwind — Flatten the lookup result (array → single object)
      {
        $unwind: {
          path: '$cleanerDetails',
          preserveNullAndEmptyArrays: true,
        },
      },
      // 5. Shape the output
      {
        $project: {
          _id: 0,
          cleanerId: { $toString: '$_id' },
          cleanerName: { $ifNull: ['$cleanerDetails.name', '$cleanerName'] },
          completedJobs: 1,
          avgCompletionMinutes: {
            $round: [{ $divide: ['$avgCompletionMs', 60000] }, 1],
          },
        },
      },
      // 6. Sort by completed jobs (descending)
      { $sort: { completedJobs: -1 } },
      { $limit: 10 },
    ]);

    res.json({ success: true, leaderboard });
  } catch (error) {
    console.error('Cleaner leaderboard error:', error);
    res.status(500).json({ error: 'Failed to fetch leaderboard' });
  }
});

// ─────────────────────────────────────────────────────────────
//  GET /api/analytics/peak-hours — Requests by hour of day
//
//  ★ Aggregation: $project (extract hour) → $group → $sort
// ─────────────────────────────────────────────────────────────
router.get('/peak-hours', auth, async (req, res) => {
  try {
    const hourlyStats = await Request.aggregate([
      {
        $project: {
          hour: { $hour: '$createdAt' },
        },
      },
      {
        $group: {
          _id: '$hour',
          count: { $sum: 1 },
        },
      },
      { $sort: { _id: 1 } },
      {
        $project: {
          _id: 0,
          hour: '$_id',
          label: {
            $concat: [
              { $toString: '$_id' },
              ':00',
            ],
          },
          count: 1,
        },
      },
    ]);

    res.json({ success: true, hourlyStats });
  } catch (error) {
    console.error('Peak hours error:', error);
    res.status(500).json({ error: 'Failed to fetch peak hours' });
  }
});

// ─────────────────────────────────────────────────────────────
//  GET /api/analytics/status-distribution — Pie chart data
// ─────────────────────────────────────────────────────────────
router.get('/status-distribution', auth, async (req, res) => {
  try {
    const distribution = await Request.aggregate([
      {
        $group: {
          _id: '$status',
          count: { $sum: 1 },
        },
      },
      {
        $project: {
          _id: 0,
          status: '$_id',
          count: 1,
        },
      },
    ]);

    res.json({ success: true, distribution });
  } catch (error) {
    console.error('Status distribution error:', error);
    res.status(500).json({ error: 'Failed to fetch distribution' });
  }
});

// ─────────────────────────────────────────────────────────────
//  GET /api/analytics/trends — Daily request trends (last 30 days)
//
//  ★ Aggregation: $match (date range) → $group (by date) → $sort
// ─────────────────────────────────────────────────────────────
router.get('/trends', auth, async (req, res) => {
  try {
    const thirtyDaysAgo = new Date();
    thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);

    const trends = await Request.aggregate([
      {
        $match: {
          createdAt: { $gte: thirtyDaysAgo },
        },
      },
      {
        $group: {
          _id: {
            $dateToString: { format: '%Y-%m-%d', date: '$createdAt' },
          },
          count: { $sum: 1 },
          completed: {
            $sum: { $cond: [{ $eq: ['$status', 'COMPLETED'] }, 1, 0] },
          },
        },
      },
      { $sort: { _id: 1 } },
      {
        $project: {
          _id: 0,
          date: '$_id',
          count: 1,
          completed: 1,
        },
      },
    ]);

    res.json({ success: true, trends });
  } catch (error) {
    console.error('Trends error:', error);
    res.status(500).json({ error: 'Failed to fetch trends' });
  }
});

// ─────────────────────────────────────────────────────────────
//  GET /api/analytics/task-distribution — Task type breakdown
//
//  ★ Aggregation: $match → $facet → $project
//  Uses $facet to run multiple sub-pipelines in parallel.
// ─────────────────────────────────────────────────────────────
router.get('/task-distribution', auth, async (req, res) => {
  try {
    const [result] = await Request.aggregate([
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
          urgent: [
            { $match: { isUrgent: true } },
            { $count: 'count' },
          ],
        },
      },
      {
        $project: {
          sweepingOnly: { $ifNull: [{ $arrayElemAt: ['$sweepingOnly.count', 0] }, 0] },
          moppingOnly: { $ifNull: [{ $arrayElemAt: ['$moppingOnly.count', 0] }, 0] },
          both: { $ifNull: [{ $arrayElemAt: ['$both.count', 0] }, 0] },
          urgent: { $ifNull: [{ $arrayElemAt: ['$urgent.count', 0] }, 0] },
        },
      },
    ]);

    res.json({ success: true, taskDistribution: result || {} });
  } catch (error) {
    console.error('Task distribution error:', error);
    res.status(500).json({ error: 'Failed to fetch task distribution' });
  }
});

// ─────────────────────────────────────────────────────────────
//  GET /api/analytics/rating-distribution — Feedback histogram
//
//  ★ Aggregation: $group (by rating) → $sort
// ─────────────────────────────────────────────────────────────
router.get('/rating-distribution', auth, async (req, res) => {
  try {
    const distribution = await Feedback.aggregate([
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

    // Ensure all ratings 1-5 are represented
    const fullDistribution = [1, 2, 3, 4, 5].map((r) => {
      const found = distribution.find((d) => d.rating === r);
      return found || { rating: r, count: 0, label: `${r} ★` };
    });

    res.json({ success: true, ratingDistribution: fullDistribution });
  } catch (error) {
    console.error('Rating distribution error:', error);
    res.status(500).json({ error: 'Failed to fetch rating distribution' });
  }
});

// ─────────────────────────────────────────────────────────────
//  GET /api/analytics/cleaner-efficiency — Detailed cleaner metrics
//
//  ★ Aggregation: $match → $group → $lookup → $unwind → $project
//  Calculates time-to-accept and time-to-complete per cleaner.
// ─────────────────────────────────────────────────────────────
router.get('/cleaner-efficiency', auth, async (req, res) => {
  try {
    const efficiency = await Request.aggregate([
      {
        $match: {
          status: 'COMPLETED',
          'assignment.cleanerId': { $ne: null },
          'assignment.assignedAt': { $ne: null },
          isDeleted: { $ne: true },
        },
      },
      {
        $group: {
          _id: '$assignment.cleanerId',
          completedJobs: { $sum: 1 },
          avgTotalTimeMs: {
            $avg: {
              $cond: [
                { $ne: ['$assignment.completedAt', null] },
                { $subtract: ['$assignment.completedAt', '$assignment.assignedAt'] },
                null,
              ],
            },
          },
          avgResponseTimeMs: {
            $avg: {
              $cond: [
                { $ne: ['$assignment.startedAt', null] },
                { $subtract: ['$assignment.startedAt', '$assignment.assignedAt'] },
                null,
              ],
            },
          },
          avgCleaningTimeMs: {
            $avg: {
              $cond: [
                {
                  $and: [
                    { $ne: ['$assignment.startedAt', null] },
                    { $ne: ['$assignment.completedAt', null] },
                  ],
                },
                { $subtract: ['$assignment.completedAt', '$assignment.startedAt'] },
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
          isOnDuty: { $ifNull: ['$cleaner.isOnDuty', false] },
          completedJobs: 1,
          avgTotalMinutes: {
            $round: [{ $divide: [{ $ifNull: ['$avgTotalTimeMs', 0] }, 60000] }, 1],
          },
          avgResponseMinutes: {
            $round: [{ $divide: [{ $ifNull: ['$avgResponseTimeMs', 0] }, 60000] }, 1],
          },
          avgCleaningMinutes: {
            $round: [{ $divide: [{ $ifNull: ['$avgCleaningTimeMs', 0] }, 60000] }, 1],
          },
        },
      },
      { $sort: { completedJobs: -1 } },
    ]);

    res.json({ success: true, efficiency });
  } catch (error) {
    console.error('Cleaner efficiency error:', error);
    res.status(500).json({ error: 'Failed to fetch efficiency data' });
  }
});

// ─────────────────────────────────────────────────────────────
//  GET /api/analytics/cleaner-summary/:id — Single cleaner profile
//
//  ★ User-Defined Functionality: Cleaner Performance Summary
//  Returns a comprehensive performance profile for one cleaner:
//  total jobs, avg completion time, average rating, busiest day.
//  Uses $lookup across requests + feedback + users collections.
// ─────────────────────────────────────────────────────────────
router.get('/cleaner-summary/:id', auth, async (req, res) => {
  try {
    const cleanerId = new mongoose.Types.ObjectId(req.params.id);

    // 1. Cleaner info
    const cleaner = await User.findOne({ _id: cleanerId, role: 'cleaner' }).lean();
    if (!cleaner) {
      return res.status(404).json({ error: 'Cleaner not found' });
    }

    // 2. Job stats via aggregation
    const [jobStats] = await Request.aggregate([
      {
        $match: {
          'assignment.cleanerId': cleanerId,
          isDeleted: { $ne: true },
        },
      },
      {
        $group: {
          _id: null,
          totalJobs: { $sum: 1 },
          completedJobs: {
            $sum: { $cond: [{ $eq: ['$status', 'COMPLETED'] }, 1, 0] },
          },
          cancelledJobs: {
            $sum: { $cond: [{ $eq: ['$status', 'CANCELLED_ROOM_LOCKED'] }, 1, 0] },
          },
          avgCompletionMs: {
            $avg: {
              $cond: [
                {
                  $and: [
                    { $eq: ['$status', 'COMPLETED'] },
                    { $ne: ['$assignment.completedAt', null] },
                    { $ne: ['$assignment.assignedAt', null] },
                  ],
                },
                { $subtract: ['$assignment.completedAt', '$assignment.assignedAt'] },
                null,
              ],
            },
          },
        },
      },
    ]);

    // 3. Average rating from feedback for this cleaner's completed requests
    const [ratingStats] = await Request.aggregate([
      {
        $match: {
          'assignment.cleanerId': cleanerId,
          status: 'COMPLETED',
          isDeleted: { $ne: true },
        },
      },
      {
        $lookup: {
          from: 'feedbacks',
          localField: '_id',
          foreignField: 'requestId',
          as: 'feedback',
        },
      },
      { $unwind: { path: '$feedback', preserveNullAndEmptyArrays: false } },
      {
        $group: {
          _id: null,
          avgRating: { $avg: '$feedback.rating' },
          totalRatings: { $sum: 1 },
        },
      },
    ]);

    // 4. Busiest day of the week
    const busiestDay = await Request.aggregate([
      {
        $match: {
          'assignment.cleanerId': cleanerId,
          status: 'COMPLETED',
          isDeleted: { $ne: true },
        },
      },
      {
        $group: {
          _id: { $dayOfWeek: '$assignment.assignedAt' },
          count: { $sum: 1 },
        },
      },
      { $sort: { count: -1 } },
      { $limit: 1 },
      {
        $project: {
          _id: 0,
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
      summary: {
        cleanerId: cleaner._id.toString(),
        cleanerName: cleaner.name,
        isOnDuty: cleaner.isOnDuty,
        totalJobs: jobStats?.totalJobs || 0,
        completedJobs: jobStats?.completedJobs || 0,
        cancelledJobs: jobStats?.cancelledJobs || 0,
        avgCompletionMinutes: jobStats?.avgCompletionMs
          ? Math.round((jobStats.avgCompletionMs / 60000) * 10) / 10
          : 0,
        avgRating: ratingStats?.avgRating
          ? Math.round(ratingStats.avgRating * 10) / 10
          : null,
        totalRatings: ratingStats?.totalRatings || 0,
        busiestDay: busiestDay[0] || null,
      },
    });
  } catch (error) {
    console.error('Cleaner summary error:', error);
    res.status(500).json({ error: 'Failed to fetch cleaner summary' });
  }
});

module.exports = router;
