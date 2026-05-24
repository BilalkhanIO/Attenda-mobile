# Attenda Flutter — Mobile App

iOS & Android employee mobile app for the Attenda Workforce Management Platform.

## Features

| Tab | Screens |
|-----|---------|
| 🏠 Home | Today's status card, live hours counter, auto IP check-in, QR scan button, quick actions, shift preview |
| ⏰ Attendance | Monthly history, status summary chips, day detail bottom sheet, override indicators |
| 📅 Leave | Leave requests list, balance progress bars, cancel request with confirmation |
| 📆 Schedule | Upcoming shifts list with colour coding, swap request management |
| 👤 Profile | Personal info, payslips list, performance reviews with star ratings, sign out |

### Key capabilities
- **IP Auto Check-in** — detects office WiFi and calls `/attendance/ip-event` automatically on app resume
- **QR Scanner** — full-screen camera with custom scan overlay, success/error animations
- **Remote Work** — declares remote with duration (full/morning/afternoon), triggers AI WhatsApp nudges
- **Leave Requests** — submit, view balance with progress bars, cancel pending requests
- **JWT auto-refresh** — Dio interceptor silently refreshes expired tokens

## Setup

```bash
# Prerequisites: Flutter 3.x, Dart 3.x

# 1. Install dependencies
flutter pub get

# 2. Set API URL (optional — defaults to localhost:5000)
# In lib/services/api_service.dart change defaultValue or use:
flutter run --dart-define=API_URL=https://your-api.com/api/v1

# 3. Run
flutter run
```

## Required Permissions

### Android (`android/app/src/main/AndroidManifest.xml`)
```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
<uses-permission android:name="android.permission.CAMERA" />
```

### iOS (`ios/Runner/Info.plist`)
```xml
<key>NSCameraUsageDescription</key>
<string>Camera needed to scan office QR codes for check-in</string>
<key>NSLocalNetworkUsageDescription</key>
<string>Network info needed for automatic check-in detection</string>
```

## Architecture

```
lib/
├── main.dart                   # App entry, providers
├── router.dart                 # go_router with auth guard
├── shell.dart                  # Bottom nav shell (5 tabs)
├── services/
│   ├── api_service.dart        # Dio client, all API calls, JWT refresh interceptor
│   └── auth_provider.dart      # ChangeNotifier, JWT decode, login/logout
├── utils/
│   └── theme.dart              # Attenda design tokens, colors, theme
├── widgets/
│   └── common.dart             # StatusBadge, UserAvatar, AppCard, AppButton, etc.
└── screens/
    ├── auth/login_screen.dart  # Email/password + forgot password bottom sheet
    ├── home/
    │   ├── home_screen.dart    # Status card, quick actions, IP detection, timer
    │   └── remote_work_screen.dart
    ├── attendance/
    │   ├── attendance_screen.dart  # History with month picker, summary chips
    │   └── qr_scanner_screen.dart # Camera + scan overlay + success/error states
    ├── leave/
    │   ├── leave_screen.dart       # Requests + balance tabs
    │   └── request_leave_screen.dart
    ├── schedule/schedule_screen.dart
    └── profile/profile_screen.dart
```

## Backend Connection

Set `API_URL` at build time or edit `lib/services/api_service.dart`:
```dart
const _baseUrl = String.fromEnvironment('API_URL', defaultValue: 'http://localhost:5000/api/v1');
```

For Android emulator connecting to local backend, use `10.0.2.2` instead of `localhost`.
