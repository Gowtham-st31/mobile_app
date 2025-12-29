# App Update System Guide

## Overview
Your Powerloom mobile app already has an **automatic update checker** built in. When users open the app, it checks if a newer version is available and shows an "UPDATE" banner with a direct download link.

---

## How It Works

1. **Backend serves version info**: The server at `/api/mobile/android/latest` returns:
   - `version_code` (integer, e.g., `2`)
   - `version_name` (string, e.g., `"1.0.1"`)
   - `apk_url` (download link to the APK)

2. **Flutter app checks on startup**: When a user opens the app, it:
   - Calls `/api/mobile/android/latest`
   - Compares the server's `version_code` with the installed app's version
   - If server version > installed version, shows an **"Update available"** banner

3. **User taps UPDATE**: Opens the APK download link in the browser/file manager so they can install the new version.

---

## Step-by-Step: Publish an Update

### 1. Build a New APK

In your Flutter project:

```powershell
cd C:\Users\gowth\powerloom2.0\powerloom_mobile

# **IMPORTANT**: Bump the version in pubspec.yaml first!
# Example: change version: 1.0.0+1 to version: 1.0.1+2
# The number after + is the versionCode (must increase)

flutter build apk --release
```

The APK will be at: `powerloom_mobile\build\app\outputs\flutter-apk\app-release.apk`

### 2. Host the APK

**Option A: Put it on your server (recommended if you control the backend)**

1. Copy `app-release.apk` to: `c:\Users\gowth\powerloom2.0\static\apk\powerloom_mobile.apk`
2. Your backend already serves it at: `http://yourserver.com/download/android`

**Option B: Upload to your website**

1. Upload `app-release.apk` to your website (e.g., `https://yoursite.com/downloads/powerloom-v1.0.1.apk`)
2. Use the absolute URL when configuring environment variables (next step)

### 3. Configure Environment Variables

Set these on your server (or in your `.env` file):

```env
# The versionCode from pubspec.yaml (the number after +)
MOBILE_ANDROID_VERSION_CODE=2

# The versionName from pubspec.yaml (the number before +)
MOBILE_ANDROID_VERSION_NAME=1.0.1

# (Optional) Full URL to your APK if hosted externally
# MOBILE_ANDROID_APK_URL=https://yoursite.com/downloads/powerloom-v1.0.1.apk

# (Optional) Filename if using your backend's /download/android route
# MOBILE_ANDROID_APK_FILENAME=powerloom_mobile.apk
```

**If you DON'T set `MOBILE_ANDROID_APK_URL`**, the backend automatically uses its own download route (`/download/android`).

### 4. Restart Your Server

After setting environment variables, restart your backend:

```powershell
# Example for local dev
cd c:\Users\gowth\powerloom2.0
python app.py
```

### 5. Users Get the Update

- When users open their old version of the app, they see: **"Update available: v1.0.1. Please download and install the latest version."**
- They tap **UPDATE** → browser opens the APK download link.
- They install the new APK (Android will prompt "Update existing app").

---

## Adding APK Download Link to Your Website

If you want to embed a download link on your website:

```html
<!-- In your website HTML -->
<a href="https://yourserver.com/download/android" download>
  Download Powerloom App (Android)
</a>
```

Or if hosted externally:

```html
<a href="https://yoursite.com/downloads/powerloom-v1.0.1.apk" download>
  Download Powerloom App v1.0.1
</a>
```

---

## Important Notes

### Version Numbers Must Increase

- **versionCode** (the number after `+` in `pubspec.yaml`): Must be **higher** than the previous release for the update check to work.
  - Example: `1.0.0+1` → `1.0.0+2` → `1.0.1+3`
- **versionName** (before the `+`): Can be any string (e.g., `1.0.1`), shown to users.

### APK Signing

- For users to **update** (not reinstall), all APKs must be signed with the **same keystore**.
- If you rebuild with a different keystore, users must uninstall the old app first.

### No Automatic Updates Like Play Store

- Users must **manually download and install** the new APK each time.
- This is how direct APK distribution works (no Play Store auto-update).

---

## Example Workflow

1. Edit code in Flutter project
2. Update `pubspec.yaml`: `version: 1.0.1+2` (increase the `+2` part)
3. `flutter build apk --release`
4. Copy `app-release.apk` to `static/apk/powerloom_mobile.apk` (or upload to website)
5. Set `.env`:
   ```
   MOBILE_ANDROID_VERSION_CODE=2
   MOBILE_ANDROID_VERSION_NAME=1.0.1
   ```
6. Restart backend
7. Users open their app → see update banner → tap UPDATE → install new APK

---

## Troubleshooting

**"Update banner doesn't show"**
- Check `MOBILE_ANDROID_VERSION_CODE` in `.env` is **higher** than the installed app's versionCode.
- Verify `/api/mobile/android/latest` returns the correct JSON (visit in browser).

**"APK download fails"**
- Ensure APK file exists at `static/apk/powerloom_mobile.apk` (or your custom path).
- Check file permissions (server can read it).

**"Can't install APK"**
- User needs to enable "Install from unknown sources" (Android setting).
- Ensure APK is signed with the same keystore as the currently installed app.

---

## Summary

✅ **Update system is already built into your app!**  
✅ Just bump version numbers, build APK, set environment variables, and restart server.  
✅ Users see a banner with an UPDATE button → download → install.

No code changes needed—just follow the steps above each time you release a new version.
