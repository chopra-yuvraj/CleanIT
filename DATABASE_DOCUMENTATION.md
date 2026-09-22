# CleanIT — Complete Database Documentation

> **Purpose**: This document serves as the comprehensive MongoDB database documentation for the CleanIT DBMS project. It covers schema design, indexing strategies, aggregation pipelines, transactions, and all advanced DBMS features implemented in the system.

---

## 1. Architecture Overview

```
┌─────────────────┐         ┌───────────────────────┐         ┌──────────────────┐
│  Flutter App    │  HTTP   │   Express.js Server   │ Mongoose │    MongoDB       │
│  (Frontend)     │────────►│   (Backend API)       │─────────►│    Atlas / Local │
│                 │◄────────│                       │◄─────────│                  │
│  Services:      │  JSON   │  Middleware:          │          │  Collections:    │
│  • AuthService  │         │  • JWT Auth           │          │  • users         │
│  • RequestSvc   │         │  • Role Guard         │          │  • requests      │
│  • AnalyticsSvc │         │  • Rate Limiter       │          │  • feedbacks     │
│  • QRService    │         │  • Mongo Sanitize     │          │  • auditlogs     │
│  • ApiClient    │         │                       │          │                  │
│                 │         │  Routes:              │          │  Features:       │
│                 │         │  • /api/auth          │          │  • Transactions  │
│                 │         │  • /api/requests      │          │  • TTL Indexes   │
│                 │         │  • /api/feedback      │          │  • Text Search   │
│                 │         │  • /api/analytics     │          │  • Aggregation   │
│                 │         │  • /api/admin         │          │  • $lookup       │
│                 │         │  • /api/dbms          │          │  • $graphLookup  │
└─────────────────┘         └───────────────────────┘         └──────────────────┘
```

**Design Pattern**: Frontend → Backend API → Service/Business Logic → MongoDB

The Flutter frontend communicates exclusively through HTTP REST calls to the Express.js backend. The backend uses Mongoose as an ODM (Object-Document Mapper) to interact with MongoDB. There is **no direct database access** from the frontend.

---

## 2. Collection Schemas

### 2.1 `users` Collection

**Purpose**: Stores all user profiles — students, cleaners, and admins.

| Field | Type | Constraints | Purpose |
|---|---|---|---|
| `_id` | ObjectId | Primary Key | Auto-generated document ID |
| `email` | String | **Unique**, Required | Login identifier |
| `password` | String | Required, Min 6 | bcrypt-hashed password |
| `name` | String | Required | Display name |
| `role` | String (enum) | Required: `student`, `cleaner`, `admin` | Access control |
| `block` | String | Required if `role=student` | Hostel block (A, B, C, D) |
| `roomNumber` | String | Required if `role=student` | Room number |
| `fcmToken` | String | Optional | Firebase push notification token |
| `isOnDuty` | Boolean | Default: `false` | Cleaner availability status |
| `createdAt` | Date | Auto (timestamps) | Registration timestamp |
| `updatedAt` | Date | Auto (timestamps) | Last update timestamp |

**Design Decision**: Students and cleaners share one collection (distinguished by `role`) because authentication and JWT generation are identical for all user types. This avoids duplicating auth logic across separate collections.

---

### 2.2 `requests` Collection

**Purpose**: Core transactional collection — cleaning jobs created by students.

| Field | Type | Constraints | Purpose |
|---|---|---|---|
| `_id` | ObjectId | Primary Key | Request ID |
| `studentId` | ObjectId (ref: User) | Required | Student who created the request |
| `status` | String (enum) | Required | `OPEN`, `ASSIGNED`, `IN_PROGRESS`, `COMPLETED`, `CANCELLED_ROOM_LOCKED` |
| `isSweeping` | Boolean | Required | Sweeping task requested |
| `isMopping` | Boolean | Required | Mopping task requested |
| `isUrgent` | Boolean | Default: `false` | Priority flag |
| `notes` | String | Optional | Student instructions (text-indexed) |
| `assignment` | **Embedded Document** | Optional | Cleaner assignment details |
| `assignment.cleanerId` | ObjectId (ref: User) | | Assigned cleaner |
| `assignment.cleanerName` | String | | Denormalized cleaner name |
| `assignment.assignedAt` | Date | | When cleaner accepted |
| `assignment.startedAt` | Date | | When cleaner started cleaning |
| `assignment.completedAt` | Date | | When job was completed/cancelled |
| `assignment.failureReason` | String | | e.g., `room_locked` |
| `studentName` | String | Denormalized | Copied at creation time |
| `studentBlock` | String | Denormalized | Copied at creation time |
| `studentRoom` | String | Denormalized | Copied at creation time |
| `isDeleted` | Boolean | Default: `false` | Soft delete flag |
| `deletedAt` | Date | | Deletion timestamp |
| `deletedBy` | ObjectId (ref: User) | | Who deleted it |
| `createdAt` | Date | Auto | Creation timestamp |
| `updatedAt` | Date | Auto | Last update timestamp |

