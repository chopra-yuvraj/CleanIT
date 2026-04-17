# CleanIT — Entity-Relationship Diagram

## Overview

The CleanIT data model consists of four core entities that support the full lifecycle
of a cleaning request: creation, assignment, execution, and feedback.

## ER Diagram

```mermaid
erDiagram
    USERS {
        uuid id PK "Primary key, auto-generated"
        text email UK "Unique, used for auth"
        text name "Display name"
        user_role role "ENUM: student | cleaner | admin"
        text block "Hostel block (e.g. A, B, C)"
        text room_number "Room number (e.g. 101)"
        text fcm_token "Firebase Cloud Messaging token"
        boolean is_on_duty "Cleaner availability flag"
        timestamptz created_at "Auto-set on insert"
        timestamptz updated_at "Auto-updated via trigger"
    }

    REQUESTS {
        uuid id PK "Primary key, auto-generated"
        uuid student_id FK "References USERS.id"
        request_status status "ENUM: OPEN | ASSIGNED | IN_PROGRESS | COMPLETED | CANCELLED_ROOM_LOCKED"
        boolean is_sweeping "Task: floor sweeping"
        boolean is_mopping "Task: wet mopping"
        boolean is_urgent "Urgent flag (spills, accidents)"
        text notes "Optional instructions for cleaner"
        timestamptz created_at "Auto-set on insert"
        timestamptz updated_at "Auto-updated via trigger"
    }

    ASSIGNMENTS {
        uuid id PK "Primary key, auto-generated"
        uuid request_id FK UK "References REQUESTS.id (unique — one assignment per request)"
        uuid cleaner_id FK "References USERS.id"
        timestamptz assigned_at "When cleaner accepted"
        timestamptz started_at "When cleaner tapped Start Job"
        timestamptz completed_at "When QR verification succeeded"
        text failure_reason "Reason if cancelled (e.g. room_locked)"
        text proof_image_url "URL to photo proof (locked door)"
    }

    FEEDBACK {
        uuid id PK "Primary key, auto-generated"
        uuid request_id FK UK "References REQUESTS.id (unique — one feedback per request)"
        uuid student_id FK "References USERS.id"
        integer rating "1-5 star rating"
        text comment "Optional written feedback"
        timestamptz created_at "Auto-set on insert"
    }

    USERS ||--o{ REQUESTS : "creates"
    USERS ||--o{ ASSIGNMENTS : "is assigned to"
    REQUESTS ||--o| ASSIGNMENTS : "has at most one"
    REQUESTS ||--o| FEEDBACK : "receives at most one"
    USERS ||--o{ FEEDBACK : "gives"
```

## Key Constraints

| Constraint | Implementation | Purpose |
|---|---|---|
| One active request per student | `UNIQUE INDEX` on `requests(student_id)` where status IN `('OPEN','ASSIGNED','IN_PROGRESS')` | Prevents spam / rate-limiting |
| One assignment per request | `UNIQUE(request_id)` on `assignments` | Ensures only one cleaner is assigned |
| One feedback per request | `UNIQUE(request_id)` on `feedback` | Prevents duplicate reviews |
| Race-condition safety | `SELECT ... FOR UPDATE SKIP LOCKED` in `accept_request()` RPC | Only one cleaner wins the race |
| Rating bounds | `CHECK (rating >= 1 AND rating <= 5)` on `feedback` | Data integrity |

## Enum Types

```sql
CREATE TYPE user_role AS ENUM ('student', 'cleaner', 'admin');
CREATE TYPE request_status AS ENUM (
    'OPEN',
    'ASSIGNED',
    'IN_PROGRESS',
    'COMPLETED',
    'CANCELLED_ROOM_LOCKED'
);
```
