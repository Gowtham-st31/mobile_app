# Firebase Cloud Messaging (FCM) Setup

This repo now supports true push notifications (FCM) so users get notification-bar alerts even when the app is closed/killed.

## 1) Create Firebase project

- Go to Firebase Console → create a project.
- Enable **Cloud Messaging** (default).

## 2) Add Android app in Firebase

- Package name (must match Android `applicationId`): `com.example.powerloom_mobile`
- Download **google-services.json**
- Place it at:
  - `powerloom_mobile/android/app/google-services.json`

Notes:
- The file is currently ignored by git in `powerloom_mobile/android/.gitignore`.

## 3) Backend: create a Service Account

- Firebase Console → Project settings → Service accounts
- Generate a new private key JSON.

### Configure on Render

Set **one** of these environment variables:

- `FIREBASE_SERVICE_ACCOUNT_JSON` → paste the full JSON content as a single JSON string
  - If your dashboard strips newlines, paste it as one line.

OR

- `FIREBASE_SERVICE_ACCOUNT_FILE` → path to the JSON file (only if you mount a file on the server)

Optional:
- `FCM_TOKENS_COLLECTION` (default: `fcm_tokens`)

## 4) How it works

- Mobile registers its FCM token to the server at `POST /api/mobile/fcm/register` after login.
- When admin calls `POST /admin/broadcast_message`, the server:
  - persists the message
  - emits Socket.IO (`admin_message`)
  - sends an **FCM push** to all registered tokens (best-effort)

## 5) Release checklist

- Build a new APK (current app version in `pubspec.yaml`): `1.0.6+15`
- Upload APK to GitHub Releases
- Update Render env vars:
  - `MOBILE_ANDROID_VERSION_CODE`
  - `MOBILE_ANDROID_VERSION_NAME`
  - `MOBILE_ANDROID_APK_URL`