**Design Decisions**:
1. **Embedded `assignment` subdocument**: In a relational database, assignments would be a separate table. In MongoDB, assignments have a strict 1:1 relationship with requests and are always queried together. Embedding prevents costly `$lookup` joins on the read-heavy cleaner broadcast path.

2. **Denormalized student info** (`studentName`, `studentBlock`, `studentRoom`): Copied from the user document at request creation time. This allows the cleaner broadcast view to fetch all `OPEN` requests from a single collection without joins, optimizing the critical read path.

3. **Soft delete** (`isDeleted`, `deletedAt`, `deletedBy`): Instead of physically removing completed requests, we flag them. This preserves referential integrity with feedback records and enables audit/recovery workflows.

---

### 2.3 `feedbacks` Collection

**Purpose**: Post-completion ratings and comments from students.

| Field | Type | Constraints | Purpose |
|---|---|---|---|
| `_id` | ObjectId | Primary Key | Feedback ID |
| `requestId` | ObjectId (ref: Request) | **Unique** | One feedback per request |
| `studentId` | ObjectId (ref: User) | Required | Student who submitted |
| `rating` | Number | Required, 1-5 | Star rating |
| `comment` | String | Optional | Text comment |
| `createdAt` | Date | Auto | Submission timestamp |

**Design Decision**: Feedback is stored in a separate collection (not embedded in requests) because:
- It is created *after* the request lifecycle completes
- It isn't needed during the core operational flow
- Keeping it separate prevents unbounded document growth in the `requests` collection

---

### 2.4 `auditlogs` Collection

**Purpose**: Change Data Capture — records every state change across all collections.

| Field | Type | Constraints | Purpose |
|---|---|---|---|
| `_id` | ObjectId | Primary Key | Log entry ID |
| `collection` | String | Required | Which collection was modified |
| `documentId` | ObjectId | Required | Which document was modified |
| `action` | String (enum) | Required | `CREATE`, `UPDATE`, `DELETE`, `BULK_CANCEL` |
| `performedBy` | ObjectId | Required | Who performed the action |
| `performedByName` | String | Denormalized | User's name at time of action |
| `changes` | Mixed/Object | Optional | Before/after field values |
| `summary` | String | Required | Human-readable description |
| `timestamp` | Date | Default: `now` | When the action occurred |
| `expireAt` | Date | **TTL indexed** | Auto-deletion after 90 days |

**Design Decision**: The `expireAt` field is set 90 days in the future at creation time. MongoDB's TTL index monitor automatically removes documents past their expiry, demonstrating **automated data lifecycle management** at the storage engine level.

---

## 3. Entity Relationships

```
┌──────────┐        ┌──────────────┐        ┌──────────────┐
│  USERS   │───────►│   REQUESTS   │───────►│   FEEDBACK   │
│          │ 1:N    │              │ 1:1    │              │
│ student  │creates │ studentId    │has one │ requestId    │
│ cleaner  │        │ assignment   │        │ studentId    │
│ admin    │        │   (embedded) │        │ rating       │
└──────────┘        └──────────────┘        └──────────────┘
     │                    │
     │ 1:N (audit)        │ 1:N (audit)
     ▼                    ▼
┌──────────────────────────┐
│       AUDIT LOGS         │
│ collection, documentId   │
│ action, changes          │
│ expireAt (TTL: 90 days)  │
└──────────────────────────┘
```

- **Users → Requests**: One-to-Many (a student can create many requests over time)
- **Users → Requests (assignment)**: One-to-Many (a cleaner can be assigned many requests)
- **Requests → Feedback**: One-to-One (enforced by unique index on `requestId`)
- **All → AuditLogs**: Many-to-Many observer pattern (any entity change generates a log)

---

## 4. Index Catalog

### 4.1 `users` Indexes

| Index Name | Keys | Type | Purpose |
|---|---|---|---|
| `_id_` | `{ _id: 1 }` | Default | Primary key lookup |
| `email_1` | `{ email: 1 }` | **Unique** | Fast login, prevents duplicate registrations |
| `role_1_isOnDuty_1` | `{ role: 1, isOnDuty: 1 }` | **Compound** | Fetches on-duty cleaners without scanning all users |
| `idx_user_text_search` | `{ name: "text", email: "text" }` | **Text** | Admin full-text user search |
| `fcmToken_1` | `{ fcmToken: 1 }` | **Sparse** | Only indexes users with push tokens |

### 4.2 `requests` Indexes

