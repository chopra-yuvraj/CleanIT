# CleanIT — MongoDB Schema & DBMS Architecture

This document outlines the database design, schema decisions, and advanced DBMS features implemented in the CleanIT Node.js/MongoDB backend. It serves as technical documentation for the DBMS project submission.

> For full database documentation including index catalog and demo instructions, see [`DATABASE_DOCUMENTATION.md`](DATABASE_DOCUMENTATION.md).

## 1. Schema Design (Denormalization vs. Normalization)

Moving from a relational mindset to MongoDB required shifting from a purely normalized model to an aggregate-oriented document model. Each design decision is explained below.

### `users` Collection
Stores both students and cleaners, distinguished by the `role` enum.
- **Why one collection?** Allows a single unified authentication flow and generic role-based access control middleware. All users share the same JWT generation and login logic.
- **Conditional validation**: `block` and `roomNumber` are required only for students (not cleaners/admins). This is enforced via Mongoose custom validators.

### `requests` Collection
The core transactional collection of the system.
- **Embedded Document (`assignment`)**: In SQL, cleaner assignments would be a separate table with a foreign key. In MongoDB, the assignment is embedded directly within the request document.
  - **Why?** Assignments have a 1:1 strict relationship with requests and are always queried together. Embedding prevents costly `$lookup` joins on read-heavy paths (cleaner broadcast, student active request).
- **Denormalized Data**: `studentName`, `studentBlock`, and `studentRoom` are copied from the user document at creation time.
  - **Why?** Once a request is created, the room number and block rarely change for that specific request event. This allows the cleaner broadcast view (fetching all `OPEN` requests) to read from a single collection without any joins, optimizing read performance.
- **Soft Delete Fields**: `isDeleted`, `deletedAt`, `deletedBy` enable logical deletion.
  - **Why?** Physical deletion would break referential integrity with feedback records and lose audit trail data. Soft delete preserves data while hiding it from normal queries.

### `feedbacks` Collection
Stores post-completion ratings and comments.
- **Normalized Reference**: Links to `requestId` and `studentId` via `ObjectId` references.
  - **Why?** Feedback is created *after* the request lifecycle is complete and isn't needed during the core operational flow (cleaning the room). Keeping it separate prevents the `requests` collection documents from growing unbounded and keeps the working set small.

### `auditlogs` Collection
Records every state change across all collections (Change Data Capture).
- **Why a separate collection?** Audit logs grow continuously and have a different lifecycle (90-day TTL auto-purge) than operational data. Separating them prevents bloating the working set of the `requests` collection.

---

## 2. Advanced DBMS Features Implemented

### A. Multi-Document ACID Transactions
MongoDB supports full ACID transactions across multiple documents.
- **Implementation**: The `POST /api/requests/:id/accept` endpoint uses `mongoose.startSession()` and `session.withTransaction()`.
- **Purpose**: Atomically transitions the request status from `OPEN` to `ASSIGNED` *and* creates an audit log entry. If another cleaner accepts the request at the exact same millisecond, the transaction ensures only one succeeds and the other sees the updated state.
- **Demo**: The `POST /api/dbms/transaction-demo` endpoint demonstrates a full transaction lifecycle with intentional rollback.

### B. Optimistic Concurrency Control
- **Implementation**: The `start_job` and `complete_job` endpoints use `findOneAndUpdate` with strict state conditions (e.g., `status: 'ASSIGNED'`).
- **Purpose**: Prevents lost updates without the overhead of explicit pessimistic locking. Mongoose's internal `__v` (versionKey) also protects against parallel modifications.

### C. Advanced Indexing Strategies
15 indexes across 4 collections demonstrate 7 different index types:

1. **Compound Indexes**: `users: { role: 1, isOnDuty: 1 }`
   - *Use Case*: Rapidly fetching available cleaners without scanning all users.
2. **Partial Unique Indexes**: `requests: { studentId: 1 }` where `status IN ['OPEN', 'ASSIGNED', 'IN_PROGRESS']`
   - *Use Case*: Enforces at the database level that a student can only have **one active request at a time**.
3. **Text Indexes**: `requests: { notes: "text" }`, `users: { name: "text", email: "text" }`
   - *Use Case*: Powers full-text search APIs for admins to search request notes and users by relevance score.
4. **Sparse Indexes**: `users: { fcmToken: 1 }`
   - *Use Case*: Only indexes users who actually have push notification tokens, saving RAM.
5. **TTL (Time-To-Live) Indexes**: `auditlogs: { expireAt: 1 }`
   - *Use Case*: Automatically deletes old audit logs after 90 days, demonstrating automated data lifecycle management.
6. **Unique Indexes**: `feedbacks: { requestId: 1 }`, `users: { email: 1 }`
   - *Use Case*: Prevents duplicate feedback and duplicate registrations.
7. **Descending Indexes**: `auditlogs: { timestamp: -1 }`
   - *Use Case*: Optimizes reverse-chronological queries (admin dashboard).

### D. Aggregation Pipeline
MongoDB's aggregation framework is used heavily in the Analytics endpoints.
- **Pipeline Stages Used**:
  - `$match`: Filtering (SQL `WHERE`)
  - `$group`: Grouping and aggregating (SQL `GROUP BY`, `SUM`, `AVG`)
  - `$lookup`: Left outer joins across collections (SQL `LEFT JOIN`)
  - `$unwind`: Flattening arrays from `$lookup`
  - `$project`: Reshaping documents (SQL `SELECT`)
  - `$facet`: Running multiple sub-pipelines in parallel
  - `$dateToString`: Formatting timestamps for daily trend grouping
  - `$dayOfWeek`: Extracting day-of-week for weekly patterns
  - `$cond`: Conditional expressions

### E. Soft Delete (Logical Deletion)
- **Implementation**: `isDeleted`, `deletedAt`, `deletedBy` fields on the `requests` collection.
- **Purpose**: Preserves referential integrity, enables admin recovery, and maintains audit trail completeness.

### F. Bulk Write Operations
- **Implementation**: `PUT /api/admin/bulk-cancel` uses `updateMany` to cancel stale requests.
- **Purpose**: Demonstrates MongoDB's ability to atomically update multiple documents matching a filter.

### G. Query Explain Plans
- **Implementation**: `GET /api/dbms/explain` runs `explain('executionStats')` on common queries.
- **Purpose**: Shows the difference between IXSCAN (index scan) and COLLSCAN (collection scan).

---

## 3. Database Validation

Unlike schemaless MongoDB of the past, this implementation uses strict schema validation via Mongoose:
- **Enums**: Roles and statuses are strictly validated against allowed values.
- **Required Fields**: Mandatory fields throw validation errors before hitting the database engine.
- **Range Validators**: `rating` is constrained to 1-5 with `min`/`max`.
- **Custom Validators**: `roomNumber` and `block` are conditionally required based on the user's `role` (required for students, omitted for cleaners).
- **Pre-save Hooks**: Passwords are bcrypt-hashed before being stored, ensuring no plaintext passwords ever reach the database.
