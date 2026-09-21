<p align="center">
  <img src="https://img.icons8.com/fluency/96/broom.png" alt="CleanIT" width="80"/>
</p>

<h1 align="center">CleanIT</h1>

<p align="center">
  <strong>Real-time hostel room cleaning management system — A DBMS Project</strong><br/>
  Request cleaning → Cleaners race to accept → QR-verified completion.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.19+-02569B?logo=flutter&logoColor=white" alt="Flutter"/>
  <img src="https://img.shields.io/badge/Node.js-Express-339933?logo=node.js&logoColor=white" alt="Node.js"/>
  <img src="https://img.shields.io/badge/MongoDB-Database-47A248?logo=mongodb&logoColor=white" alt="MongoDB"/>
  <img src="https://img.shields.io/badge/Firebase-FCM-FFCA28?logo=firebase&logoColor=black" alt="Firebase"/>
  <img src="https://img.shields.io/badge/License-Proprietary-red" alt="License"/>
</p>

---

## What is CleanIT?

CleanIT is a mobile + web application that connects hostel students with cleaning staff in real time. Students submit a cleaning request, all on-duty cleaners receive it instantly, and the fastest cleaner to tap "Accept" wins the job — guaranteed by a **MongoDB multi-document ACID transaction**. Jobs are verified via time-limited, HMAC-signed QR codes to prevent fraud.

### Key Features

| Feature | DBMS Concept |
|---|---|
| **Fastest Finger First** | Multi-document ACID transaction — exactly one cleaner wins |
| **QR Verification** | HMAC-signed, 3-minute expiry QR codes prevent screenshot abuse |
| **Room Locked Reporting** | Mandatory proof photo upload for locked-door cancellations |
| **Rate Limiting** | Partial unique index enforces one active request per student |
| **Full-text Search** | Text index on request notes for keyword search |
| **Auto-expiring Audit Logs** | TTL index automatically purges 90-day-old logs |
| **Admin Analytics** | Aggregation pipelines with $group, $lookup, $facet, $unwind |
| **Soft Delete** | Logical deletion preserving referential integrity |
| **Optimistic Concurrency** | Version key (`__v`) prevents lost updates |

---

## Tech Stack

| Layer | Technology |
|---|---|
| **Frontend** | Flutter (Android, iOS, Web) |
| **Backend API** | Node.js + Express.js |
| **Database** | MongoDB (with Mongoose ODM) |
| **Authentication** | JWT (JSON Web Tokens) |
| **Notifications** | Firebase Cloud Messaging |

---

## Architecture

```
┌─────────────────────┐      HTTP/REST      ┌──────────────────────┐      Mongoose      ┌───────────────┐
│   Flutter App        │ ──────────────────► │   Express.js API     │ ──────────────────► │   MongoDB     │
│   (Android/iOS/Web)  │ ◄────────────────── │   (Node.js)          │ ◄────────────────── │   Atlas       │
│                      │      JSON           │                      │      Documents      │               │
│  • Student UI        │                     │  • Auth (JWT)        │                     │  • users      │
│  • Cleaner UI        │                     │  • Request CRUD      │                     │  • requests   │
│  • Admin Dashboard   │                     │  • Analytics Agg.    │                     │  • feedbacks  │
│  • QR Scanner        │                     │  • Audit Logging     │                     │  • auditlogs  │
└─────────────────────┘                      └──────────────────────┘                     └───────────────┘
```

---

## Project Structure

```
CleanIT/
├── lib/                          # Flutter frontend
│   ├── config/                   # App configuration & theme
│   ├── models/                   # Dart data models
│   ├── screens/                  # UI screens (Auth, Student, Cleaner, Admin)
│   └── services/                 # API client, auth, request, QR, sound services
├── backend/                      # Node.js/Express backend
│   ├── config/                   # MongoDB connection config
│   ├── models/                   # Mongoose schemas (User, Request, Feedback, AuditLog)
│   ├── routes/                   # REST API routes
│   │   ├── auth.js               # Registration, login, JWT
│   │   ├── requests.js           # CRUD + state transitions + soft delete
│   │   ├── feedback.js           # Feedback CRUD + $lookup joins
│   │   ├── analytics.js          # Aggregation pipeline endpoints
│   │   ├── admin.js              # Admin operations, export, search
│   │   └── dbms.js               # DBMS feature showcase (explain, indexes, transactions)
│   ├── middleware/               # JWT auth, role guard middleware
│   ├── utils/                    # Audit logger utility
│   └── scripts/                  # Seed data, index creation
├── DATABASE_DOCUMENTATION.md     # Complete database documentation
├── MONGODB_SCHEMA_DESIGN.md      # Schema design decisions
└── README.md                     # This file
```

---

## Getting Started

### Prerequisites

- **Flutter SDK** ≥ 3.19
- **Node.js** ≥ 18
- **MongoDB Atlas** account (free M0 cluster) or local MongoDB
- **Firebase** project (free) — for push notifications