| Index Name | Keys | Type | Purpose |
|---|---|---|---|
| `_id_` | `{ _id: 1 }` | Default | Primary key lookup |
| `idx_one_active_request_per_student` | `{ studentId: 1 }` | **Partial Unique** | Enforces one active request per student |
| | | Filter: `status IN ['OPEN','ASSIGNED','IN_PROGRESS']` | |
| `idx_open_requests_broadcast` | `{ status: 1, isUrgent: -1, createdAt: 1 }` | **Compound** | Cleaner broadcast: open requests sorted by urgency |
| `idx_student_history` | `{ studentId: 1, createdAt: -1 }` | **Compound** | Student request history (sorted by date) |
| `idx_cleaner_jobs` | `{ "assignment.cleanerId": 1, status: 1 }` | **Compound** | Cleaner's active/completed jobs |
| `idx_notes_text_search` | `{ notes: "text" }` | **Text** | Full-text search on request notes |

### 4.3 `feedbacks` Indexes

| Index Name | Keys | Type | Purpose |
|---|---|---|---|
| `_id_` | `{ _id: 1 }` | Default | Primary key lookup |
| `idx_one_feedback_per_request` | `{ requestId: 1 }` | **Unique** | Prevents duplicate feedback per request |
| `idx_student_feedback` | `{ studentId: 1, createdAt: -1 }` | **Compound** | Student feedback history |

### 4.4 `auditlogs` Indexes

| Index Name | Keys | Type | Purpose |
|---|---|---|---|
| `_id_` | `{ _id: 1 }` | Default | Primary key lookup |
| `idx_ttl_auto_expire` | `{ expireAt: 1 }` | **TTL** | Auto-deletes logs after 90 days |
| `idx_audit_lookup` | `{ collection: 1, documentId: 1 }` | **Compound** | Query logs for a specific document |
| `idx_audit_recent` | `{ timestamp: -1 }` | **Descending** | Admin dashboard: recent activity |

---

## 5. User-Defined Functionalities (Application Logic — 5+)

These are features built in application code that solve real user problems using the database as a backing store.

### 5.1 Password Change

**Location**: `backend/routes/auth.js` — `PUT /api/auth/change-password`

```javascript
// Fetch user WITH password field (normally excluded by select: false)
const user = await User.findById(req.userId).select('+password');

// Verify current password
const isMatch = await user.comparePassword(currentPassword);
if (!isMatch) {
  return res.status(401).json({ error: 'Incorrect password' });
}

// Update password (pre-save hook will hash it with bcrypt)
user.password = newPassword;
await user.save();
```

**What it does**: Authenticated users can change their password. The endpoint validates the current password via `bcrypt.compare()` before accepting the new one. The Mongoose pre-save hook automatically hashes the new password before persisting.

**DBMS Concepts Used**: Schema validation, pre-save hooks, `select: false` field exclusion.

---

### 5.2 Admin Restore Soft-Deleted Request

**Location**: `backend/routes/admin.js` — `PUT /api/admin/restore-request/:id`

```javascript
const session = await mongoose.startSession();
await session.withTransaction(async () => {
  // 1. Restore the deleted request
  const request = await Request.findOneAndUpdate(
    { _id: req.params.id, isDeleted: true },
    { $set: { isDeleted: false, deletedAt: null, deletedBy: null } },
    { new: true, session }
  );

  // 2. Create audit log (same transaction)
  await AuditLog.create([{
    collection: 'requests',
    documentId: request._id,
    action: 'UPDATE',
    summary: `Soft-deleted request restored by admin`,
  }], { session });
});
```

**What it does**: Admins can undo a soft-delete, recovering a request that was previously removed. Uses a **multi-document ACID transaction** to atomically restore the request and create an audit log entry — ensuring both succeed or neither does.

**DBMS Concepts Used**: Multi-document transactions, soft delete recovery, atomicity.

---

### 5.3 Student Cancel Own Request

**Location**: `backend/routes/requests.js` — `POST /api/requests/:id/cancel`

```javascript
const request = await Request.findOneAndUpdate(
  {
    _id: req.params.id,
    studentId: req.userId,
    status: 'OPEN',         // ← Can only cancel if still OPEN
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
```

**What it does**: Students can cancel their own OPEN request before a cleaner accepts it. The atomic `findOneAndUpdate` with the `status: 'OPEN'` filter ensures that if a cleaner accepts the request between the student tapping "Cancel" and the update executing, the cancellation safely fails with a conflict response.

**DBMS Concepts Used**: Atomic update with filter conditions, optimistic concurrency.

---

### 5.4 Cleaner Performance Summary

**Location**: `backend/routes/analytics.js` — `GET /api/analytics/cleaner-summary/:id`

```javascript
// Job stats via aggregation
const [jobStats] = await Request.aggregate([
  { $match: { 'assignment.cleanerId': cleanerId, isDeleted: { $ne: true } } },
  { $group: {
      _id: null,
      totalJobs: { $sum: 1 },
      completedJobs: { $sum: { $cond: [{ $eq: ['$status', 'COMPLETED'] }, 1, 0] } },
      avgCompletionMs: { $avg: { $subtract: ['$assignment.completedAt', '$assignment.assignedAt'] } },
  }},
]);

// Average rating via $lookup across requests + feedback
const [ratingStats] = await Request.aggregate([
  { $match: { 'assignment.cleanerId': cleanerId, status: 'COMPLETED' } },
  { $lookup: { from: 'feedbacks', localField: '_id', foreignField: 'requestId', as: 'feedback' } },
  { $unwind: '$feedback' },
  { $group: { _id: null, avgRating: { $avg: '$feedback.rating' }, totalRatings: { $sum: 1 } } },
]);
```

