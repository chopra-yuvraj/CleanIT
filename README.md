# CleanIT 🧹

> **Free, real-time hostel room cleaning app for college students.**
> Request cleaning → Cleaners race to accept → QR-verified completion.

## Quick Start

See the full [**Setup Guide**](docs/setup-guide.md) for detailed instructions.

## Architecture

- **Frontend**: Flutter (iOS + Android)
- **Backend**: Supabase (PostgreSQL + Edge Functions + Realtime)
- **Notifications**: Firebase Cloud Messaging (FCM)
- **Cost**: $0 (all services on free tiers)

→ [Architecture Deep Dive](docs/architecture.md)

## Project Structure

```
CleanIT/
├── docs/
│   ├── erd.md              # Entity-Relationship Diagram
│   ├── api-spec.yaml       # OpenAPI 3.0 Specification
│   ├── architecture.md     # System Architecture & Diagrams
│   └── setup-guide.md      # Step-by-Step Setup Guide
├── supabase/
│   ├── migrations/
│   │   └── 001_initial_schema.sql  # Database schema, RPC functions, RLS
│   └── functions/
│       ├── accept-request/         # Race-safe job acceptance
│       ├── create-request/         # Request creation + FCM broadcast
│       ├── report-locked/          # Room locked with photo proof
│       └── verify-qr/             # QR code verification
├── lib/
│   └── screens/
│       └── cleaner_job_details.dart  # Cleaner's active job screen
└── README.md
```

## Key Features

| Feature | How It Works |
|---------|-------------|
| **Fastest Finger First** | `SELECT ... FOR UPDATE SKIP LOCKED` — only one cleaner wins |
| **Real-time Updates** | Supabase Realtime (WebSocket) for instant status changes |
| **QR Verification** | HMAC-signed, 3-minute expiry, prevents screenshots |
| **Anti-Abuse** | Mandatory proof photos for locked-room reports |
| **Rate Limiting** | One active request per student (DB-level constraint) |

## License

Internal use only — [Your College Name].
