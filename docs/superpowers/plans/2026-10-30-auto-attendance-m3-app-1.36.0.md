# Auto check-in / check-out M3 — app 1.36.0 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When HR has switched an employee on, the phone watches the office area in the background and reports
arrive / leave events to the tenant (connector 2.66.0, live), which checks the employee in and out automatically.

**Architecture:** The phone only reports events; the server decides and waits (spec §4). A single region per signed-in
employee is registered with `native_geofence`; its headless callback takes one location fix + Wi-Fi, queues the event
and posts the queue in `event_at` order with a device-bound **auto key**. A foreground `AutoAttendanceService`
(ChangeNotifier) keeps the region, key, permission status and queue in step with the `auto_attendance` block that
`/login` and `/me` return. Screens: setup + disclosure flow, Profile row, My day line / banner, "Automatic" labels.

**Tech Stack:** Flutter 3.44 / Dart, `provider`, `native_geofence` 1.5.1 (pinned), `permission_handler` 12.0.3,
`geolocator` 14, `network_info_plus` 7, `shared_preferences` (`SharedPreferencesAsync` for the queue),
`flutter_secure_storage`, `firebase_messaging` (silent `auto_recheck`), `flutter_local_notifications` (drop notice).

**Spec:** connector repo `docs/superpowers/specs/2026-10-27-auto-attendance-design.md` (§7 is the app) and the frozen
API in `docs/superpowers/plans/2026-10-28-auto-attendance-m1-connector-2.66.0.md` → "API contract" + "Contract
amendments after the cross-review" (both on connector `origin/main` 8f7b936). Read both before Task 1.
Mockup boards 1–3: https://claude.ai/artifact/3uDgzsR2E3WAovg5JyPLgb

## Global Constraints

- **Version:** `pubspec.yaml` **1.35.0+111 → 1.36.0+112** (Task 12 only). App version comes from pubspec
  (`package_info_plus`), never hardcoded.
- **Server is live:** every tenant runs connector 2.66.0 and hrmsmanager 1.10.0. Nothing in the server changes.
- **Values from the spec / contract (verbatim):**
  - region id `omni_office_<db>_<employee>`; centre = `office.latitude/longitude`, radius = `office.area_m`;
    triggers enter + exit (+ dwell on Android, loitering delay = `dwell_min`).
  - background handler: "one location fix (≤ 8 s, high accuracy), SSID/BSSID, mock flag → POST the event with the
    auto key"; "an event older than 30 min is dropped with a local notification "Couldn't check you in/out — open
    Omni HR"".
  - event body `{event_uid, kind: arrive|leave, event_at, latitude, longitude, location_accuracy, is_mocked,
    wifi_ssid, wifi_bssid, device_id, app_version, source?}`; `event_uid` 1–64 chars `[\x21-\x7e]`; `event_at`
    naive UTC `YYYY-MM-DD HH:MM:SS`; `source` ∈ `geofence`, `dwell`, `foreground`, `wifi`, `recheck`.
  - status body `{permission: always|while_using|denied, enabled: bool, platform: ios|android}`, posted "on every
    change and app start".
  - auto key header `X-Omni-Auto-Key: <key>`; key route `attendance/auto/key` needs a **device-bound** bearer session.
  - **AA-F01:** "post the offline queue one event at a time, in ascending `event_at`. Post the next only after a 2xx or
    a final 4xx. On 409 / 5xx / timeout, resend the same event before any later one."
  - "The app treats every 5xx, 422, timeout and non-JSON answer like 409: keep the event and resend it later with the
    **same** `event_uid`."
  - **AA-F02:** "never runs `auth/refresh` and `attendance/auto/key` at the same time: refresh first, then fetch the key."
  - **AA-F03:** `attendance/undo` sends `action` (`check_in` / `check_out`) on every Undo; 409 `undo_not_last` = do not resend.
  - **AA-F06:** "on a background wake (geofence, silent push), when the access session expires within 7 days, call
    `auth/refresh` with the device refresh token before posting."
  - **AA-F09:** `in_mode` / `out_mode` `'auto'` → "Automatic"; Team overview / My day punch `auto` (bool) → same marker.
  - busy_retry on attendance routes → "Please try again"; HTTP timeout stays ≥ 30 s (today 30 s — keep).
  - Play prominent disclosure must contain the words "location" and "even when the app is closed or not in use".
  - `auto_attendance == null` or missing = off (older connector); the manual Check in / out button keeps working (D9).
- **Repo rules (app `CLAUDE.md`):** colours only via `context.omni` (`test/core/colour_guard_test.dart`); every
  external call behind an injectable seam, fakes by subclassing (no mocktail / mockito); never keep an `OmniMobileApi`
  across attempts; session storage writes only inside `SessionService._persisting`, never call a locked method inside
  it; tests mounting `MyDayScreen` clear `MyDayMemory` in setUp; UI strings hardcoded English; theme tests are
  `testWidgets`; all user-facing error text through `friendlyError()`.
