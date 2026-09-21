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
│  • AnalyticsSvc │         │                       │          │  • feedbacks     │
│  • QRService    │         │  Routes:              │          │  • auditlogs     │
│  • ApiClient    │         │  • /api/auth          │          │                  │
│                 │         │  • /api/requests      │          │  Features:       │
│                 │         │  • /api/feedback      │          │  • Transactions  │
│                 │         │  • /api/analytics     │          │  • TTL Indexes   │
│                 │         │  • /api/admin         │          │  • Text Search   │
│                 │         │  • /api/dbms          │          │  • Aggregation   │
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

## 5. DBMS Features Implemented

### 5.1 Multi-Document ACID Transactions

**Location**: `backend/routes/requests.js` — `POST /api/requests/:id/accept`

```javascript
const session = await mongoose.startSession();
await session.withTransaction(async () => {
  // 1. Find and lock the OPEN request
  const request = await Request.findOneAndUpdate(
    { _id: requestId, status: 'OPEN' },
    { $set: { status: 'ASSIGNED', assignment: { ... } } },
    { new: true, session }
  );
  // 2. Create audit log (same transaction)
  await AuditLog.create([{ ... }], { session });
  // If either fails → ROLLBACK (both are undone)
});
```

**Why**: When multiple cleaners tap "Accept" simultaneously, the transaction ensures:
- **Atomicity**: Either both the status update AND audit log succeed, or neither does
- **Isolation**: Concurrent transactions see consistent state
- **Consistency**: Only one cleaner can win the race

### 5.2 Aggregation Pipelines

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

### 5.3 Partial Unique Index (Rate Limiting)

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

### 5.4 TTL Index (Auto-Expiring Data)

**Location**: `backend/models/AuditLog.js`

```javascript
auditLogSchema.index(
  { expireAt: 1 },
  { expireAfterSeconds: 0, name: 'idx_ttl_auto_expire' }
);
```

MongoDB's background thread automatically removes audit log documents once `expireAt` passes. This implements **automated data lifecycle management** without any cron jobs or manual cleanup scripts.

### 5.5 Text Index & Full-Text Search

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

### 5.6 Optimistic Concurrency Control

**Location**: `backend/routes/requests.js` — state transitions

```javascript
const result = await Request.findOneAndUpdate(
  { _id: requestId, status: 'ASSIGNED', '__v': expectedVersion },
  { $set: { status: 'IN_PROGRESS' }, $inc: { __v: 1 } },
  { new: true }
);
```

Mongoose's `__v` (versionKey) prevents lost updates. If two concurrent requests try to transition the same document, only one succeeds.

### 5.7 Soft Delete

**Location**: `backend/routes/requests.js` — `DELETE /api/requests/:id`

Instead of `deleteOne()`, we set `isDeleted: true` + `deletedAt` + `deletedBy`. This:
- Preserves referential integrity with feedback records
- Enables admin recovery of accidentally deleted data
- Maintains audit trail completeness
- All regular queries filter with `isDeleted: { $ne: true }`

### 5.8 Embedded Documents (Denormalization)

The `assignment` subdocument inside `requests` demonstrates MongoDB's embedded document pattern:
- **1:1 relationship** → embed instead of separate collection
- **Always queried together** → single read instead of `$lookup`
- **Atomic updates** → update request + assignment in one operation

### 5.9 Schema Validation (Mongoose)

```javascript
role: {
  type: String,
  required: true,
  enum: ['student', 'cleaner', 'admin'],
},
rating: {
  type: Number,
  required: true,
  min: 1, max: 5,
},
block: {
  type: String,
  required: function() { return this.role === 'student'; },
},
```

Validation happens **before** data reaches the database, ensuring data integrity.

### 5.10 Change Data Capture (Audit Logging)

Every state change across the application creates an `AuditLog` entry recording:
- Which collection and document were modified
- What action was performed (CREATE, UPDATE, DELETE)
- Who performed it
- What the before/after values were
- When it happened

This serves as a CDC mechanism for compliance, debugging, and analytics.

---

## 6. Query Optimization

The `/api/dbms/explain` endpoint demonstrates **IXSCAN vs COLLSCAN**:

| Query | Without Index | With Index |
|---|---|---|
| Find OPEN requests | **COLLSCAN** — scans every document | **IXSCAN** via `idx_open_requests_broadcast` |
| Find user by email | **COLLSCAN** — O(n) scan | **IXSCAN** via `email_1` — O(log n) |
| Student request history | **COLLSCAN** + sort in memory | **IXSCAN** via `idx_student_history` |

---

## 7. Data Lifecycle

```
     ┌─────────┐    accept     ┌──────────┐    start    ┌─────────────┐    QR scan    ┌───────────┐
     │  OPEN   │──────────────►│ ASSIGNED │────────────►│ IN_PROGRESS │──────────────►│ COMPLETED │
     └─────────┘               └──────────┘             └─────────────┘               └───────────┘
          │                         │                                                       │
          │ (auto-expire)           │ (room locked)                                   soft delete
          ▼                         ▼                                                       │
   ┌──────────────┐        ┌───────────────────┐                                           ▼
   │ BULK_CANCEL  │        │CANCELLED_ROOM_LOCKED│                                  ┌──────────────┐
   └──────────────┘        └───────────────────┘                                    │ isDeleted=T  │
                                                                                     └──────────────┘
```

---

## 8. Environment Variables

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

## 9. Seed Data Summary

The `seed.js` script creates a rich dataset for demonstrations:

| Collection | Count | Details |
|---|---|---|
| Users | 16 | 10 students, 5 cleaners, 1 admin |
| Requests | 25 | Across 3 weeks, all 5 statuses, 4 hostel blocks |
| Feedback | 18 | Ratings 1-5 for rating distribution analytics |
| Audit Logs | 48+ | CREATE, UPDATE actions across request lifecycle |

---

## 10. Running the DBMS Demo

After setting up and seeding, use these endpoints to showcase DBMS features:

```bash
# 1. Login as admin
TOKEN=$(curl -s -X POST http://localhost:3000/api/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"email":"admin@cleanit.com","password":"admin123"}' | jq -r '.token')

# 2. View index catalog
curl -H "Authorization: Bearer $TOKEN" http://localhost:3000/api/dbms/indexes

# 3. Run query explain plans
curl -H "Authorization: Bearer $TOKEN" http://localhost:3000/api/dbms/explain

# 4. View collection stats
curl -H "Authorization: Bearer $TOKEN" http://localhost:3000/api/dbms/collection-stats

# 5. Run transaction demo (with rollback)
curl -X POST -H "Authorization: Bearer $TOKEN" http://localhost:3000/api/dbms/transaction-demo

# 6. Run aggregation showcase
curl -H "Authorization: Bearer $TOKEN" http://localhost:3000/api/dbms/aggregation-showcase

# 7. Analytics overview (aggregation pipeline)
curl -H "Authorization: Bearer $TOKEN" http://localhost:3000/api/analytics/overview

# 8. Full-text search
curl -H "Authorization: Bearer $TOKEN" "http://localhost:3000/api/admin/search?q=urgent"

# 9. View audit logs (TTL-indexed collection)
curl -H "Authorization: Bearer $TOKEN" http://localhost:3000/api/admin/audit-logs
```