**What it does**: Returns a comprehensive performance profile for a single cleaner including: total/completed/cancelled jobs, average completion time, average rating (via cross-collection `$lookup`), and busiest day of the week.

**DBMS Concepts Used**: Aggregation pipeline, `$lookup` cross-collection join, `$group`, `$dayOfWeek`.

---

### 5.5 Admin Dashboard Counts

**Location**: `backend/routes/admin.js` — `GET /api/admin/dashboard-counts`

```javascript
const [totalStudents, totalCleaners, totalAdmins, activeRequests, ...] = await Promise.all([
  User.countDocuments({ role: 'student' }),
  User.countDocuments({ role: 'cleaner' }),
  User.countDocuments({ role: 'admin' }),
  Request.countDocuments({ status: { $in: ['OPEN', 'ASSIGNED', 'IN_PROGRESS'] } }),
  Request.countDocuments({ status: 'COMPLETED' }),
  Feedback.countDocuments({}),
  // Completed requests without feedback (pending reviews)
  Request.countDocuments({ status: 'COMPLETED', _id: { $nin: await Feedback.distinct('requestId') } }),
  AuditLog.countDocuments({ timestamp: { $gte: new Date(Date.now() - 24*60*60*1000) } }),
]);
```

**What it does**: Returns at-a-glance admin metrics by aggregating counts across **all four collections** (users, requests, feedbacks, auditlogs) in a single endpoint. Uses `Promise.all` for parallel query execution and `$nin` with `distinct()` to compute pending feedback reviews.

**DBMS Concepts Used**: Cross-collection aggregation, `countDocuments`, `distinct()`, `$nin` operator, parallel query execution.

---

## 6. NoSQL / MongoDB Functionalities (Database Engine — 5+)

These features leverage **specific MongoDB/NoSQL capabilities** that distinguish it from traditional relational databases.

### 6.1 `$lookup` Multi-Collection Join

**Location**: `backend/routes/dbms.js` — `GET /api/dbms/lookup-demo`

```javascript
const results = await Request.aggregate([
  { $match: { status: 'COMPLETED' } },

  // ★ $lookup #1 — Join with Users (student details)
  { $lookup: { from: 'users', localField: 'studentId', foreignField: '_id', as: 'studentDetails' } },
  { $unwind: { path: '$studentDetails', preserveNullAndEmptyArrays: true } },

  // ★ $lookup #2 — Join with Users (cleaner details)
  { $lookup: { from: 'users', localField: 'assignment.cleanerId', foreignField: '_id', as: 'cleanerDetails' } },
  { $unwind: { path: '$cleanerDetails', preserveNullAndEmptyArrays: true } },

  // ★ $lookup #3 — Join with Feedback
  { $lookup: { from: 'feedbacks', localField: '_id', foreignField: 'requestId', as: 'feedback' } },
  { $unwind: { path: '$feedback', preserveNullAndEmptyArrays: true } },

  { $project: { requestId: { $toString: '$_id' }, studentName: '$studentDetails.name', ... } },
]);
```

**What it does**: Performs THREE `$lookup` operations in a single aggregation pipeline, joining requests → users (student) → users (cleaner) → feedback. This is MongoDB's equivalent of SQL's `JOIN` clause, demonstrating how document databases handle cross-collection relationships.

**Why it matters**: In a relational database, this would be `SELECT ... FROM requests JOIN users ON ... JOIN feedbacks ON ...`. MongoDB's pipeline approach is more flexible — lookups can be conditional, filtered, and even nested.

---

### 6.2 `$sample` Random Sampling

**Location**: `backend/routes/dbms.js` — `GET /api/dbms/random-sample`

```javascript
// ★ $sample — Randomly selects N documents from the collection
const randomRequests = await Request.aggregate([
  { $match: { isDeleted: { $ne: true } } },
  { $sample: { size: sampleSize } },   // ← NoSQL-specific random selection
  { $project: { requestId: { $toString: '$_id' }, status: 1, ... } },
]);
```

**What it does**: Uses MongoDB's `$sample` aggregation stage to select random documents. When `N < 5%` of the collection, MongoDB uses a pseudo-random sort. Otherwise, it performs a random walk over the collection.

**Why it matters**: SQL equivalents like `ORDER BY RANDOM() LIMIT N` require sorting the entire table. MongoDB's `$sample` is a native, optimized operation that avoids full-table sorts. Use cases: QA auditing, A/B testing, data sampling for ML.

---

### 6.3 `$bucket` / `$bucketAuto` Histogram Analysis

