# CleanIT — Step-by-Step Setup Guide

> Complete guide to get CleanIT running from zero to a working app on your device.

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Clone the Repository](#2-clone-the-repository)
3. [Supabase Project Setup](#3-supabase-project-setup)
4. [Run Database Migrations](#4-run-database-migrations)
5. [Create Storage Bucket](#5-create-storage-bucket)
6. [Set Up Edge Function Secrets](#6-set-up-edge-function-secrets)
7. [Deploy Edge Functions](#7-deploy-edge-functions)
8. [Firebase / FCM Setup](#8-firebase--fcm-setup)
9. [Flutter Project Setup](#9-flutter-project-setup)
10. [Configure Environment Variables](#10-configure-environment-variables)
11. [Run the App](#11-run-the-app)
12. [Seed Test Data](#12-seed-test-data)
13. [Testing the Workflows](#13-testing-the-workflows)
14. [Troubleshooting](#14-troubleshooting)

---

## 1. Prerequisites

Install the following tools before starting:

| Tool | Version | Install Command / Link |
|------|---------|----------------------|
| **Flutter SDK** | ≥ 3.19 | [flutter.dev/docs/get-started/install](https://flutter.dev/docs/get-started/install) |
| **Dart** | ≥ 3.3 | Bundled with Flutter |
| **Node.js** | ≥ 18 | [nodejs.org](https://nodejs.org) |
| **Supabase CLI** | ≥ 1.150 | `npm install -g supabase` |
| **Git** | any | [git-scm.com](https://git-scm.com) |
| **Android Studio** or **Xcode** | latest | For emulator/simulator |

Verify installations:

```bash
flutter --version
dart --version
node --version
supabase --version
```

---

## 2. Clone the Repository

```bash
git clone https://github.com/chopra-yuvraj/CleanIT.git
cd CleanIT
```

---

## 3. Supabase Project Setup

### 3.1 Create a Supabase Account & Project

1. Go to [supabase.com](https://supabase.com) and sign up (free).
2. Click **"New Project"**.
3. Fill in:
   - **Name**: `cleanit`
   - **Database Password**: (save this — you'll need it)
   - **Region**: Choose the closest to your campus
4. Wait ~2 minutes for the project to provision.

### 3.2 Get Your Project Credentials

Once the project is ready, go to **Settings → API** and note down:

| Value | Where to Find | What It's For |
|-------|--------------|---------------|
| **Project URL** | `Settings → API → Project URL` | `SUPABASE_URL` |
| **anon (public) key** | `Settings → API → Project API Keys → anon` | Flutter client |
| **service_role key** | `Settings → API → Project API Keys → service_role` | Edge Functions (server-side only) |

> ⚠️ **NEVER** expose the `service_role` key in client-side code. It bypasses RLS.

### 3.3 Link Supabase CLI to Your Project

```bash
supabase login
supabase link --project-ref YOUR_PROJECT_REF
```

Replace `YOUR_PROJECT_REF` with the reference ID from your Supabase dashboard URL: 
`https://supabase.com/dashboard/project/<THIS_PART>`

---

## 4. Run Database Migrations

The migration file at `supabase/migrations/001_initial_schema.sql` contains everything: tables, indexes, RLS policies, RPC functions, and realtime publication.

### Option A: Via Supabase CLI (Recommended)

```bash
supabase db push
```

This automatically runs all migration files in `supabase/migrations/`.

### Option B: Via SQL Editor (Manual)

1. Go to **Supabase Dashboard → SQL Editor**.
2. Click **"New Query"**.
3. Copy-paste the entire contents of `supabase/migrations/001_initial_schema.sql`.
4. Click **"Run"**.

### Verify

Go to **Table Editor** in the dashboard. You should see four tables:
- `users`
- `requests`
- `assignments`
- `feedback`

Go to **Database → Functions**. You should see:
- `accept_request`
- `report_room_locked`
- `start_job`
- `complete_job`

---

## 5. Create Storage Bucket

The `proof-photos` bucket stores the locked-door proof photos uploaded by cleaners.

### Via Dashboard

1. Go to **Storage** in the Supabase Dashboard.
2. Click **"New Bucket"**.
3. Set:
   - **Name**: `proof-photos`
   - **Public**: ✅ Yes (so photos can be viewed in admin dashboard)
   - **File size limit**: `5 MB`
   - **Allowed MIME types**: `image/jpeg, image/png, image/webp`
4. Click **"Create"**.

### Via SQL (Alternative)

```sql
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'proof-photos',
    'proof-photos',
    true,
    5242880,
    ARRAY['image/jpeg', 'image/png', 'image/webp']
);
```

### Add Storage Policies

Go to **Storage → proof-photos → Policies** and add:

```sql
-- Allow authenticated users to upload
CREATE POLICY "Authenticated users can upload proof photos"
ON storage.objects FOR INSERT
WITH CHECK (bucket_id = 'proof-photos' AND auth.role() = 'authenticated');

-- Allow anyone to view proof photos (for admin auditing)
CREATE POLICY "Public read access for proof photos"
ON storage.objects FOR SELECT
USING (bucket_id = 'proof-photos');
```

---

## 6. Set Up Edge Function Secrets

Edge Functions need three secrets:

```bash
# Set each secret (you'll be prompted to enter the value)
supabase secrets set FCM_SERVER_KEY
supabase secrets set QR_SIGNING_SECRET

# The SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are auto-injected
```

| Secret | Where to Get It |
|--------|----------------|
| `FCM_SERVER_KEY` | Firebase Console → Project Settings → Cloud Messaging → Server Key |
| `QR_SIGNING_SECRET` | Generate a random 32+ char string: `openssl rand -hex 32` |

> The `QR_SIGNING_SECRET` must match between the Edge Function (server) and the Flutter app (client) so they can sign/verify QR payloads identically.

---

## 7. Deploy Edge Functions

```bash
# Deploy all functions at once
supabase functions deploy accept-request
supabase functions deploy report-locked
supabase functions deploy create-request
supabase functions deploy verify-qr
```

### Verify Deployment

```bash
supabase functions list
```

You should see all four functions listed with status `Active`.

### Test a Function (Optional)

```bash
curl -X POST \
  'https://YOUR_PROJECT_REF.supabase.co/functions/v1/accept-request' \
  -H "Authorization: Bearer YOUR_ANON_KEY" \
  -H "Content-Type: application/json" \
  -d '{"request_id": "test"}'
```

Expected: `401 Unauthorized` (because the anon key doesn't have a user session — this is correct).

---

## 8. Firebase / FCM Setup

### 8.1 Create a Firebase Project

1. Go to [console.firebase.google.com](https://console.firebase.google.com).
2. Click **"Add Project"** → Name it `CleanIT` → Disable Google Analytics (optional).
3. Wait for project creation.

### 8.2 Add Android App

1. In Firebase Console, click **"Add App" → Android**.
2. Set:
   - **Package name**: `com.cleanit.app` (must match your Flutter `applicationId`)
   - **App nickname**: `CleanIT Android`
3. Download `google-services.json`.
4. Place it in: `android/app/google-services.json`.

### 8.3 Add iOS App (if targeting iOS)

1. Click **"Add App" → iOS**.
2. Set:
   - **Bundle ID**: `com.cleanit.app`
3. Download `GoogleService-Info.plist`.
4. Place it in: `ios/Runner/GoogleService-Info.plist`.

### 8.4 Get FCM Server Key

1. Firebase Console → **Project Settings** → **Cloud Messaging** tab.
2. Under "Cloud Messaging API (Legacy)", copy the **Server key**.
3. This is what you set as `FCM_SERVER_KEY` in Step 6.

> ℹ️ If you see "Cloud Messaging API (Legacy) is disabled", click the three-dot menu → "Manage API in Google Cloud Console" → Enable it.

### 8.5 Configure Android for FCM

Add to `android/app/build.gradle`:

```gradle
dependencies {
    // ... existing deps
    implementation platform('com.google.firebase:firebase-bom:32.7.0')
    implementation 'com.google.firebase:firebase-messaging'
}
```

Add to `android/build.gradle`:

```gradle
buildscript {
    dependencies {
        // ... existing deps
        classpath 'com.google.gms:google-services:4.4.0'
    }
}
```

Add at the bottom of `android/app/build.gradle`:

```gradle
apply plugin: 'com.google.gms.google-services'
```

### 8.6 Create Notification Channels (Android)

For the urgent siren sound, create a custom notification channel.

Add `android/app/src/main/res/raw/siren.wav` — any short alarm sound file.

In `android/app/src/main/kotlin/.../MainActivity.kt`:

```kotlin
import android.app.NotificationChannel
import android.app.NotificationManager
import android.media.AudioAttributes
import android.net.Uri
import android.os.Build
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        createNotificationChannels()
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)

            // Normal requests
            val normalChannel = NotificationChannel(
                "normal_requests",
                "Cleaning Requests",
                NotificationManager.IMPORTANCE_HIGH
            )
            manager.createNotificationChannel(normalChannel)

            // Urgent requests with siren sound
            val urgentChannel = NotificationChannel(
                "urgent_requests",
                "Urgent Requests",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                val soundUri = Uri.parse(
                    "android.resource://${packageName}/raw/siren"
                )
                setSound(soundUri, AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                    .build())
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 500, 200, 500)
            }
            manager.createNotificationChannel(urgentChannel)
        }
    }
}
```

---

## 9. Flutter Project Setup

### 9.1 Initialize Flutter Project (if not already done)

If this is a fresh clone (no `pubspec.yaml` yet):

```bash
flutter create --org com.cleanit --project-name cleanit .
```

### 9.2 Add Dependencies

Add these to `pubspec.yaml` under `dependencies:`:

```yaml
dependencies:
  flutter:
    sdk: flutter

  # Supabase
  supabase_flutter: ^2.3.0

  # Firebase / FCM
  firebase_core: ^2.27.0
  firebase_messaging: ^14.7.0

  # QR Code
  qr_flutter: ^4.1.0          # Generate QR codes (student side)
  mobile_scanner: ^4.0.0       # Scan QR codes (cleaner side)

  # Camera & Image
  image_picker: ^1.0.7         # Capture proof photos

  # Crypto (for QR HMAC signing)
  crypto: ^3.0.3

  # HTTP
  http: ^1.2.0

  # State Management (optional — can upgrade to Riverpod/Bloc later)
  # provider: ^6.1.0
```

Then run:

```bash
flutter pub get
```

### 9.3 Initialize Supabase & Firebase in `main.dart`

```dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

// Background FCM handler (must be top-level function)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  // Handle background message (e.g., show local notification)
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Initialize Supabase
  await Supabase.initialize(
    url: const String.fromEnvironment('SUPABASE_URL'),
    anonKey: const String.fromEnvironment('SUPABASE_ANON_KEY'),
  );

  // Request FCM permission
  final messaging = FirebaseMessaging.instance;
  await messaging.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  );

  // Get FCM token and save to user profile
  final fcmToken = await messaging.getToken();
  debugPrint('FCM Token: $fcmToken');

  runApp(const CleanITApp());
}

class CleanITApp extends StatelessWidget {
  const CleanITApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CleanIT',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF11111B),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF89B4FA),
          secondary: Color(0xFFA6E3A1),
          error: Color(0xFFFF6B6B),
          surface: Color(0xFF1E1E2E),
        ),
      ),
      home: const Placeholder(), // Replace with your auth/home screen
    );
  }
}
```

---

## 10. Configure Environment Variables

### For Flutter (build-time injection)

Run the app with Supabase credentials injected via `--dart-define`:

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=your_anon_key_here
```

### For VS Code (launch.json)

Create `.vscode/launch.json`:

```json
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "CleanIT (Debug)",
      "request": "launch",
      "type": "dart",
      "args": [
        "--dart-define=SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co",
        "--dart-define=SUPABASE_ANON_KEY=your_anon_key_here"
      ]
    }
  ]
}
```

### For QR Signing Secret (in the app)

Create a config file `lib/config/app_config.dart`:

```dart
class AppConfig {
  // This MUST match the QR_SIGNING_SECRET set in Supabase Edge Function secrets
  static const String qrSigningSecret = String.fromEnvironment(
    'QR_SIGNING_SECRET',
    defaultValue: 'YOUR_SECRET_HERE_FOR_DEV',
  );

  static const Duration qrExpiry = Duration(minutes: 3);
}
```

> ⚠️ In production, inject this via `--dart-define=QR_SIGNING_SECRET=...` instead of hardcoding.

---

## 11. Run the App

### Android Emulator

```bash
flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
```

### iOS Simulator

```bash
cd ios && pod install && cd ..
flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
```

### Chrome (Web — for Admin Dashboard development)

```bash
flutter run -d chrome --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
```

---

## 12. Seed Test Data

Run this in the Supabase SQL Editor to create test users:

```sql
-- Create a test student
INSERT INTO users (auth_id, email, name, role, block, room_number)
VALUES (
    '00000000-0000-0000-0000-000000000001',
    'student@test.com',
    'Test Student',
    'student',
    'A',
    '101'
);

-- Create test cleaners
INSERT INTO users (auth_id, email, name, role, is_on_duty)
VALUES
    ('00000000-0000-0000-0000-000000000002', 'cleaner1@test.com', 'Cleaner Raj',   'cleaner', true),
    ('00000000-0000-0000-0000-000000000003', 'cleaner2@test.com', 'Cleaner Priya', 'cleaner', true),
    ('00000000-0000-0000-0000-000000000004', 'cleaner3@test.com', 'Cleaner Amit',  'cleaner', true);

-- Create a test admin
INSERT INTO users (auth_id, email, name, role)
VALUES (
    '00000000-0000-0000-0000-000000000005',
    'admin@test.com',
    'Hostel Admin',
    'admin'
);
```

---

## 13. Testing the Workflows

### Test 1: Create a Request

1. Log in as the **student**.
2. Navigate to "New Request".
3. Toggle **Floor Sweeping** ON.
4. Submit the request.
5. **Expected**: Request appears in `requests` table with status `OPEN`.

### Test 2: Accept Request (Race Condition)

1. Open 3 browser tabs / emulators logged in as 3 different cleaners.
2. Create a request from the student.
3. Have all 3 cleaners tap "Accept" simultaneously.
4. **Expected**: Exactly ONE cleaner gets the assignment. The other two see "Already accepted."

### Test 3: QR Verification

1. Cleaner taps "Start Job" → status becomes `IN_PROGRESS`.
2. Student opens app → taps "Show QR".
3. Cleaner scans the QR.
4. **Expected**: Status becomes `COMPLETED`, student sees feedback prompt.

### Test 4: Room Locked

1. Cleaner taps "Room Locked / Student Not Present".
2. Camera opens → cleaner takes a photo.
3. **Expected**: Status becomes `CANCELLED_ROOM_LOCKED`, student gets a push notification, proof photo appears in Supabase Storage.

### Test 5: Rate Limiting

1. Student creates a request (status `OPEN`).
2. Student tries to create another request.
3. **Expected**: Error — "You already have an active cleaning request."

---

## 14. Troubleshooting

| Problem | Solution |
|---------|----------|
| `supabase db push` fails | Ensure you've run `supabase link` first |
| Edge function 500 errors | Check `supabase functions logs <function-name>` |
| FCM not receiving notifications | Verify `google-services.json` is in `android/app/` |
| QR scan fails with "invalid signature" | Ensure `QR_SIGNING_SECRET` matches between app and Edge Function |
| "Active request exists" when none visible | Check for requests stuck in `OPEN`/`ASSIGNED`/`IN_PROGRESS` in the DB |
| Realtime not updating | Verify `ALTER PUBLICATION supabase_realtime ADD TABLE requests` was run |
| iOS build fails | Run `cd ios && pod install` before building |
| Storage upload fails | Ensure `proof-photos` bucket exists and has upload policies |

---

## Next Steps After Setup

- [ ] Build remaining Flutter screens (Student Home, New Request Form, Auth)
- [ ] Implement QR code generation on the student side using `qr_flutter`
- [ ] Add FCM token refresh logic (save updated token to `users.fcm_token`)
- [ ] Build the Admin Web Dashboard
- [ ] Set up CI/CD (GitHub Actions → Supabase deploy)
- [ ] Add error monitoring (Sentry free tier)
