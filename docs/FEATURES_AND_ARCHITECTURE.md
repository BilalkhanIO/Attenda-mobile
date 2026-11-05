# Mobile feature and architecture guide

Attenda Mobile targets iOS and Android and is employee-first. Platform capabilities differ: persistent Wi-Fi attendance background work and cryptographic attendance-device enrollment are currently Android-only; some manager and organization administration workflows are web-only or available only to users with the corresponding mobile capability. For product-wide behavior and API references, see the workspace [system feature guide](../../SYSTEM_FEATURE_GUIDE.md), [backend guide](../../attenda-api/BACKEND_API_AND_LOGIC.md), and [roadmap checklist](../../NON_PAYMENT_ROADMAP_CHECKLIST.md).

Home fetches `GET /api/v1/dashboard/summary` as an additive, permission-scoped source. The API may include a team snapshot only when the caller has team attendance access; the Home screen does not infer manager access from a role name. Personal attendance and shift controls continue to use their feature APIs because those carry the live break/clock and attendance-device state.

## Project structure

```text
lib/main.dart                 App initialization and providers
lib/router.dart               GoRouter routes, auth redirects, feature guards
lib/shell.dart                Capability-aware bottom navigation
lib/services/api_service.dart Dio client, endpoint methods, auth refresh
lib/services/auth_provider.dart Signed-in user and capability state
lib/services/                 Attendance, Wi-Fi, device proof, idempotency, theme
lib/models/capabilities.dart  Effective permission/feature capability model
lib/screens/<feature>/        Route-level screens and feature flows
lib/widgets/common.dart       Reusable app controls, cards, badges, avatars
lib/utils/theme.dart          Shared colors, typography, status colors, motion
```

Authentication uses Provider (`AuthProvider`); GoRouter listens to it for redirect updates. Other app state may use the existing Riverpod dependency where established, but do not introduce a second competing source for authentication. `ApiService` is the shared Dio client; do not create per-screen clients.

## Navigation and screen inventory

The app shell shows Home, Attendance, Leave (when the plan feature is enabled), Schedule (when enabled), Time (when enabled and permitted), and Profile. Secondary flows are pushed as nested or full-screen routes.

| Area | Main routes/screens | Purpose |
| --- | --- | --- |
| Authentication | `/login`, `/2fa` | Sign in and complete a TOTP challenge. |
| Home | `/home`, `/home/remote`, `/home/remote/detail`, `/home/notifications`, `/home/ai` | Current attendance state, check-in/out and breaks, shift preview, remote actions, notifications, AI assistant. |
| My requests | `/requests` | Cross-feature request status hub for leave, remote work, overtime, shift swaps, availability, attendance corrections, and expenses. Sections are gated by plan features and link to the source workflow. |
| Attendance | `/attendance`, `/attendance/qr` | Attendance history and details; QR scanning for supported check-in/checkpoint flows. |
| Leave | `/leave`, `/leave/request` | Balances, request history, request/cancellation flows. |
| Schedule | `/schedule`, `/schedule/manage`, `/schedule/history`, `/schedule/open-shifts`, `/schedule/availability`, `/schedule/rounds`, `/schedule/checkpoint-scan` | Personal schedule plus capability-gated planning and field operations. |

Published personal shifts can be confirmed or flagged from the Schedule screen. Conflict/help responses require a short explanation and are sent to in-scope shift managers; each response is persisted and appears in schedule history. The server supplies the 24-hour deadline and rejects responses for unpublished or past shifts. This action uses `POST /api/v1/shifts/assignments/me/:id/acknowledgement` through `ApiService.acknowledgeMyShift`; do not implement a mobile-only status. Outstanding response management remains a manager-side follow-up.
| Projects | `/projects`, `/projects/:id`, `/projects/:id/tasks/:taskId` | Search/filter projects by status; search/filter tasks by status, priority, owner, and due date; manage project members and custom task statuses; view task details, subtasks, dependencies, files, and discussion; mention a selected project member for an in-app notification. Mutations are permission checked by the API. |
| Project time | `/project-time` | Timer, entries, timesheet, and project time workflows when enabled. |
| Approvals | `/profile/approvals` | Review eligible correction, leave, expense, overtime, and remote-work requests when permitted; select up to 20 pending items from one category for confirmed bulk decisions. Each decision uses its existing endpoint and idempotency key; partial failures identify the affected request and reason. Late-arrival summaries are informational and excluded from selection. |
| Profile and employee resources | `/profile`, `/profile/payslips`, `/profile/expenses`, `/profile/documents`, `/profile/announcements`, `/profile/onboarding`, `/profile/performance`, `/profile/kudos` | Self-service account and employee records. |
| Settings | `/profile/settings` and nested settings routes | Personal appearance, notification, security, device, and reliability preferences. |