- **Read every file before editing it; edit by quoted anchor text, never by line number.** Every subagent brief repeats this.
- **Workspace:** worktree `omnisoft-hrms-mobile/.claude/worktrees/auto-attendance-app`, branch
  `feat/auto-attendance-app` from `origin/master` 3bff862. Commits local; no push, store upload or tenant change
  without Willy's word. Commit messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- **Test commands:** `flutter test <file>` per task; gate = `flutter test` (all green) **and** `flutter analyze`
  (no new issues vs the Task 0 baseline).
- **Never** log or print the auto key, tokens or full Wi-Fi BSSIDs outside `kDebugMode`.

## Lead decisions (binding for the implementer)

- **L1 No `location` background mode on iOS.** The spike relaunched a terminated app on ENTER without it (F2);
  `UIBackgroundModes` stays `[remote-notification]`. App Store risk is lower without it.
- **L2 Keychain access while locked.** The auto key is stored with
  `IOSOptions(accessibility: KeychainAccessibility.first_unlock)` (a wake usually comes with the phone locked). The
  existing access / refresh tokens keep their current options; the background refresh (AA-F06) is best effort and
  skips silently when the keychain is not readable.
- **L3 Idempotent arming.** Re-registering a region resets iOS's state and opens the plugin's initial-state window
  (spike F3: a crossing in it is lost). `AutoFence.sync` compares the wanted region (id, centre to 6 decimals, radius)
  with `getRegisteredGeofences()` and only re-creates on a difference.
- **L4 Foreground arrive only when the phone has no inside state.** Opening the app posts `source: foreground` only if
  the last region state the app saw is not `inside` **or** the last event answer was `waiting_wifi` less than 30 min
  ago. (Otherwise a manual check-out at the desk followed by opening the app would check the employee in again.)
- **L5 Queue across isolates.** The queue lives in `SharedPreferencesAsync` (no per-isolate cache) under
  `omni_auto_queue`; `flush()` takes a 30 s lease (`omni_auto_flush_lease_until`) so the UI isolate and a background
  wake never post the same queue at once. Max 20 events; the oldest beyond that is dropped.
- **L6 Android Wi-Fi wait (v1):** no native `NetworkCallback`. Android re-checks Wi-Fi on the plugin's DWELL
  (`source: dwell`, at `dwell_min`) and on app open; iPhone on the silent `auto_recheck`. **Open question Q1.**
- **L7 Turn off on this phone** is a local opt-out (`omni_auto_opted_out` pref, per employee): disarm, delete the key,
  post status `enabled: false`. HR's switch is untouched; the setup card offers to turn it back on.
- **L8 Separate HTTP client for auto routes.** `AutoApi` reads HTTP status (409 / 5xx / 401 / 400 matter) and never
  fires `OmniMobileApi.onInvalidSession` (a background wake must not sign the user out). The key fetch uses
  `OmniMobileApi` (foreground, bearer).

## Open questions for Willy

- **Q1 (L6):** v1 Android Wi-Fi re-check = DWELL + app open. The always-on native Wi-Fi listener (Kotlin
  `NetworkCallback` + PendingIntent → headless post) is ~1–2 days more and can follow in 1.36.x. Recommend: v1 as above.
- **Q2:** Field days with the spike app should still run before the 1.36 store submission (M4 gate), not before building.

## Review Focus

1. **Locked iPhone at the wake** — the auto key must be readable (L2) and the event posted; test
   `auto_key_store_test.dart: writes with first_unlock accessibility` (Task 3).
2. **No network at the wake** — event queued, sent in `event_at` order on the next wake / app open; > 30 min dropped
   with the notice; tests in Task 4 (`flush keeps order after a 409`, `drops stale with one notice`).
3. **Sign-out (or HR switch off) with events queued** — region removed, key deleted, queue cleared, nothing posted
   after; test `AutoAttendanceService: session clearing wipes queue, key and fence` (Task 7).
4. **Manual check-out at the desk, then app opened** — no foreground arrive (L4); test `no foreground arrive when last
   state is inside` (Task 7).
5. **UI isolate and background wake flushing together** — one poster at a time (L5); test `second flush inside the
   lease posts nothing` (Task 4).

---

## File map

| File | Task | Responsibility |
|---|---|---|
| `lib/models/auto_attendance_config.dart` (new) | 1 | `auto_attendance` block |
| `lib/services/session_service.dart` | 1 | persist / clear the block |
| `lib/services/auto/auto_event.dart`, `auto_event_queue.dart` (new) | 2 | event + persisted queue |
| `lib/services/auto/auto_api.dart`, `auto_key_store.dart` (new); `lib/services/omni_mobile_api.dart` | 3 | auto routes, key storage, key fetch, status |
| `lib/services/auto/auto_sender.dart` (new) | 4 | ordered flush, drop notice, last answer |
| `lib/services/auto/auto_sampler.dart`, `auto_background.dart` (new); `lib/services/push_service.dart` | 5 | background entry points |
| `lib/services/auto/auto_fence.dart` (new) | 6 | region arm / disarm |
| `lib/services/auto/auto_attendance_service.dart` (new); `lib/main.dart` | 7 | foreground orchestration |
| Android manifest + proguard, iOS Info.plist / AppDelegate / PrivacyInfo | 8 | platform |
| `lib/screens/auto/*` (new); `lib/screens/home/my_day/*` | 9, 10 | setup flow, status screens |
| `lib/screens/profile/profile_screen.dart` | 10 | Profile row |
| models / history / overview / undo / push tap / `error_messages.dart` | 11 | labels, Undo, push kinds |
| `pubspec.yaml`, Android changelog, `CLAUDE.md`, `docs/auto-checkin-release.md` | 12 | release |

