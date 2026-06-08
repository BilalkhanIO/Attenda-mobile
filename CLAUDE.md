# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Install dependencies
flutter pub get

# Run on a connected device/emulator
flutter run

# Run with a specific API backend
flutter run --dart-define=API_URL=https://your-api.com/api/v1

# Run on Android emulator pointing to local backend
flutter run --dart-define=API_URL=http://10.0.2.2:5000/api/v1

# Analyze / lint
flutter analyze

# Run all tests
flutter test

# Run a single test file
flutter test test/widget_test.dart

# Regenerate Riverpod providers (after annotating with @riverpod)
dart run build_runner build --delete-conflicting-outputs

# Watch mode for code generation
dart run build_runner watch --delete-conflicting-outputs
```

## Architecture

### State Management — intentional split
`AuthProvider` (in `lib/services/auth_provider.dart`) uses the **`provider`** package (`ChangeNotifier` / `ChangeNotifierProvider`). The pubspec also includes **`flutter_riverpod`** for any future non-auth state. Do not migrate auth to Riverpod without careful attention to the router, which calls `buildRouter(auth)` and passes `AuthProvider` as a `refreshListenable`.

### Routing (`lib/router.dart`)
`buildRouter(AuthProvider auth)` returns a `GoRouter` configured with:
- `refreshListenable: auth` — router re-evaluates on every `notifyListeners()` call from auth
- A `redirect` guard: unauthenticated requests go to `/login`; authenticated users on `/login` go to `/home`
- A `ShellRoute` wrapping all five tabs via `AppShell` (bottom nav). Two routes — `/attendance/qr` and `/leave/request` — use `parentNavigatorKey: _rootKey` so they render full-screen above the shell.

### API Layer (`lib/services/api_service.dart`)
Single `ApiService` singleton exposed as the top-level `api` constant. All HTTP calls go through a single `Dio` instance with two interceptors:
1. **Request**: attaches `Authorization: Bearer <token>` from `flutter_secure_storage`
2. **Error (401)**: silently refreshes via `/auth/refresh`, retries the original request; on failure clears all stored tokens

The base URL is resolved at compile time via `String.fromEnvironment('API_URL')`, defaulting to `http://localhost:5000/api/v1`.

### Auth (`lib/services/auth_provider.dart`)
JWT tokens (`access_token`, `refresh_token`) are persisted in `flutter_secure_storage`. On app start, `_init()` reads and decodes the access token; if valid and non-expired, the user is restored without a network call. `AuthUser` exposes role helpers (`isManager`, `isHRAdmin`, `isSuperAdmin`).

### WiFi Auto Check-in (`lib/services/wifi_service.dart`)
`WifiAttendanceService` is a singleton initialized in `main()` **before** `runApp`. It:
- Registers a `Workmanager` periodic background task (`com.attenda.ipPoll`, every 5 minutes) to detect office WiFi even when the app is backgrounded
- Listens to `connectivity_plus` for foreground WiFi connect/disconnect events
- Implements a **10-minute grace period** timer: when the device leaves WiFi, it waits 10 minutes before triggering auto check-out (in case of brief network drops)
- Queues failed events in a **Hive box** (`offline_queue`) and replays them on next connectivity restore
- Blocks auto check-in if a VPN is detected

### Theming (`lib/utils/theme.dart`)
All design tokens live in `AppColors` (Tailwind-style naming, e.g. `primary600`, `gray200`). `StatusColors` maps attendance status strings (`'in'`, `'late'`, `'absent'`, `'remote'`, `'leave'`) to background color, foreground color, display label, and icon. `AppTheme.light` is the single `ThemeData` used throughout.

### Shared Widgets (`lib/widgets/common.dart`)
Common components (`StatusBadge`, `UserAvatar`, `AppCard`, `AppButton`, etc.) are all in a single file. Screens import from here rather than defining one-off widgets inline.

## Key Conventions
- All API responses are unwrapped from `res.data['data']` before returning — the backend wraps all payloads in a `{ "data": ... }` envelope.
- DM Sans is the project font, bundled under `assets/fonts/` and configured in `pubspec.yaml`. Use `GoogleFonts.dmSans(...)` or rely on `AppTheme.light`'s text theme rather than specifying font families ad-hoc.
- Navigation uses `context.go(path)` (replace) for tab switches and `context.push(path)` for full-screen overlays like the QR scanner.
