# Attenda-mobile — 2026 Best-Practice Research & Improvement Roadmap

**Date:** 2026-06-11
**Scope:** `/home/user/Attenda-mobile` — Flutter (Android-first), provider for auth + StatefulWidgets,
dio 5, go_router 13, hive 2 (offline queue), flutter_foreground_task 9, firebase_messaging 14
(declared), permission_handler 11.
**Companion docs:** `attenda-api/docs/ATTENDANCE_RESEARCH.md` covers WiFi-presence/doze reliability,
check-in methods, and the verified package-version table — referenced below, not repeated.
**Verification note:** §1 was researched live against pub.dev/riverpod.dev/docs.flutter.dev.
§2–§3 facts about THIS codebase were verified directly. Competitor-UX (§4) summarizes the verified
findings in ATTENDANCE_RESEARCH.md §1. §5–§7 combine the verified version table with established
knowledge (marked where not re-verified).

---

## 1. State management & architecture (researched live, 2026-06)

### Riverpod 3 status
- Riverpod 3.0 shipped Sept 2025; current stable **flutter_riverpod 3.3.2** (June 2026). provider is
  in **maintenance mode** — its author recommends Riverpod for new work, but there is no forced deadline.
- v3 highlights: automatic provider retry, experimental offline persistence + mutations, unified
  `Notifier` API, `Ref.mounted`, legacy providers demoted to `legacy.dart`. `riverpod_generator` 3.x
  is stable; codegen is optional-but-recommended.
- **provider and Riverpod coexist cleanly** (nest `ProviderScope` with `MultiProvider`); the official
  migration guide endorses incremental adoption. The GoRouter `refreshListenable: auth` wiring is
  preserved via a small `ValueNotifier` bridge pattern (Code With Andrea) or a `Notifier` that
  implements `Listenable`.

### What actually pays off here (priority order)
The Flutter team's official architecture guidance (MVVM: ViewModel per screen + Repository/Service
data layer, `Result<T>` sealed returns) is the real gap — not the provider→Riverpod swap:

1. **Typed models + repository layer.** `ApiService` returns raw `Map<String, dynamic>` straight to
   widgets; every screen re-parses fields defensively. Introduce domain models
   (`json_serializable`; freezed only where copyWith/equality earns its build cost — 2026 sentiment
   favors plain classes + sealed Dart 3 hierarchies) and repositories that own caching/queueing and
   return `Result<T, Failure>`.
2. **Sealed failure hierarchy for Dio.** Error handling today string-matches `e.toString()` for
   `'401'`/`'423'` (login_screen, two_factor_screen). Map `DioExceptionType` + status codes →
   `NetworkFailure / TimeoutFailure / UnauthorizedFailure / ServerFailure(code)` in ONE place
   (interceptor or repository helper). `dio_smart_retry` 7.x is the maintained retry interceptor.
3. **Decompose `home_screen.dart` (2,600+ lines)** strangler-fig style: extract leaf sections into
   separate widget *classes* (own rebuild boundary, testable), then a `HomeViewModel extends
   ChangeNotifier` per section on the existing provider package, then typed models behind it.
   Enforce a max-lines lint to prevent regression.
4. **Riverpod is step 4, not step 1** — adopt for new feature state once repositories exist;
   migrate auth last (router wiring risk; CLAUDE.md already warns about this).

## 2. Offline-first (verified against this codebase)

- **hive 2.2.3 is unmaintained (last publish June 2022).** Migrate to **hive_ce** (active drop-in
  fork, 2.19.x): imports change `package:hive_flutter` → `package:hive_ce_flutter`, no data
  migration needed for plain boxes like ours (`offline_queue`, `ip_state` store JSON strings).
  **drift** (SQLite) is the upgrade path if the queue grows into queryable local history — not
  needed today.
- Queue durability is decent post-fix (12 h retention, 4xx discard). Gaps: no exponential backoff on
  replay, no dedupe key (a checkin queued twice replays twice — server idempotency saves us today),
  and home-screen caching is ad-hoc SharedPreferences JSON. A repository layer (§1.1) should own a
  single read-through cache (hive_ce box) with stale-while-revalidate semantics for
  home/attendance/shifts data.

## 3. Push notifications (verified: currently dead code)

- `firebase_messaging: ^14.9.1` is in pubspec but **completely unwired**: zero references in `lib/`,
  no `google-services.json`, no gradle plugin application. It ships dead weight in the APK today.
- Wiring it enables the single most valuable reliability feature from the attendance research: the
  **FCM high-priority presence challenge** — before auto-checkout, the server pings the device
  through the one channel designed to punch through Doze; the device wakes, checks WiFi, replies;
  only an unanswered challenge proceeds to checkout.
- Requirements: Firebase project + `google-services.json` (needs the project owner), token
  registration endpoint on the API (`PUT /users/me/device-token`), background message handler that
  runs the same office-network check the foreground task uses, Android 13+ `POST_NOTIFICATIONS`
  runtime flow (permission_handler already present).
