<p align="center">
  <img src="https://img.icons8.com/fluency/96/broom.png" alt="CleanIT" width="80"/>
</p>

<h1 align="center">CleanIT</h1>

<p align="center">
  <strong>Real-time hostel room cleaning app for college students.</strong><br/>
  Request cleaning → Cleaners race to accept → QR-verified completion.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.19+-02569B?logo=flutter&logoColor=white" alt="Flutter"/>
  <img src="https://img.shields.io/badge/Supabase-Backend-3ECF8E?logo=supabase&logoColor=white" alt="Supabase"/>
  <img src="https://img.shields.io/badge/Firebase-FCM-FFCA28?logo=firebase&logoColor=black" alt="Firebase"/>
  <img src="https://img.shields.io/badge/License-Proprietary-red" alt="License"/>
</p>

---

## What is CleanIT?

CleanIT is a mobile + web application that connects hostel students with cleaning staff in real time. Students submit a cleaning request, all on-duty cleaners receive an instant push notification, and the fastest cleaner to tap "Accept" wins the job — guaranteed by database-level row locking. Jobs are verified via time-limited, HMAC-signed QR codes to prevent fraud.

### Key Features

| Feature | Description |
|---|---|
| **Fastest Finger First** | `FOR UPDATE SKIP LOCKED` — exactly one cleaner wins, zero race conditions |
| **Real-time Updates** | Supabase Realtime (WebSocket) for instant UI changes |
| **QR Verification** | HMAC-signed, 3-minute expiry QR codes prevent screenshot abuse |
| **Room Locked Reporting** | Mandatory proof photo upload for locked-door cancellations |
| **Push Notifications** | Firebase Cloud Messaging with urgent/normal channels |
| **Rate Limiting** | One active request per student enforced at database level |

---

## Tech Stack

- **Frontend**: Flutter (Android, iOS, Web)
- **Backend**: Supabase — PostgreSQL + Edge Functions (Deno) + Realtime + Storage
- **Notifications**: Firebase Cloud Messaging
- **Auth**: Supabase Auth (JWT)
- **Cost**: $0 — all services on free tiers

---

## Project Structure

```
CleanIT/
├── lib/
│   ├── config/        # App configuration & theme
│   ├── models/        # Data models (User, Request)
│   ├── screens/       # UI screens (Auth, Student, Cleaner)
│   └── services/      # Business logic (Auth, QR, Requests)
├── supabase/
│   ├── functions/     # Edge functions (accept, create, report, verify)
│   └── migrations/    # Database schema & RLS policies
├── web/               # Flutter web shell
├── android/           # Android platform
├── ios/               # iOS platform
├── firebase.json      # Firebase Hosting config
└── vercel.json        # Vercel deployment config
```

---

## Getting Started

### Prerequisites

- Flutter SDK ≥ 3.19
- Node.js ≥ 18 (for Supabase CLI)
- Supabase account (free)
- Firebase project (free)

### Setup

```bash
# Clone
git clone https://github.com/chopra-yuvraj/CleanIT.git
cd CleanIT

# Install Flutter dependencies
flutter pub get

# Copy environment template and fill in your keys
cp .env.example .env

# Run on your device
flutter run \
  --dart-define=SUPABASE_URL=<your_url> \
  --dart-define=SUPABASE_ANON_KEY=<your_key> \
  --dart-define=QR_SIGNING_SECRET=<your_secret>

# Build for web
flutter build web --release
```

### Deploy

**Vercel** (static site):
```bash
flutter build web --release
npx vercel --prod
```

**Firebase Hosting**:
```bash
flutter build web --release
npx firebase-tools deploy --only hosting
```

---

## Screenshots

> Coming soon.

---

## License

**Proprietary — All Rights Reserved.**
See [LICENSE](LICENSE) for details. This code is viewable for demonstration purposes only. No permission is granted to copy, modify, or distribute.

For licensing inquiries, contact the author.