Tests mirror the paths under `test/` (e.g. `test/services/auto/auto_sender_test.dart`).

---

## Tasks

### Task 0: Baseline and dependencies

**Files:** Modify `pubspec.yaml`, `pubspec.lock`.

- [ ] **Step 1:** `flutter pub get && flutter test 2>&1 | tail -3 && flutter analyze | tail -3` on the untouched
  branch; record the pass count and analyze issue count in `.superpowers/sdd/progress.md` (create it).
- [ ] **Step 2:** add `native_geofence: 1.5.1` and `permission_handler: 12.0.3` (exact pins, as in the spike).
- [ ] **Step 3:** `flutter pub get`, `flutter test` → same count, green.
- [ ] **Step 4:** commit `chore(auto): pin native_geofence 1.5.1 + permission_handler 12.0.3`.

### Task 1: The `auto_attendance` block in the session

**Files:** Create `lib/models/auto_attendance_config.dart`; modify `lib/services/session_service.dart`
(`saveLoginResponse`, `refreshMeWith`, `_clearSessionFields`). Tests `test/models/auto_attendance_config_test.dart`,
`test/services/session_auto_attendance_test.dart`.

**Interfaces — Produces:**
- `enum AutoTrigger { locationWifi, location }` (`'location_wifi'`, `'location'`; unknown → `locationWifi`).
- `class AutoOffice { final String name; final double latitude, longitude; final int areaM; }`
- `class AutoAttendanceConfig { final AutoTrigger trigger; final int dwellMin, exitMin; final AutoOffice office;
  final bool wifiRequired; static AutoAttendanceConfig? fromJson(Object? json); Map<String, dynamic> toJson();
  String get signature; }` — `fromJson` returns null for null / non-map / missing office / non-finite coordinates /
  `area_m <= 0`. `signature` = `'${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)},$areaM'`.
- `SessionService.autoAttendance → AutoAttendanceConfig?` backed by pref `employee_auto_attendance` (JSON), written
  by `_writeAutoAttendance(Map employee)` from `saveLoginResponse` and `refreshMeWith` (inside the existing
  `_persisting`, like `_writeAttendanceKioskOnly`), removed in `_clearSessionFields`. A `/me` without the key → null.

- [ ] **Step 1: failing tests**
  - `fromJson parses the contract block` (`{trigger:'location', dwell_min:5, exit_min:10, office:{name:'NOVAWORKS HQ',
    latitude:1.2894, longitude:103.847, area_m:150}, wifi_required:false}` → fields equal).
  - `fromJson returns null for null, {}, missing office, area_m 0`.
  - `unknown trigger falls back to locationWifi`.
  - `login stores the block; me without the key clears it; clearSession removes it`.
- [ ] **Step 2:** run → FAIL. **Step 3:** implement. **Step 4:** run → PASS, plus `flutter test test/services` green.
- [ ] **Step 5:** commit `feat(auto): keep the auto_attendance block from /login and /me`.

### Task 2: Event and persisted queue

**Files:** Create `lib/services/auto/auto_event.dart`, `lib/services/auto/auto_event_queue.dart`. Tests
`test/services/auto/auto_event_test.dart`, `auto_event_queue_test.dart`.

**Interfaces — Produces:**
- `enum AutoKind { arrive, leave }`; `enum AutoSource { geofence, dwell, foreground, wifi, recheck }`.
- `class AutoEvent { final String eventUid; final AutoKind kind; final DateTime eventAt /*UTC*/; final double?
  latitude, longitude, accuracy; final bool isMocked; final String? wifiSsid, wifiBssid; final String deviceId,
  appVersion; final AutoSource source; Map<String, dynamic> toBody(); Map<String, dynamic> toJson();
  factory AutoEvent.fromJson(Map); static String newUid(); }`
  - `toBody()` = the contract body; `event_at` formatted `YYYY-MM-DD HH:MM:SS` in UTC; `source` omitted when
    `geofence`; null coordinates sent as JSON null.
  - `newUid()` = `'a-'` + 24 lowercase hex chars from `Random.secure()` (fits `[\x21-\x7e]{1,64}`).