The team schedule planner filters assignments by location only for users with `org.locations.view` or `org.locations.manage`. The filter calls the same tenant-checked `/shifts/assignments` contract as web and supports assignments without a location. Employee, department, and location filters are intersected with the caller's server-side schedule visibility scope.

The complete route definition and guards are in `lib/router.dart`. Route visibility and action availability should use server-loaded capabilities from `AuthProvider`, not fixed role-name comparisons. Existing fallback behavior and any role-only checks should be reviewed against the dynamic RBAC model when touching that flow.

The request hub uses the existing self-service APIs (`/leave/requests/me`, `/attendance/remote/sessions/me`, `/overtime/requests/me`, `/shifts/swaps/me`, `/shifts/planning/availability/me`, `/attendance/corrections/me`, and `/expenses/me`). Each section loads independently so an unavailable feature does not hide other request history. The hub shows recent items and status; full history and request actions stay in each source screen.

## Data and interaction conventions

- Use `api` from `ApiService`; it unwraps the backend success envelope before returning values to screens.
- Keep HTTP and serialization in the service layer. Screens should not build raw Dio requests.
- Model visible loading, empty, retry, validation, permission, and success states explicitly. Use confirmation dialogs for cancellation, destructive actions, or actions that require user confirmation.
- Use shared widgets from `lib/widgets/common.dart` (`AppButton`, `AppCard`, `StatusBadge`, `UserAvatar`, and related components) instead of introducing lookalike controls.
- Use `AppColors`, `AppTheme`, and `StatusColors` from `lib/utils/theme.dart`; do not hardcode a second status palette in a screen.
- Respect safe areas, keyboard insets, large text, touch target sizes, and narrow device widths. Use bottom sheets for short contextual forms and dedicated screens for longer/multi-step workflows.
- Keep status labels consistent with the API and web client. A status must be understandable without its color, and color should use the shared semantic mapping.

## Attendance background operation

`WifiAttendanceService` and the Android foreground task are initialized from `main.dart`. The service observes network changes, checks attendance policy through the API, sends heartbeats while configured, and queues supported events for later replay. The app must not infer a server-side checkout solely from a local UI timer. Server timestamps, server policy, idempotency, and sync outcomes are authoritative. See `lib/services/wifi_service.dart`, `foreground_service.dart`, `attendance_clock.dart`, and the attendance sections of the backend guide before changing this flow.

Offline attendance actions use the mobile outbox and idempotency key store. Do not reuse an operation key for a different action or silently discard an unresolved queued event. The user interface should communicate pending sync, review parking, and permanent rejection when that information is available from the service.

## Shared visual format

- The app currently uses a light, solid-surface Material interface styled by `AppTheme`; `AppColors` and the selected theme palette provide its color source. These tokens are separate from the web CSS variables; shared cross-platform tokens remain a roadmap item.
- `StatusColors` is the common mapping for attendance and request status labels/colors/icons.
- Shared spacing, radius, and motion constants are defined alongside the theme tokens. Prefer them to arbitrary per-screen values.
- Use the shared DM Sans typography configuration. Avoid tiny labels, cramped forms, and repeated cards that show the same metric.
- Use native platform affordances for camera/location permission prompts, while explaining why the permission is needed before requesting it.
- Use animations for feedback and transitions only; honor reduced-motion/device performance expectations and keep controls responsive while animation runs.

## Capability and API flow

```text
GoRouter guard / shell tab filter
  → AuthProvider capability helpers
  → ApiService method with authenticated Dio client
  → backend route permission + organization + feature checks
  → typed/parsed result returned to screen
```

The client may hide unavailable routes or controls for clarity, but the backend must enforce authorization. A 401 triggers a single-flight refresh/retry; if refresh fails, stored credentials are cleared and the router returns to sign-in. Supported writes use the idempotency interceptor and encrypted persistent key store; offline attendance retains its event-specific key lifecycle.

## Adding or changing a mobile feature

1. Find the backend route and schema first; match paths, verbs, field names, status values, and error behavior.
2. Add or update service methods in `ApiService`; parse the `{success, data}` envelope in one place.
3. Add screen-specific state and reusable widgets; keep authentication and capabilities in their existing providers.
4. Register the route and its authentication, plan-feature, and permission behavior in `router.dart` and `shell.dart` as appropriate.
5. Reuse theme/status tokens and shared widgets; provide loading, empty, validation, error, success, and offline states.
6. Update this guide, the system feature guide, backend docs, and roadmap status. Add/adjust tests for behavior that changes.
