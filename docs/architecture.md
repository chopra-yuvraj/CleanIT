# CleanIT — System Architecture

## Overview

CleanIT uses a **serverless-first** architecture powered by **Supabase** (PostgreSQL + Edge Functions + Realtime) and **Firebase Cloud Messaging (FCM)** for push notifications. This eliminates server management costs and scales effortlessly to 1000+ concurrent users on free tiers.

---

## Architecture Diagram

```mermaid
graph TB
    subgraph "Mobile Clients (Flutter)"
        S["📱 Student App"]
        C["📱 Cleaner App(s)"]
    end

    subgraph "Supabase (Free Tier)"
        EF["⚡ Edge Functions<br/>(Deno Runtime)"]
        DB["🐘 PostgreSQL<br/>+ PgBouncer"]
        RT["📡 Realtime Engine<br/>(WebSocket)"]
        ST["📦 Storage<br/>(Proof Photos)"]
        AU["🔐 Auth<br/>(JWT)"]
    end

    subgraph "Firebase (Free Tier)"
        FCM["🔔 Cloud Messaging<br/>(Push Notifications)"]
    end

    S -->|"REST + JWT"| EF
    C -->|"REST + JWT"| EF
    EF -->|"SQL + RPC"| DB
    EF -->|"Upload"| ST
    EF -->|"HTTP API"| FCM
    DB -->|"WAL stream"| RT
    RT -->|"WebSocket"| S
    RT -->|"WebSocket"| C
    FCM -->|"Push"| S
    FCM -->|"Push"| C

    style S fill:#89B4FA,stroke:#1E1E2E,color:#1E1E2E
    style C fill:#A6E3A1,stroke:#1E1E2E,color:#1E1E2E
    style EF fill:#CBA6F7,stroke:#1E1E2E,color:#1E1E2E
    style DB fill:#F9E2AF,stroke:#1E1E2E,color:#1E1E2E
    style RT fill:#89DCEB,stroke:#1E1E2E,color:#1E1E2E
    style ST fill:#FAB387,stroke:#1E1E2E,color:#1E1E2E
    style AU fill:#F5C2E7,stroke:#1E1E2E,color:#1E1E2E
    style FCM fill:#FF6B6B,stroke:#1E1E2E,color:#FFF
```

---

## End-to-End Sequence: Request → Broadcast → Race → Completion

```mermaid
sequenceDiagram
    autonumber
    participant S as 📱 Student
    participant EF as ⚡ Edge Functions
    participant DB as 🐘 PostgreSQL
    participant RT as 📡 Realtime
    participant FCM as 🔔 FCM
    participant C1 as 📱 Cleaner A
    participant C2 as 📱 Cleaner B
    participant C3 as 📱 Cleaner C

    Note over S,C3: ─── Flow 1: Request Creation ───

    S->>EF: POST /create-request<br/>{sweeping: true, mopping: true, urgent: false}
    EF->>DB: INSERT INTO requests (status='OPEN')
    DB-->>EF: ✅ request_id = abc-123
    
    Note over EF,FCM: Broadcast to ALL on-duty cleaners
    EF->>DB: SELECT fcm_token FROM users<br/>WHERE role='cleaner' AND is_on_duty=true
    DB-->>EF: [token_A, token_B, token_C]
    EF->>FCM: POST /fcm/send {registration_ids: [...]}
    
    par Push Notifications (simultaneous)
        FCM-->>C1: 🔔 "New Request: Room A-101"
        FCM-->>C2: 🔔 "New Request: Room A-101"
        FCM-->>C3: 🔔 "New Request: Room A-101"
    end
    
    EF-->>S: 201 {request_id: abc-123}

    Note over S,C3: ─── Flow 2: Fastest Finger First Race ───

    par Cleaners race to accept (within milliseconds)
        C1->>EF: POST /accept-request {request_id: abc-123}
        C2->>EF: POST /accept-request {request_id: abc-123}
        C3->>EF: POST /accept-request {request_id: abc-123}
    end

    EF->>DB: RPC accept_request(abc-123, cleaner_A)<br/>SELECT ... FOR UPDATE SKIP LOCKED
    Note over DB: 🔒 Row locked by Cleaner A's transaction
    DB-->>EF: ✅ {success: true, assignment_id: xyz-789}
    
    EF->>DB: RPC accept_request(abc-123, cleaner_B)<br/>SELECT ... FOR UPDATE SKIP LOCKED
    Note over DB: Row already locked → SKIP LOCKED returns 0 rows
    DB-->>EF: ❌ {success: false, code: 'ALREADY_ASSIGNED'}
    
    EF->>DB: RPC accept_request(abc-123, cleaner_C)<br/>Row no longer OPEN
    DB-->>EF: ❌ {success: false, code: 'ALREADY_ASSIGNED'}

    par Responses
        EF-->>C1: 200 ✅ "Request accepted!"
        EF-->>C2: 409 ❌ "Already accepted by someone else"
        EF-->>C3: 409 ❌ "Already accepted by someone else"
    end

    Note over DB,RT: Status change triggers Realtime broadcast
    DB->>RT: WAL: requests.status changed to 'ASSIGNED'
    RT-->>S: WebSocket: {status: 'ASSIGNED'}
    RT-->>C1: WebSocket: {status: 'ASSIGNED'}

    Note over S,C3: ─── Flow 3: Job Execution & QR Verification ───

    C1->>EF: RPC start_job(abc-123)
    EF->>DB: UPDATE status='IN_PROGRESS'
    DB->>RT: WAL broadcast
    RT-->>S: WebSocket: {status: 'IN_PROGRESS'}

    Note over C1: Cleaner performs sweeping/mopping

    C1->>EF: POST /verify-qr {qr_payload: ...}
    EF->>EF: Verify HMAC signature + 3-min expiry
    EF->>DB: RPC complete_job(abc-123)
    DB->>RT: WAL broadcast
    RT-->>S: WebSocket: {status: 'COMPLETED'}
    EF-->>C1: 200 "Job completed!"

    Note over S: Student prompted for 1-5 star rating
```