**Location**: `backend/routes/dbms.js` — `GET /api/dbms/bucket-analysis`

```javascript
const completionBuckets = await Request.aggregate([
  { $match: { status: 'COMPLETED', ... } },
  // Compute completion time in minutes
  { $addFields: {
      completionMinutes: { $divide: [{ $subtract: ['$assignment.completedAt', '$assignment.assignedAt'] }, 60000] },
  }},
  // ★ $bucket — Group into fixed histogram ranges
  { $bucket: {
      groupBy: '$completionMinutes',
      boundaries: [0, 15, 30, 60, 120, 1440],    // 0-15, 15-30, 30-60, 1-2hr, 2-24hr
      default: 'over_24h',
      output: { count: { $sum: 1 }, avgMinutes: { $avg: '$completionMinutes' } },
  }},
]);

// ★ $bucketAuto — MongoDB auto-determines optimal bucket boundaries
const ratingBuckets = await Feedback.aggregate([
  { $bucketAuto: { groupBy: '$rating', buckets: 3, output: { count: { $sum: 1 } } } },
]);
```

**What it does**: `$bucket` creates fixed-range histograms (e.g., 0-15min, 15-30min, etc.) for completion time analysis. `$bucketAuto` lets MongoDB automatically determine optimal bucket boundaries for rating distribution.

**Why it matters**: These are MongoDB-specific aggregation stages with no direct SQL equivalent. They perform binning/histogramming at the database level, avoiding transferring raw data to the application.

---

### 6.4 `$graphLookup` Recursive Audit Trail

**Location**: `backend/routes/dbms.js` — `GET /api/dbms/graph-lookup`

```javascript
const auditChain = await AuditLog.aggregate([
  { $sort: { timestamp: -1 } },
  { $limit: 5 },

  // ★ $graphLookup — Recursive graph traversal
  { $graphLookup: {
      from: 'auditlogs',
      startWith: '$documentId',           // Start from this document
      connectFromField: 'documentId',     // Follow documentId
      connectToField: 'documentId',       // Match against documentId
      as: 'relatedEvents',               // Output array
      maxDepth: 2,                        // Limit recursion
      depthField: 'depth',               // Track depth
      restrictSearchWithMatch: {
        timestamp: { $gte: new Date(Date.now() - 30 * 24 * 60 * 60 * 1000) },
      },
  }},
]);
```

**What it does**: Uses `$graphLookup` to build a recursive chain of all audit events related to a given document. Starting from recent audit entries, it finds ALL other audit entries referencing the same document — creating a complete event timeline.

**Why it matters**: This is MongoDB's equivalent of SQL recursive CTEs (`WITH RECURSIVE`), but built into the aggregation pipeline. It enables graph-like traversals without a separate graph database. Use case: Trace the complete lifecycle of a cleaning request from creation → acceptance → start → completion.

---

### 6.5 `$merge` Materialized View

**Location**: `backend/routes/dbms.js` — `POST /api/dbms/materialized-view`

```javascript
await Request.aggregate([
  { $match: { isDeleted: { $ne: true } } },
  { $group: {
      _id: '$studentBlock',
      totalRequests: { $sum: 1 },
      completedRequests: { $sum: { $cond: [{ $eq: ['$status', 'COMPLETED'] }, 1, 0] } },
      avgCompletionMs: { $avg: { ... } },
  }},
  { $project: { block: '$_id', totalRequests: 1, ... } },

  // ★ $merge — Persist results into a target collection
  { $merge: {
      into: 'request_summary_mv',
      on: '_id',
      whenMatched: 'replace',      // Update if exists
      whenNotMatched: 'insert',    // Insert if new
  }},
]);
```

**What it does**: Uses `$merge` to persist aggregation results into a new collection (`request_summary_mv`), creating a **materialized view** of per-block request summaries. This pre-computes expensive aggregations for instant dashboard reads.

**Why it matters**: Unlike SQL views (which re-execute queries on access), `$merge` writes physical documents. Unlike `$out` (which replaces the entire collection), `$merge` can **incrementally update** existing documents. This enables a refresh-on-demand pattern for expensive analytics.

---

## 7. Additional DBMS Features

Beyond the 10 core functionalities above, the project implements these supporting DBMS features:

### 7.1 Multi-Document ACID Transactions

**Location**: `backend/routes/requests.js` — `POST /api/requests/:id/accept`

```javascript
const session = await mongoose.startSession();
await session.withTransaction(async () => {
  const request = await Request.findOneAndUpdate(
    { _id: requestId, status: 'OPEN' },
    { $set: { status: 'ASSIGNED', assignment: { ... } } },
    { new: true, session }
  );
  await AuditLog.create([{ ... }], { session });
});
```

When multiple cleaners tap "Accept" simultaneously, the transaction ensures atomicity, isolation, and consistency.

### 7.2 Aggregation Pipelines

**Location**: `backend/routes/analytics.js`

