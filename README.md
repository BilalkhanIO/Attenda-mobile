# Attenda Flutter — Mobile App

iOS & Android employee mobile app for the Attenda Workforce Management Platform.

See [FEATURES_AND_ARCHITECTURE.md](docs/FEATURES_AND_ARCHITECTURE.md) for the mobile route/screen map, data flow, capability rules, shared UI conventions, and feature development checklist. The workspace [system feature guide](../SYSTEM_FEATURE_GUIDE.md) describes cross-client behavior.

## Features

The shell provides Home, Attendance, Leave, Schedule, optional Project Time, and Profile tabs. From those areas, employees can access AI chat, approvals where authorized, projects/tasks, notifications, remote work, open shifts, availability, QR checkpoints, expenses, payslips, documents, announcements, onboarding, kudos, performance, and personal settings. See [the mobile feature guide](docs/FEATURES_AND_ARCHITECTURE.md) for every screen and route.

Attendance combines user-initiated controls with organization policy, network/location evidence, background heartbeats when configured, offline event queuing, and server reconciliation. The API remains authoritative for recorded status and time; the client timer is a display aid. Other capabilities include project task collaboration, shift rounds/checkpoints, emergency open-shift claims, AI-assisted HR workflows, dynamic permission-aware navigation, and session/token refresh.

## Setup

```bash
# Prerequisites: Flutter 3.x, Dart 3.x

# 1. Install dependencies
flutter pub get

# 2. Point the app at the API for your target. Never use a production URL for
#    local development. The safe fallback is http://localhost:5000/api/v1.
# Android emulator:
flutter run --dart-define=API_URL=http://10.0.2.2:5000/api/v1
# iOS simulator:
flutter run --dart-define=API_URL=http://127.0.0.1:5000/api/v1
# Physical phone: replace with the development computer's LAN IP address.
# flutter run --dart-define=API_URL=http://192.168.1.20:5000/api/v1

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

Keep the route/screen inventory and data-flow details in the canonical
[mobile feature and architecture guide](docs/FEATURES_AND_ARCHITECTURE.md) so
this README does not drift into a second, incomplete architecture map.

## Backend Connection

`API_URL` is resolved at build time and shared by the foreground attendance
service and the normal API client. A local build without the define uses a safe
localhost URL; it never defaults to production. The debug log shows the chosen
scheme and host only, without credentials, paths, or query values.
```dart
const apiBaseUrl = String.fromEnvironment('API_URL', defaultValue: 'http://localhost:5000/api/v1');
```

For Android emulators connecting to a backend on the development computer, use
`10.0.2.2` instead of `localhost`. iOS simulators can use `127.0.0.1`. A
physical device must use a reachable LAN address and both devices must be on a
network that permits the connection. Release builds must set `API_URL` to the
intended environment explicitly.