### 1. Clone the Repository

```bash
git clone https://github.com/chopra-yuvraj/CleanIT.git
cd CleanIT
```

### 2. Set Up the Backend

```bash
cd backend

# Install dependencies
npm install

# Create .env from the example
cp .env.example .env

# Edit .env with your MongoDB Atlas connection string
# MONGODB_URI=mongodb+srv://<username>:<password>@<cluster>.mongodb.net/cleanit
# JWT_SECRET=<generate with: openssl rand -hex 32>

# Create indexes
npm run create-indexes

# Seed the database with sample data
npm run seed

# Start the server
npm start
```

### 3. Set Up the Flutter Frontend

```bash
cd ..  # Back to project root

# Install Flutter dependencies
flutter pub get

# Copy .env.example to .env and fill in your values
cp .env.example .env

# Run the app
flutter run --dart-define=QR_SIGNING_SECRET=<your_secret>
```

---

## DBMS Features Demonstrated

> See [`DATABASE_DOCUMENTATION.md`](DATABASE_DOCUMENTATION.md) for complete technical details.

| # | Feature | Location |
|---|---|---|
| 1 | **Multi-document ACID Transactions** | `routes/requests.js` — accept endpoint |
| 2 | **Aggregation Pipelines** ($group, $lookup, $facet, $unwind) | `routes/analytics.js` |
| 3 | **Partial Unique Index** | `models/Request.js` — one active request per student |
| 4 | **TTL Index** | `models/AuditLog.js` — 90-day auto-expiry |
| 5 | **Text Index + Full-text Search** | `models/Request.js` + `routes/admin.js` |
| 6 | **Sparse Index** | `models/User.js` — fcmToken |
| 7 | **Compound Index** | `models/User.js` — role + isOnDuty |
| 8 | **Optimistic Concurrency Control** | `routes/requests.js` — version key |
| 9 | **Soft Delete** | `routes/requests.js` — logical deletion |
| 10 | **Bulk Write Operations** | `routes/admin.js` — bulk cancel |
| 11 | **Query Explain Plans** | `routes/dbms.js` — IXSCAN vs COLLSCAN |
| 12 | **Embedded Documents** | `models/Request.js` — assignment subdocument |
| 13 | **Change Data Capture** | `utils/auditLogger.js` — CDC via audit logs |
| 14 | **Schema Validation** | Mongoose enum, required, custom validators |
| 15 | **Data Export** | `routes/admin.js` — JSON export |

---

## API Endpoints

| Method | Endpoint | Description |
|---|---|---|
| `POST` | `/api/auth/register` | Register a new user |
| `POST` | `/api/auth/login` | Login and receive JWT |
| `GET` | `/api/requests/open` | List open requests (cleaners) |
| `POST` | `/api/requests` | Create a cleaning request (students) |
| `POST` | `/api/requests/:id/accept` | Accept a request (transaction) |
| `POST` | `/api/requests/:id/start` | Start a job |
| `POST` | `/api/requests/:id/complete` | Complete a job (QR verified) |
| `DELETE` | `/api/requests/:id` | Soft-delete a request |
| `GET` | `/api/requests/search?q=...` | Full-text search on notes |
| `POST` | `/api/feedback` | Submit feedback |
| `GET` | `/api/analytics/overview` | Dashboard metrics (aggregation) |
| `GET` | `/api/analytics/by-block` | Requests by hostel block |
| `GET` | `/api/analytics/cleaner-leaderboard` | Cleaner rankings |
| `GET` | `/api/analytics/peak-hours` | Peak hours distribution |
| `GET` | `/api/analytics/trends` | Daily request trends |
| `GET` | `/api/analytics/task-distribution` | Sweeping vs mopping stats |
| `GET` | `/api/analytics/rating-distribution` | Feedback rating histogram |
| `GET` | `/api/analytics/cleaner-efficiency` | Cleaner time metrics |
| `GET` | `/api/dbms/explain` | Query execution plans |
| `GET` | `/api/dbms/indexes` | Full index catalog |
| `GET` | `/api/dbms/collection-stats` | Collection statistics |
| `POST` | `/api/dbms/transaction-demo` | Transaction with rollback demo |
| `GET` | `/api/dbms/aggregation-showcase` | Aggregation pipeline showcase |

---

## Test Credentials (after seeding)

| Role | Email | Password |
|---|---|---|
| Student | `yuvraj@vit.in` | `password123` |
| Cleaner | `ravi@cleanit.com` | `password123` |
| Admin | `admin@cleanit.com` | `admin123` |

---

## Screenshots

> Coming soon.

---

## License

**Proprietary — All Rights Reserved.**
See [LICENSE](LICENSE) for details. This code is viewable for demonstration purposes only. No permission is granted to copy, modify, or distribute.

For licensing inquiries, contact the author.