| Pipeline | Stages Used | Purpose |
|---|---|---|
| Overview | `$match`, `$group`, `$count` | Dashboard KPI metrics |
| By Block | `$match`, `$group` | Hostel block distribution |
| Cleaner Leaderboard | `$match`, `$group`, `$lookup`, `$unwind`, `$sort` | Top cleaner rankings |
| Peak Hours | `$match`, `$group` (by `$hour`) | Request volume by hour |
| Status Distribution | `$group` | Request status breakdown |
| Daily Trends | `$match`, `$group` (`$dateToString`), `$sort` | 30-day request trend |
| Task Distribution | `$match`, `$facet`, `$project` | Sweeping vs mopping ratio |
| Rating Distribution | `$group`, `$sort`, `$project` | 1-5 star feedback histogram |
| Cleaner Efficiency | `$match`, `$group`, `$lookup`, `$unwind`, `$project` | Avg response + cleaning time |

### 7.3 Partial Unique Index (Rate Limiting)

**Location**: `backend/models/Request.js`

```javascript
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
```

A student literally **cannot insert** a second request if they already have an active one. The database engine enforces this constraint — no application code needed.

### 7.4 TTL Index (Auto-Expiring Data)

**Location**: `backend/models/AuditLog.js`

```javascript
auditLogSchema.index(
  { expireAt: 1 },
  { expireAfterSeconds: 0, name: 'idx_ttl_auto_expire' }
);
```

MongoDB's background thread automatically removes audit log documents once `expireAt` passes. This implements **automated data lifecycle management** without cron jobs.

### 7.5 Text Index & Full-Text Search

**Location**: `backend/models/Request.js` + `backend/routes/admin.js`

```javascript
// Model
requestSchema.index({ notes: 'text' }, { name: 'idx_notes_text_search' });

// Query
Request.find(
  { $text: { $search: 'urgent cleaning' } },
  { score: { $meta: 'textScore' } }
).sort({ score: { $meta: 'textScore' } });
```

Enables relevance-ranked search across request notes.

### 7.6 Optimistic Concurrency Control

Uses Mongoose's `__v` (versionKey) to prevent lost updates during concurrent state transitions.

### 7.7 Soft Delete

Instead of `deleteOne()`, we set `isDeleted: true` + `deletedAt` + `deletedBy`. Preserves referential integrity and enables admin recovery.

### 7.8 Embedded Documents (Denormalization)

The `assignment` subdocument inside `requests` demonstrates MongoDB's embedded document pattern for 1:1 relationships.

### 7.9 Schema Validation (Mongoose)

Enum constraints, min/max validators, required fields, conditional requirements, and custom validators enforce data integrity before data reaches the database.

### 7.10 Change Data Capture (Audit Logging)

Every state change creates an `AuditLog` entry recording who, what, when, and the before/after values.

---

## 8. Query Optimization

The `/api/dbms/explain` endpoint demonstrates **IXSCAN vs COLLSCAN**:

| Query | Without Index | With Index |
|---|---|---|
| Find OPEN requests | **COLLSCAN** — scans every document | **IXSCAN** via `idx_open_requests_broadcast` |
| Find user by email | **COLLSCAN** — O(n) scan | **IXSCAN** via `email_1` — O(log n) |
| Student request history | **COLLSCAN** + sort in memory | **IXSCAN** via `idx_student_history` |

---

## 9. Data Lifecycle

```
     ┌─────────┐    accept     ┌──────────┐    start    ┌─────────────┐    QR scan    ┌───────────┐
     │  OPEN   │──────────────►│ ASSIGNED │────────────►│ IN_PROGRESS │──────────────►│ COMPLETED │
     └─────────┘               └──────────┘             └─────────────┘               └───────────┘
          │                         │                                                       │
          │ (auto-expire            │ (room locked)                                   soft delete
          │  or student cancel)     ▼                                                       │
          ▼                  ┌───────────────────┐                                          ▼
   ┌──────────────┐          │CANCELLED_ROOM_LOCKED│                                 ┌──────────────┐
   │ BULK_CANCEL  │          └───────────────────┘                                   │ isDeleted=T  │
   └──────────────┘                                                                  └──────────────┘
                                                                                            │
                                                                                     admin restore
                                                                                            │
                                                                                            ▼
                                                                                     ┌──────────────┐
                                                                                     │ isDeleted=F  │
                                                                                     └──────────────┘
```

---

## 10. Project Enhancements

### 10.1 API Rate Limiting

**Location**: `backend/middleware/rateLimiter.js` + `backend/server.js`

```javascript
const rateLimit = require('express-rate-limit');

// Auth endpoints: 10 requests per minute per IP (prevents brute-force)
const authLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 10,
  standardHeaders: true,
});

// General API: 100 requests per minute per IP
const apiLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 100,
  standardHeaders: true,
});
```

Rate limiting protects the API from brute-force login attacks and request flooding. Auth endpoints get a stricter limit (10 req/min) than the general API (100 req/min).

