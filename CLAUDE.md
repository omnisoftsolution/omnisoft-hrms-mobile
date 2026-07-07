# Omni HR Mobile (omni_hr) — Flutter employee app

Android + iOS employee app for Omni HR (version in pubspec.yaml). Backend = Odoo connector
`omni_hrms_mobile` via `POST $clientUrl/api/v1/omni_mobile/...?db=<db>`
(lib/services/omni_mobile_api.dart). Login flow: company code → SaaS resolver (`omni_hrms_saas`,
`$SAAS_URL/omni_hrms/resolve_company`) → clientUrl, persisted in SharedPreferences
(lib/services/session_service.dart). There is NO in-app server-URL setting.

## Run / test
- On-device: `flutter run -d R8YY921VY1A` (user's Samsung test phone; check `flutter devices`).
- Local dev Odoo: `flutter run --dart-define=SAAS_URL=http://<LAN-IP>:8069` — default is prod
  `https://hrmsmanager.omnisoftsolution.com` (lib/core/constants.dart `defaultSaasUrl`).
- Dev toggles in lib/core/constants.dart: useDevLocation, simulateFaceRecognition, requireReceiptOnExpense.
- `flutter test`: all green (repo suite; count grows with new model tests). No ink_sparkle shader failures in this repo (kiosk-only problem).
- No l10n: no l10n.yaml / lib/l10n — UI strings are hardcoded English.

## Release
- iOS TestFlight: `cd ios && fastlane beta` (`archive_only` = IPA, no upload). Bump pubspec version FIRST
  (prebuild regenerates Generated.xcconfig; stale = ships v<N-1>). ASC .p8 key lives in ~/Keys/ (outside repo).
  Prebuild runs tools/patch_tflite_pod.sh (pins TFLite 2.17.0 for spoof models; idempotent).
- Android Play internal: `cd android && fastlane build_and_internal`; then `promote_to_alpha` / `promote_to_prod`.
  Tester notes: android/fastlane/metadata/android/<lang>/changelogs/default.txt (edit per release).
- Signing: android/key.properties (gitignored) points at a keystore OUTSIDE the repo; absent → debug-keystore
  fallback so `flutter run --release` still works. iOS bundle com.omnisoftsolution.omnihr; Android appId
  com.omnisoft.omnihr (Gradle namespace stays com.omnisoft.omni_hr — do not "fix").

## Build footgun — ALREADY FIXED, do not remove
Flutter 3.44 + tflite_flutter "Inconsistent JVM Target" (`:tflite_flutter:compileReleaseKotlin`) is fixed on
master (f82a8db): android/gradle.properties sets `kotlin.jvm.target.validation.mode=warning`, and the JDK is
pinned machine-wide via `flutter config --jdk-dir` → temurin-17. If the error returns, re-check both.

## Geofence / mock-location (recurring bug area)
- lib/screens/home/home_screen.dart — client fast-fail gate `_isInsideRadius`; fallback
  `_defaultRadiusMeters = 200` mirrors the connector default; 60s GPS polling; clears stale
  "outside geofence" banner when a later fix is inside (radius-widened-by-admin case).
- lib/models/attendance_status.dart — officeRadiusMeters ← `office_radius_meters`, geofenceSource.
- lib/services/location_service.dart + lib/models/location_result.dart — isMocked from geolocator.
- lib/services/omni_mobile_api.dart — attendance body ALWAYS sends `is_mocked`; `location_accuracy` when known.
- lib/core/error_messages.dart — friendly text for mock_location / outside_geofence /
  office_geofence_not_configured error codes.
- Flexible work location (`AttendanceStatus.flexibleLocation` ← `flexible_location`):
  home_screen skips the fast-fail, button stays ready, GPS chip shows neutral
  "Remote" outside the fence. Server logs coords + tags in_work_from/out_work_from
  and flags remote punches for HR review; coords required + mock hard-denied
  server-side for these employees.
Server enforces; the client radius check is UX only. Radius-update bugs: check home_screen's cached
status/distance recompute path first.

## Liveness mirror — HELD, own cadence
Branch `feat/liveness-confidence-threshold` @ 479c32d (unmerged, unpushed) mirrors the kiosk's
0.90 spoof-confidence gate: lib/services/face_spoof_detector.dart, face_recognition_engine.dart,
lib/core/constants.dart. Do not merge just to sync with kiosk; mobile ships it on its own schedule.
iOS is still-frame-only for spoof texture (multi-frame raw-bytes P1.1 open, per kiosk notes).