- Notification deep links: `FirebaseMessaging.onMessageOpenedApp` → `router.go(payload.route)`;
  go_router handles this cleanly once the router is exposed via a navigator key or a global.

## 4. Employee-app UX benchmarks (summarized from ATTENDANCE_RESEARCH.md §1)

Leading employee apps (Deputy, Connecteam, Jibble, When I Work) converge on: a deliberate punch
action with passive verification (vs our purely passive model), an always-visible offline/connectivity
indicator, one-tap "Running late" notice (we have the modal — surface it as a quick action),
shift views with acknowledgment, and a **tracking-reliability/permissions screen** that walks users
through OEM battery settings (dontkillmyapp patterns). Dark-mode-only glass UI is distinctive but an
accessibility audit (contrast on `--on-glass-dim`) is pending. *(Specific competitor screens not
re-verified beyond the attendance research.)*

## 5. Platform upgrades (versions verified in ATTENDANCE_RESEARCH.md §6)

| Package | Current → Latest | Risk notes |
|---|---|---|
| go_router | 13.x → **17.3** | Multiple majors: redirect signatures, `GoRouterState` changes, ShellRoute API. Budget a focused `router.dart` pass; our router is small (1 shell + ~18 routes). |
| network_info_plus | 6.x → **8.1** | Forces Dart ≥3.10 / Flutter ≥3.38 — this is the SDK-upgrade train; do it as one batch with go_router + permission_handler 12. |
| connectivity_plus | 6.x → **7.1** | Already handles `List<ConnectivityResult>` — low risk. |
| flutter_foreground_task | 9.x current | Config was the issue (service type — fixed), not version. |
| hive → hive_ce | 2.2.3 → 2.19.x | §2. |
| firebase_messaging | 14.x → current | Bump when wiring (§3). |

Material 3: `theme.dart` builds a single custom dark `ThemeData`; M3 token adoption is cosmetic
debt, not urgent. **iOS**: continuous WiFi presence as built is effectively impossible on iOS
(no persistent foreground services, SSID reads heavily restricted); an iOS port needs the
geofence + deliberate-punch model from the attendance research — treat iOS as a product decision,
not a port.

## 6. Quality, testing, CI (verified)

- **No CI exists in any of the three repos.** Minimum: GitHub Actions running
  `flutter analyze` + `flutter test` on PR (with the SDK pinned), matching jobs for api
  (`tsc + jest`) and web (`eslint + next build + vitest`).
- Tests: only the unit tests added recently (role helpers, capabilities, color parsing). Priority
  additions once repositories exist (§1): failure-mapping unit tests, offline-queue replay tests
  (fake clock), widget tests for login/2FA flows, golden tests for the design-system widgets in
  `widgets/common.dart`.
- `flutter analyze` cannot run in the current dev container (no Flutter SDK) — CI is the forcing
  function to keep the tree analyzable.

## 7. Security (established knowledge — not re-verified live)

- flutter_secure_storage for JWTs is correct; ensure `encryptedSharedPreferences: true` on Android.
- Certificate pinning via dio (`badCertificateCallback` or `http_certificate_pinning`) is worth it
  for an attendance app (MITM-forged check-ins); requires a pin-rotation plan.
- Root/jailbreak detection (e.g. `flutter_jailbreak_detection`) raises the bar against mock-location
  and traffic-forging fraud — pair with server anomaly flags rather than hard-blocking.
- Release hardening: `--obfuscate --split-debug-info` in the build, and keep the API base URL a
  `--dart-define` (already done).

---

## Ranked implementation roadmap (impact × effort)

### Tier 1 — days
1. **hive → hive_ce** swap (imports + pubspec; verify with `flutter test` in CI). Unmaintained
   storage under the offline queue is the biggest latent risk.
2. **Sealed failure mapping** for Dio in one place; kill the string-matching in login/2FA screens.
3. **Reliability-check screen** using existing deps (battery-optimization status + request,
   notification & location permission states, service-running check, last-heartbeat timestamp).
4. **CI workflow** (analyze + test) — prerequisite for everything else.

### Tier 2 — 2–6 weeks
5. **FCM wiring** (needs Firebase project from owner) → device-token endpoint → presence-challenge
   handler. Completes the doze story server+client.
6. **Repository + typed models** for the home/attendance/leave domains; move SharedPreferences
   caching into the repository; `Result<T, Failure>` returns.
7. **home_screen.dart decomposition** into section widgets + view-models (provider-based).
8. **Upgrade train**: Flutter 3.38 SDK + go_router 17 + network_info_plus 8 + permission_handler 12
   in one PR, behind CI.

### Tier 3 — quarter
9. Riverpod 3 for new feature state (coexisting with provider auth); migrate auth last via the
   Listenable bridge.
10. Widget/golden test suite; integration tests for check-in flows.
11. Certificate pinning + root detection + obfuscation flags.
12. Quick-action UX pass (running-late shortcut, offline banner, shift acknowledgment) per §4.

### Tier 4 — strategic
13. iOS product decision (geofence + deliberate punch model, per ATTENDANCE_RESEARCH.md).
14. drift migration if local history/reporting features arrive.