### 10.2 NoSQL Injection Prevention

**Location**: `backend/server.js`

```javascript
const mongoSanitize = require('express-mongo-sanitize');
app.use(mongoSanitize());
```

Strips out any keys starting with `$` or containing `.` from `req.body`, `req.query`, and `req.params`. This prevents attackers from injecting MongoDB operators (e.g., `{ "$gt": "" }`) into query parameters to bypass authentication or extract data.

---

## 11. Environment Variables

### Backend (`backend/.env`)

| Variable | Required | Description |
|---|---|---|
| `MONGODB_URI` | ✅ | MongoDB connection string |
| `MONGODB_DATABASE` | ✅ | Database name (e.g., `cleanit`) |
| `JWT_SECRET` | ✅ | Secret for signing JWT tokens |
| `PORT` | ❌ | Server port (default: 3000) |
| `NODE_ENV` | ❌ | `development` or `production` |

### Frontend (`.env`)

| Variable | Required | Description |
|---|---|---|
| `QR_SIGNING_SECRET` | ✅ | HMAC-SHA256 secret for QR code signing |
| `FIREBASE_PROJECT_ID` | ❌ | Firebase project ID for push notifications |

---

## 12. Seed Data Summary

The `seed.js` script creates a rich dataset for demonstrations:

| Collection | Count | Details |
|---|---|---|
| Users | 16 | 10 students, 5 cleaners, 1 admin |
| Requests | 25 | Across 3 weeks, all 5 statuses, 4 hostel blocks |
| Feedback | 18 | Ratings 1-5 for rating distribution analytics |
| Audit Logs | 48+ | CREATE, UPDATE actions across request lifecycle |

---

## 13. Complete API Endpoint Reference

### Authentication (`/api/auth`)

| Method | Endpoint | Description | Role |
|---|---|---|---|
| POST | `/api/auth/register` | Create new account | Public |
| POST | `/api/auth/login` | Sign in | Public |
| GET | `/api/auth/profile` | Get current user profile | Any |
| PUT | `/api/auth/fcm-token` | Update FCM push token | Any |
| PUT | `/api/auth/toggle-duty` | Toggle cleaner on-duty | Any |
| PUT | `/api/auth/change-password` | **★ Change password** | Any |

### Requests (`/api/requests`)

| Method | Endpoint | Description | Role |
|---|---|---|---|
| POST | `/api/requests` | Create cleaning request | Student |
| GET | `/api/requests/open` | List all OPEN requests | Cleaner, Admin |
| GET | `/api/requests/my` | Student request history | Any |
| GET | `/api/requests/active` | Current active request | Any |
| GET | `/api/requests/cleaner-jobs` | Cleaner's active jobs | Cleaner, Admin |
| POST | `/api/requests/:id/accept` | Accept a request (transaction) | Cleaner, Admin |
| POST | `/api/requests/:id/start` | Start a job | Cleaner, Admin |
| POST | `/api/requests/:id/complete` | Complete a job | Cleaner, Admin |
| POST | `/api/requests/:id/report-locked` | Report room locked | Cleaner, Admin |
| DELETE | `/api/requests/:id` | Soft-delete a request | Any |
| POST | `/api/requests/:id/cancel` | **★ Student cancel own request** | Student, Admin |
| GET | `/api/requests/search` | Full-text search on notes | Any |

### Feedback (`/api/feedback`)

| Method | Endpoint | Description | Role |
|---|---|---|---|
| POST | `/api/feedback` | Submit feedback | Any |
| GET | `/api/feedback/:requestId` | Get feedback for request | Any |
| PUT | `/api/feedback/:id` | Update feedback | Any |
| DELETE | `/api/feedback/:id` | Delete feedback | Any |
| GET | `/api/feedback/details/:requestId` | Feedback with full request details ($lookup) | Any |

### Analytics (`/api/analytics`)

| Method | Endpoint | Description | Role |
|---|---|---|---|
| GET | `/api/analytics/overview` | Dashboard KPIs | Any |
| GET | `/api/analytics/by-block` | Requests by hostel block | Any |
| GET | `/api/analytics/cleaner-leaderboard` | Top cleaners | Any |
| GET | `/api/analytics/peak-hours` | Requests by hour | Any |
| GET | `/api/analytics/status-distribution` | Status pie chart | Any |
| GET | `/api/analytics/trends` | 30-day daily trends | Any |
| GET | `/api/analytics/task-distribution` | Task type breakdown ($facet) | Any |
| GET | `/api/analytics/rating-distribution` | Feedback histogram | Any |
| GET | `/api/analytics/cleaner-efficiency` | Cleaner time metrics | Any |
| GET | `/api/analytics/cleaner-summary/:id` | **★ Single cleaner profile** | Any |

### Admin (`/api/admin`)