---

## Sequence: Room Locked Exception Path

```mermaid
sequenceDiagram
    participant C as 📱 Cleaner
    participant EF as ⚡ Edge Functions
    participant ST as 📦 Storage
    participant DB as 🐘 PostgreSQL
    participant FCM as 🔔 FCM
    participant S as 📱 Student

    Note over C: Arrives at room — door is locked

    C->>C: Taps "Room Locked"<br/>Camera opens → snaps proof photo
    C->>EF: POST /report-locked<br/>(multipart: request_id + photo)
    
    EF->>ST: Upload photo to proof-photos bucket
    ST-->>EF: ✅ public URL

    EF->>DB: RPC report_room_locked()<br/>Verify cleaner is assigned
    DB-->>EF: ✅ {success: true, student_id: ...}

    EF->>DB: UPDATE requests SET status='CANCELLED_ROOM_LOCKED'
    EF->>DB: UPDATE assignments SET proof_image_url, failure_reason

    EF->>DB: SELECT fcm_token FROM users WHERE id=student_id
    DB-->>EF: student's FCM token

    EF->>FCM: Push to student
    FCM-->>S: 🔔 "Your cleaner arrived, but your room was locked."
    
    Note over S: Dashboard shows red alert banner:<br/>"Last request cancelled: Room locked"

    EF-->>C: 200 "Report submitted. Student notified."
```

---

## How It All Works Together

### 1. FCM Broadcast to 100+ Cleaners

When a student creates a request, the `create-request` Edge Function queries all on-duty cleaners' FCM tokens and sends a **multicast push notification** in a single HTTP call (batched in groups of 500). FCM handles the fan-out internally — it's designed for millions of messages and is **100% free**.

**Urgent requests** use a distinct Android notification channel (`urgent_requests`) mapped to a siren sound file, so the cleaner's phone plays an alarm instead of a default ding.

### 2. Race-Condition Resolution at the Database Level

This is the most critical piece. When 100 cleaners tap "Accept" simultaneously:

| Step | What Happens |
|------|-------------|
| 1 | Each cleaner's request hits a separate Edge Function instance |
| 2 | Each instance calls `accept_request()` — a PostgreSQL function |
| 3 | PostgreSQL's `SELECT ... FOR UPDATE SKIP LOCKED` grabs an **exclusive row lock** |
| 4 | The **first** transaction to acquire the lock wins and proceeds |
| 5 | All other transactions see zero rows (thanks to `SKIP LOCKED`) and return immediately with "already taken" |
| 6 | The winner's transaction atomically updates the status and creates the assignment |

This is **non-blocking** — losers don't wait for the winner's transaction to commit. They get an instant rejection. No deadlocks, no retries, no application-level distributed locks needed.

### 3. Real-Time "Loser" Notification via Supabase Realtime

Supabase Realtime listens to PostgreSQL's **Write-Ahead Log (WAL)** stream. When `requests.status` changes from `OPEN` to `ASSIGNED`:

1. The WAL event is captured by Supabase's Realtime engine
2. It broadcasts to all clients subscribed to that row's channel
3. Every cleaner's Flutter app receives the WebSocket message in ~50ms
4. The app UI auto-updates: the pop-up dismisses with "Already accepted by someone else"

This is **dual-channel redundancy**: the HTTP response from the Edge Function tells the individual loser instantly, while the WebSocket broadcast updates everyone's UI simultaneously.

### 4. "Room Locked" Push Back to Student

The flow is: **Cleaner → Edge Function → Storage (photo) → Database (status update) → FCM → Student**.

The Edge Function orchestrates all of this in a single request:
1. Validates the cleaner is the assigned cleaner (prevents abuse)
2. Uploads the mandatory proof photo (prevents false reports)
3. Updates both `requests` and `assignments` tables atomically
4. Fetches the student's FCM token and pushes a notification

The student's app also receives the status change via Supabase Realtime WebSocket, so even if FCM push is delayed, the UI updates instantly.

---

## Free Tier Capacity

| Service | Free Tier Limit | CleanIT Usage |
|---------|----------------|---------------|
| Supabase Database | 500 MB, unlimited API calls | ~50 KB/1000 requests |
| Supabase Edge Functions | 500K invocations/month | ~10K/month at 1000 students |
| Supabase Realtime | 200 concurrent connections | ✅ Handles 200 concurrent |
| Supabase Storage | 1 GB | Proof photos (~100 KB each) |
| Supabase Auth | 50,000 MAU | ✅ |
| Firebase FCM | Unlimited | ✅ 100% free forever |

> **Scaling note**: If you exceed 200 concurrent Realtime connections, upgrade to Supabase Pro ($25/month) for 10,000 concurrent connections. All other tiers remain free.