- `class AutoEventQueue { AutoEventQueue({SharedPreferencesAsync? prefs}); Future<void> add(AutoEvent e);
  Future<List<AutoEvent>> ordered(); Future<void> remove(String eventUid); Future<List<AutoEvent>>
  takeStale(DateTime now); Future<void> clear(); static const maxEvents = 20; static const staleAfter =
  Duration(minutes: 30); }` — key `omni_auto_queue` (JSON list). `add` ignores a repeated `eventUid`, drops the
  oldest when over 20. `takeStale` removes and returns events with `eventAt < now - 30 min`.

- [ ] **Step 1: failing tests** — `toBody formats event_at as naive UTC` (local 2026-10-30 08:47:05 +08:00 →
  `'2026-10-30 00:47:05'`); `toBody omits source for geofence, sends 'dwell'`; `newUid matches ^a-[0-9a-f]{24}$`;
  `ordered sorts by eventAt`; `add ignores a repeated uid`; `21st event drops the oldest`; `takeStale returns and
  removes events older than 30 min` (use `SharedPreferencesAsyncPlatform` in-memory fake, see shared_preferences
  testing docs).
- [ ] **Step 2–4:** FAIL → implement → PASS.
- [ ] **Step 5:** commit `feat(auto): auto event + persisted queue`.

### Task 3: Auto routes client, key store, key fetch, status

**Files:** Create `lib/services/auto/auto_api.dart`, `lib/services/auto/auto_key_store.dart`; modify
`lib/services/omni_mobile_api.dart` (add `fetchAutoKey`, `postAutoStatus`). Tests `test/services/auto/auto_api_test.dart`,
`auto_key_store_test.dart`, `test/services/omni_mobile_api_auto_test.dart`.

**Interfaces — Produces:**
- `sealed class AutoPostResult` with `AutoAccepted(String state, {String? reason, DateTime? confirmAfter})`,
  `AutoFinal(String error)` (400 `invalid_event` / `invalid_request`, 404 `no_employee_linked`, any other 4xx except
  409/422/401), `AutoRetry(String why)` (409, 422, 5xx, timeout, network error, non-JSON), `AutoKeyInvalid()` (401
  `invalid_key` / `invalid_session` / `invalid_token`).
- `class AutoApi { AutoApi({required String baseUrl, required String db, String? autoKey, String? bearer,
  http.Client? client}); Future<AutoPostResult> postEvent(AutoEvent e); Future<AutoPostResult> postStatus({required
  String permission, required bool enabled, required String platform}); }` — URL
  `'$baseUrl/api/v1/omni_mobile/attendance/auto/event?db=$db'`; header `X-Omni-Auto-Key` when `autoKey` set, else
  `Authorization: Bearer`; timeout 30 s; `200 + success:true` → `AutoAccepted`; `200 + success:false +
  error:'feature_unavailable'` → `AutoFinal('feature_unavailable')`.
- `class AutoKeyStore { AutoKeyStore({FlutterSecureStorage? storage}); Future<String?> read(); Future<void>
  write(String key, String deviceId); Future<String?> deviceId(); Future<void> delete(); }` — keys `omni_auto_key`,
  `omni_auto_key_device`; every call passes `IOSOptions(accessibility: KeychainAccessibility.first_unlock)` (L2).
- `OmniMobileApi.fetchAutoKey() → Future<({String key, String deviceId})>` (POST `/attendance/auto/key` `{}`; errors
  as every route: `ApiException('device_required' | 'not_enabled' | 'feature_unavailable' | 'busy_retry' | …)`).

- [ ] **Step 1: failing tests** (use `MockClient` from `package:http/testing.dart`):
  - `202/200 success → AutoAccepted with state, reason, confirmAfter parsed as UTC`.
  - `409 busy_retry, 500 server_error, 422 html, timeout, non-JSON → AutoRetry`.
  - `400 invalid_event → AutoFinal('invalid_event')`; `401 invalid_key → AutoKeyInvalid`.
  - `sends X-Omni-Auto-Key and no Authorization when a key is set`.
  - `auto_key_store writes with first_unlock accessibility` (fake `FlutterSecureStorage` subclass recording `iOptions`).
  - `fetchAutoKey returns key + device_id; 403 not_enabled throws ApiException('not_enabled')`.
- [ ] **Step 2–4:** FAIL → implement → PASS.
- [ ] **Step 5:** commit `feat(auto): auto routes client, key store and key fetch`.

### Task 4: Ordered flush, drop notice, last answer

**Files:** Create `lib/services/auto/auto_sender.dart`. Test `test/services/auto/auto_sender_test.dart`.

**Interfaces:**
- Consumes: `AutoEventQueue`, `AutoApi`, `AutoKeyStore` (Tasks 2–3).
- Produces: `class AutoSender { AutoSender({required AutoEventQueue queue, required AutoApi Function() api,
  required Future<void> Function(int dropped) notifyDropped, SharedPreferencesAsync? prefs, DateTime Function()?
  now}); Future<FlushOutcome> flush(); }`; `enum FlushOutcome { done, retryLater, keyInvalid, busy }`;
  `class AutoLastAnswer { String state; String? reason; DateTime at; }` stored under `omni_auto_last_answer`,
  read by `static Future<AutoLastAnswer?> lastAnswer(SharedPreferencesAsync prefs)`.