| Method | Endpoint | Description | Role |
|---|---|---|---|
| GET | `/api/admin/users` | List all users | Any |
| GET | `/api/admin/audit-logs` | Fetch audit trail | Any |
| GET | `/api/admin/search` | Full-text search (notes) | Any |
| GET | `/api/admin/export/:collection` | Export collection as JSON | Any |
| GET | `/api/admin/db-stats` | Database statistics | Any |
| PUT | `/api/admin/users/:id/role` | Update user role (transaction) | Any |
| GET | `/api/admin/deleted-requests` | List soft-deleted requests | Any |
| PUT | `/api/admin/bulk-cancel` | Bulk cancel stale requests | Any |
| GET | `/api/admin/user-search` | Text search on users | Any |
| PUT | `/api/admin/restore-request/:id` | **★ Restore soft-deleted request** | Admin |
| GET | `/api/admin/dashboard-counts` | **★ Admin dashboard counts** | Admin |

### DBMS Showcase (`/api/dbms`)

| Method | Endpoint | Description | DBMS Feature |
|---|---|---|---|
| GET | `/api/dbms/explain` | Query execution plans | IXSCAN vs COLLSCAN |
| GET | `/api/dbms/indexes` | Complete index catalog | Index management |
| GET | `/api/dbms/collection-stats` | Collection statistics | DB introspection |
| POST | `/api/dbms/transaction-demo` | Transaction with rollback | ACID transactions |
| GET | `/api/dbms/aggregation-showcase` | Aggregation examples | Aggregation framework |
| GET | `/api/dbms/lookup-demo` | **★ Multi-collection $lookup** | `$lookup` joins |
| GET | `/api/dbms/random-sample` | **★ Random document sampling** | `$sample` |
| GET | `/api/dbms/bucket-analysis` | **★ Histogram analysis** | `$bucket` / `$bucketAuto` |
| GET | `/api/dbms/graph-lookup` | **★ Recursive audit trail** | `$graphLookup` |
| POST | `/api/dbms/materialized-view` | **★ Materialized view** | `$merge` |

---

## 14. Running the DBMS Demo

After setting up and seeding, use these endpoints to showcase DBMS features:

```bash
# 1. Login as admin
TOKEN=$(curl -s -X POST http://localhost:3000/api/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"email":"admin@cleanit.com","password":"admin123"}' | jq -r '.token')

# ── User-Defined Functionalities ──

# 2. Change password
curl -X PUT -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"currentPassword":"admin123","newPassword":"newpass123"}' \
  http://localhost:3000/api/auth/change-password

# 3. Admin dashboard counts (cross-collection aggregation)
curl -H "Authorization: Bearer $TOKEN" http://localhost:3000/api/admin/dashboard-counts

# 4. Cleaner performance summary (replace CLEANER_ID with actual ID)
curl -H "Authorization: Bearer $TOKEN" http://localhost:3000/api/analytics/cleaner-summary/CLEANER_ID

# 5. View soft-deleted requests (for restore demo)
curl -H "Authorization: Bearer $TOKEN" http://localhost:3000/api/admin/deleted-requests

# 6. Restore a soft-deleted request (replace REQUEST_ID)
curl -X PUT -H "Authorization: Bearer $TOKEN" \
  http://localhost:3000/api/admin/restore-request/REQUEST_ID

# ── NoSQL Functionalities ──

# 7. $lookup multi-collection join
curl -H "Authorization: Bearer $TOKEN" http://localhost:3000/api/dbms/lookup-demo

# 8. $sample random sampling
curl -H "Authorization: Bearer $TOKEN" "http://localhost:3000/api/dbms/random-sample?size=5"

# 9. $bucket histogram analysis
curl -H "Authorization: Bearer $TOKEN" http://localhost:3000/api/dbms/bucket-analysis

# 10. $graphLookup recursive audit trail
curl -H "Authorization: Bearer $TOKEN" http://localhost:3000/api/dbms/graph-lookup

# 11. $merge materialized view
curl -X POST -H "Authorization: Bearer $TOKEN" http://localhost:3000/api/dbms/materialized-view

# ── Existing Features ──

# 12. View index catalog
curl -H "Authorization: Bearer $TOKEN" http://localhost:3000/api/dbms/indexes

# 13. Run query explain plans
curl -H "Authorization: Bearer $TOKEN" http://localhost:3000/api/dbms/explain

# 14. Transaction demo (with rollback)
curl -X POST -H "Authorization: Bearer $TOKEN" http://localhost:3000/api/dbms/transaction-demo

# 15. Aggregation showcase
curl -H "Authorization: Bearer $TOKEN" http://localhost:3000/api/dbms/aggregation-showcase

# 16. Full-text search
curl -H "Authorization: Bearer $TOKEN" "http://localhost:3000/api/admin/search?q=urgent"

# 17. View audit logs (TTL-indexed collection)
curl -H "Authorization: Bearer $TOKEN" http://localhost:3000/api/admin/audit-logs

# 18. Analytics overview
curl -H "Authorization: Bearer $TOKEN" http://localhost:3000/api/analytics/overview
```