- Algorithm (AA-F01): take the lease (`omni_auto_flush_lease_until` = now + 30 s; if a lease is live → `busy`);
  `takeStale(now)` → if any, `notifyDropped(n)` once; then for each `ordered()` event: `AutoAccepted` or `AutoFinal`
  → `remove` (+ store last answer for `AutoAccepted`) and continue; `AutoRetry` → stop, `retryLater`;
  `AutoKeyInvalid` → stop, `keyInvalid` (the event stays queued). Release the lease in `finally`.
- Drop notice text: title "Couldn't check you in/out", body "Open Omni HR" — built by
  `showAutoDroppedNotice()` in this file (flutter_local_notifications `show()` on the `attendance` channel id; iOS
  default presentation).

- [ ] **Step 1: failing tests:** `posts in event_at order`; `flush keeps order after a 409` (first event retried, second
  not posted); `final 4xx removes the event and continues`; `drops stale with one notice` (3 stale → one call with 3);
  `key invalid keeps the event and stops`; `second flush inside the lease posts nothing`; `stores the last answer`.
- [ ] **Step 2–4:** FAIL → implement → PASS.
- [ ] **Step 5:** commit `feat(auto): send queued events in order (AA-F01)`.

### Task 5: Background entry points

**Files:** Create `lib/services/auto/auto_sampler.dart`, `lib/services/auto/auto_background.dart`; modify
`lib/services/push_service.dart` (`handleBackgroundData`). Tests `test/services/auto/auto_background_test.dart`.

**Interfaces:**
- Produces:
  - `class AutoSample { double? latitude, longitude, accuracy; bool isMocked; String? ssid, bssid; }`;
    `Future<AutoSample> sampleNow({Future<Position> Function()? fix, Future<WifiInfoResult> Function()? wifi})` —
    fix ≤ 8 s high accuracy (`Geolocator.getCurrentPosition`, no permission request in background), Wi-Fi bounded
    3 s concurrently, never throws (failures → nulls).
  - `class AutoBackgroundContext { String baseUrl, db, deviceId, appVersion; int employeeId; String? autoKey;
    AutoAttendanceConfig? config; static Future<AutoBackgroundContext?> load(); }` — reads prefs `client_url`,
    `client_db`, the employee id pref `SessionService` already writes (read its key from `session_service.dart`;
    don't add a second one), `employee_auto_attendance`, `omni_hr_device_id`, `omni_auto_opted_out_<employee>`
    after `reload()`, key via `AutoKeyStore`; null when signed out, config null, or opted out.
  - `Future<void> handleAutoWake({required AutoKind kind, required AutoSource source, AutoBackgroundContext? ctx,
    …seams})` — load context (null → return); record region state `omni_auto_last_state` (`inside` on arrive from
    geofence/dwell, `outside` on leave); sample; build `AutoEvent`; `queue.add`; best-effort refresh (AA-F06, below);
    `AutoSender.flush()`. Whole wake bounded by 25 s.
  - `@pragma('vm:entry-point') Future<void> autoGeofenceTriggered(GeofenceCallbackParams p)` — `enter` → arrive /
    geofence, `exit` → leave / geofence, `dwell` → arrive / dwell. Ignores regions whose id ≠ the current
    `omni_office_<db>_<employee>`.
  - `Future<void> handleAutoRecheck(Map<String, dynamic> data)` → `handleAutoWake(arrive, recheck)` only when
    `omni_auto_last_state == inside`.
  - AA-F06 best effort: `Future<void> refreshIfExpiringSoon({Duration within = const Duration(days: 7)})` — when pref
    `expires_at` is within 7 days, take the lease `omni_auto_refresh_lease_until` (60 s), read the refresh token
    (skip silently on any keychain error), POST `auth/refresh` through `SessionService.refreshAccessToken`
    semantics but **without** firing `onInvalidSession`; on success write tokens through a `SessionService`
    instance loaded in this isolate; never call `fetchAutoKey` in the same wake (AA-F02).
- Modify `handleBackgroundData`: `kind == 'auto_recheck'` → `await handleAutoRecheck(data)` (before the existing
  `action == 'remove'` path; nothing shown).

- [ ] **Step 1: failing tests** (seams for sampler, queue, api, clock): `enter posts an arrive with the sample and
  device id`; `exit records outside and posts a leave`; `dwell sends source dwell`; `signed out or opted out → nothing
  queued`; `foreign region id is ignored`; `recheck only when last state is inside`; `sampler failure still queues the
  event with null coordinates`; `refresh skipped when expiry is 8 days away`.
- [ ] **Step 2–4:** FAIL → implement → PASS.
- [ ] **Step 5:** commit `feat(auto): background wake — sample, queue, send`.

### Task 6: The region

**Files:** Create `lib/services/auto/auto_fence.dart`. Test `test/services/auto/auto_fence_test.dart`.

**Interfaces — Produces:**
- `abstract class GeofencePort { Future<List<ActiveGeofence>> registered(); Future<void> create(Geofence g);
  Future<void> removeById(String id); }` with `NativeGeofencePort` (wraps `NativeGeofenceManager.instance`, calls
  `initialize()` once, registers `autoGeofenceTriggered`).
- `class AutoFence { AutoFence({GeofencePort? port}); static String regionId(String db, int employeeId);
  Future<bool> sync({required String db, required int employeeId, required AutoAttendanceConfig? config, required
  bool alwaysGranted}); Future<void> removeAll(String db); }` — `sync` returns true when a region is armed. Wanted =
  config != null && alwaysGranted. Removes any `omni_office_<db>_*` region that is not the wanted one. L3: re-create
  only when id / centre (6 dp) / radius differ. Settings: iOS `IosGeofenceSettings(initialTrigger: false)`; Android
  `AndroidGeofenceSettings(initialTriggers: {}, expiration: Duration(days: 365), loiteringDelay:
  Duration(minutes: config.dwellMin), notificationResponsiveness: Duration(minutes: 1))`; triggers enter + exit, plus
  dwell on Android only.

- [ ] **Step 1: failing tests:** `arms once and is a no-op on the second sync`; `re-creates when area_m changes`;
  `removes the region when config becomes null`; `removes a stale region of another employee in the same db`; `no
  region without Always`; `android adds dwell with loitering = dwell_min`.
- [ ] **Step 2–4:** FAIL → implement → PASS.
- [ ] **Step 5:** commit `feat(auto): arm and disarm the office region`.

### Task 7: Foreground orchestration

**Files:** Create `lib/services/auto/auto_attendance_service.dart`; modify `lib/main.dart` (provider, hooks). Test
`test/services/auto/auto_attendance_service_test.dart`.

**Interfaces:**
- Consumes: Tasks 1–6; `SessionService` (`autoAttendance`, `refreshAccessToken`, `onSessionClearing`),
  `OmniMobileApi.fetchAutoKey`.
- Produces: `enum AutoPhoneState { off, needsSetup, needsAlways, on, waitingWifi, optedOut }`;
  `class AutoAttendanceService extends ChangeNotifier { AutoPhoneState get state; AutoAttendanceConfig? get config;
  Future<void> sync({bool appStart = false}); Future<void> turnOffOnThisPhone(); Future<void> turnOnAgain();
  Future<void> onSessionClearing(); void onAutoUndone(); }` with seams `permission` (`Future<String>
  Function()` → `always|while_using|denied`), `fence`, `keyStore`, `apiBuilder`, `autoApiBuilder`, `sender`,
  `sampler`, `platform`.
- `sync()` order (runs on app start, resume and after every `/me` / login; serialized — a call while one runs sets a
  rerun flag): read config → state; if `off`/`optedOut` → `fence.removeAll`, `keyStore.delete`, post status
  `enabled:false` once per change, return; refresh the session when it expires within 7 days, **then** fetch the key
  if missing (AA-F02; `ApiException('not_enabled')` → treat as off; `device_required` → state `needsSetup` with a
  log line); `fence.sync`; post status `{permission, enabled: state == on || waitingWifi, platform}` when it differs
  from pref `omni_auto_status_sent`, or on `appStart`; foreground check (L4: inside the area by one `sampleNow` fix,
  `distance <= area_m + min(accuracy, 100)` and no `inside` state, or last answer `waiting_wifi` < 30 min) → queue an
  arrive with `source: foreground`; `sender.flush()`; `AutoKeyInvalid` from the flush → delete key, fetch once more.
  `state = waitingWifi` while the last answer is `waiting_wifi` and < 30 min old.
- `onSessionClearing()` = `fence.removeAll(db)`, `keyStore.delete()`, `queue.clear()`, clear `omni_auto_*` prefs.
- `onAutoUndone()` sets `omni_auto_last_state` to `unknown`.
- `main.dart`: create the service, add to `MultiProvider`, make `session.onSessionClearing` a composite of
  `push.onSessionCleared` and `auto.onSessionClearing`; call `auto.sync(appStart: true)` after the first `/me`
  refresh and `auto.sync()` on every resume / login.

- [ ] **Step 1: failing tests:** `config null → removes fence, deletes key, posts enabled false`; `refresh runs before
  the key fetch` (call log order); `not_enabled on key fetch → state off`; `while_using → needsAlways, no region`;
  `session clearing wipes queue, key and fence`; `no foreground arrive when last state is inside`; `foreground arrive
  when inside and state unknown`; `status posted on app start and on change only`; `concurrent sync runs twice, not
  in parallel`.
- [ ] **Step 2–4:** FAIL → implement → PASS; `flutter test` all green.
- [ ] **Step 5:** commit `feat(auto): keep region, key, status and queue in step with HR's switch`.

### Task 8: Platform configuration and release builds

**Files:** `android/app/src/main/AndroidManifest.xml`, `android/app/proguard-rules.pro`, `ios/Runner/Info.plist`,
`ios/Runner/AppDelegate.swift`, `ios/Runner/PrivacyInfo.xcprivacy`.

- [ ] **Step 1 Android:** add `ACCESS_BACKGROUND_LOCATION`, `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_LOCATION`,
  `RECEIVE_BOOT_COMPLETED`, `WAKE_LOCK`; the plugin's receivers / service exactly as in the spike manifest
  (`NativeGeofenceBroadcastReceiver`, `NativeGeofenceRebootBroadcastReceiver` with `BOOT_COMPLETED`,
  `NativeGeofenceForegroundService` `foregroundServiceType="location"`). Proguard (R8 stays on): keep
  `androidx.work.impl.WorkDatabase_Impl`, `androidx.work.**` workers and `com.chunkytofustudios.native_geofence.**`
  (the spike crashed at start with R8 on — WorkDatabase_Impl constructor stripped).
- [ ] **Step 2 iOS:** `AppDelegate.didFinishLaunchingWithOptions` calls
  `NativeGeofencePlugin.setPluginRegistrantCallback { GeneratedPluginRegistrant.register(with: $0) }` (must not move
  into the implicit-engine callback: a wake has no scene). Purpose strings:
  - `NSLocationWhenInUseUsageDescription`: "Omni HR uses your location to check you in and out at your office."
  - `NSLocationAlwaysAndWhenInUseUsageDescription`: "If your HR turned on automatic check-in, Omni HR uses your
    location in the background, even when the app is closed, only to notice when you arrive at or leave your office."
  - `PrivacyInfo.xcprivacy`: declare precise location, linked to the user, purpose App Functionality, no tracking.
  - No `location` in `UIBackgroundModes` (L1).
- [ ] **Step 3:** `flutter build apk --release` and `flutter build ios --release --no-codesign` both succeed; install
  the release APK on the Samsung (R8YY921VY1A) and confirm it starts (the R8 crash would show at start).
- [ ] **Step 4:** commit `build(auto): background location config for Android and iOS`.

### Task 9: Setup flow (My day card → explainer → permission → result)

**Files:** Create `lib/screens/auto/auto_setup_card.dart`, `lib/screens/auto/auto_setup_screen.dart`; modify
`lib/screens/home/my_day/my_day_screen.dart`. Tests `test/screens/auto/auto_setup_test.dart`.

**Interfaces:** Consumes `AutoAttendanceService` (state, `sync`, `turnOnAgain`), seam `requestPermission` (
`Future<String> Function(String step)` with steps `while_using`, `always`, `settings`).

- Card on My day (state `needsSetup` / `needsAlways` / `optedOut`), key `ValueKey('auto-setup-card')`: title "Automatic
  check-in", body "Your HR turned it on. Set it up once and Omni HR checks you in and out at <office.name>.", button
  "Set up".
- Explainer = the Play prominent disclosure (shown before any system prompt), key `auto-disclosure`: "Omni HR collects
  your location to check you in when you arrive at <office.name> and out when you leave, **even when the app is closed
  or not in use**. Only your office area is watched. Every automatic check-in shows you a notice with Undo." Buttons
  "Continue" / "Not now".
- Permission steps: iOS — while-in-use request, then Always request (provisional; copy: "When iPhone asks later,
  choose Change to Always Allow"). Android — while-in-use, then a screen "Choose Allow all the time" with "Open
  settings" (`openAppSettings()`); on return re-check.
- Result: `on` → "You're set. Omni HR checks you in at <office.name>."; else "Automatic check-in is paused" + "Try
  again".

- [ ] **Step 1: failing widget tests:** `card shows for needsSetup and hides for on/off`; `disclosure text contains
  'location' and 'even when the app is closed or not in use'`; `Not now leaves the state unchanged`; `android path
  shows Allow all the time step after while_using`; `result shows paused when always is denied`; dark theme renders
  (`testWidgets`, colour guard passes).
- [ ] **Step 2–4:** FAIL → implement → PASS.
- [ ] **Step 5:** commit `feat(auto): setup flow with the location disclosure`.

### Task 10: Profile row, status screen, My day line and paused banner

**Files:** Create `lib/screens/auto/auto_checkin_screen.dart`; modify `lib/screens/profile/profile_screen.dart`
(new card after `_notificationsCard`, same template, key `profile-auto-checkin`), `lib/screens/home/my_day/my_day_screen.dart`
(line under `StatusTile`, banner). Tests `test/screens/auto/auto_checkin_screen_test.dart`,
`test/screens/home/my_day/auto_line_test.dart`.

- Profile row only when `config != null`; subtitle per state: on "On · <office.name>", waitingWifi "Waiting for
  office Wi-Fi", needsAlways "Paused — location permission", optedOut "Off on this phone", needsSetup "Not set up".
- Status screen: office name + area, trigger ("Location + Wi-Fi" / "Location"), permission, last automatic punch time
  (from My day if known), buttons "Fix permission" (needsAlways), "Turn off on this phone" (confirm dialog) /
  "Turn on again".
- My day line under the status tile (`ValueKey('auto-line')`): "Auto check-in on · <office.name>" / "Waiting for
  office Wi-Fi" / "Paused". Paused banner (`auto-paused-banner`) when state `needsAlways`, button "Fix".

- [ ] **Step 1: failing widget tests:** `row hidden without config`; `subtitle per state` (5 cases); `turn off asks
  first and calls turnOffOnThisPhone`; `my day shows the line for on and the banner for needsAlways`; dark theme.
- [ ] **Step 2–4:** FAIL → implement → PASS.
- [ ] **Step 5:** commit `feat(auto): Profile row, status screen, My day line`.

### Task 11: "Automatic" labels, Undo with action, push kinds, wording

**Files:** `lib/models/my_day.dart` (`MyDayPunch.auto`, `MyDay.autoUndo`), `lib/screens/home/my_day/my_day_screen.dart`
(Undo for `auto_undo`), `lib/models/attendance_record.dart` (`modeLabel`), `lib/models/team_overview.dart` +
`lib/screens/home/overview/person_sheet.dart`, `lib/services/omni_mobile_api.dart` (`undoPunch`),
`lib/services/attendance_action_controller.dart` / `my_day_screen.dart` callers, `lib/screens/notifications/notification_tap.dart`
+ `lib/services/push_service.dart` (kinds), `lib/core/error_messages.dart`. Tests next to each.

- `MyDayPunch.auto` (bool, default false) → `placeLabel` "Automatic" when true (before the source rule).
- `MyDay.autoUndo` = `{attendanceId, action, undoUntil}` from `today.auto_undo`; My day shows the existing Undo
  snackbar for it once per `attendanceId` while `now < undoUntil`; Undo calls `undoPunch(id, action:)` then
  `auto.onAutoUndone()`.
- `undoPunch(int attendanceId, {required String action})` sends `{'attendance_id', 'action'}` (AA-F03); every caller
  passes the action of the punch it shows; `ApiException('undo_not_last')` → "That punch was already undone." via
  `friendlyError`, no resend.
- `AttendanceRecord.modeLabel`: `inMode == 'auto' || outMode == 'auto'` → "Automatic" (both legs auto → "Automatic";
  mixed → the existing in-mode label + " · Automatic out" when only `outMode` is auto). `_modeColor('auto')` = the
  existing mobile colour.
- `OverviewPunch.auto` parsed; `punchSourceLabel` gets `{bool auto = false}` → "Automatic".
- Push kinds `auto_checked_in` / `auto_checked_out`: tap → `openHome()` (My day), like reminder kinds; foreground
  arrival → `pushArrivalSnackBar` with "Open". `auto_recheck` is never shown (Task 5).
- `friendlyError`: add `ErrorContext.attendance`; `busy_retry` in that context → "Please try again."; punch and Undo
  callers pass it.

- [ ] **Step 1: failing tests:** `auto punch shows Automatic in the timeline`; `auto_undo shows Undo once and sends
  action`; `undoPunch sends action`; `history auto in/out → Automatic`; `overview auto punch → Automatic`;
  `auto_checked_in tap opens My day`; `busy_retry in attendance context → Please try again.`; `undo_not_last text`.
- [ ] **Step 2–4:** FAIL → implement → PASS; `flutter test` all green.
- [ ] **Step 5:** commit `feat(auto): Automatic labels, Undo with action, confirmation pushes`.

### Task 12: Release 1.36.0 and the M4 checklist

**Files:** `pubspec.yaml`, `android/fastlane/metadata/android/en-US/changelogs/default.txt`, `CLAUDE.md`, create
`docs/auto-checkin-release.md`.

- [ ] **Step 1:** version `1.36.0+112`; changelog "Automatic check-in: if your HR turns it on, Omni HR checks you in
  and out at your office." `CLAUDE.md` gains an "Automatic check-in (1.36.0)" section: files, L1–L8, the locked-
  keychain rule, the isolate lease, how to test with `xcrun devicectl device simulate location` and adb test providers
  (memory `project_auto_attendance_20261027`).
- [ ] **Step 2:** `flutter test` all green, `flutter analyze` no new issues, both release builds succeed.
- [ ] **Step 3:** `docs/auto-checkin-release.md` = M4 checklist (all need Willy): spike field days done; device e2e on
  omnihrdemo (Willy's iPhone + Samsung: setup, walk in → Automatic check-in push, Undo, walk out, locked phone,
  airplane mode then back, sign-out removes region); a week on omnihrdemo; Play background-location declaration +
  30 s video (disclosure → permission → walk-in notice); App Store review notes (opt-in, office area only, Undo);
  privacy policy paragraph (omnihr-legal); Data safety update; then TestFlight / Play internal; then stores; then HR
  switches employees on per tenant.
- [ ] **Step 4:** commit `Release 1.36.0 (112): automatic check-in`.
- [ ] **Step 5:** whole-branch review (Codex gpt-6-astra + Fable 5.1, high) before any upload.
