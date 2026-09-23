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

## Wi-Fi egress gate (attendance, spec 2026-08-03)
- Android: `ACCESS_WIFI_STATE` + `ACCESS_NETWORK_STATE` in AndroidManifest.xml (with existing
  ACCESS_FINE_LOCATION) let the plugin read the connected SSID/BSSID for office-network verification.
- iOS: `ios/Runner/Runner.entitlements` sets `com.apple.developer.networking.wifi-info` (Access Wi-Fi
  Information) and is wired via `CODE_SIGN_ENTITLEMENTS` on all three Runner build configs in
  project.pbxproj. **Willy gate:** the App ID `com.omnisoftsolution.omnihr` (team 5PBHZ3JDAD) needs
  "Access Wi-Fi Information" enabled in the Apple Developer portal before this entitlement takes effect
  on device — automatic signing regenerates the provisioning profile on the next Xcode/fastlane build.
- No new PrivacyInfo.xcprivacy entry: Wi-Fi info has no dedicated NSPrivacyAccessedAPICategory; the
  precise-location declaration already covers the geofence and this feature reuses it.
- Play Console Data-safety: confirm the existing location-purpose text also covers office-network
  verification for attendance (Willy gate, not automatable).
- Device test caveat: check whether iPhone actually returns a BSSID (iOS 26 reality — Apple has
  progressively restricted this even with the entitlement).

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

## App identity (1.25.0)
- Login chain: the server decides — app credential first, Odoo password fallback while the
  tenant flag is on. `/login` and `/me` both return `auth_source` (`'omni'` | `'odoo'`);
  `SessionService.supportsIdentity` is `authSource.isNotEmpty`. A response with no `auth_source`
  key means a legacy (pre-identity) connector: `updateFromMe` leaves `authSource` untouched rather
  than clearing it, and all new UI (Your devices, forget-this-phone sheet) stays hidden for that
  session.
- `identity_capable` (prefs bool, `SessionService.identityCapable`): set true whenever `/login`,
  `/me` or `/auth/refresh` carries `auth_source`. Stored with the SaaS routing keys — survives
  `clearSession()`, removed by the full `logout()`, reset to false by `saveCompany` when the company
  (code/URL/db) changes. The signed-out login screen shows "Forgot password?" only when it is true
  ("Activate with an invite" is always shown; a pre-2.45 connector answers activation with an HTML
  404 = `server_error`, mapped to "Activation is not available for your company yet. Ask HR.").
- `/login` body is case-preserving: `buildLoginBody` only trims the login (Odoo matches
  `res.users.login` case-sensitively). Activation and password-reset bodies still trim + lowercase.
- Storage keys (lib/services/session_service.dart): secure storage `refresh_token`; prefs
  `refresh_expires_at`, `auth_source`, `device_label`, `identity_capable` (plus the pre-existing
  `user_id`/`user_login` prefs, which the refresh/`/me` paths also update). Biometric credential
  (lib/services/biometric_auth_service.dart): secure storage `biometric_login`,
  `biometric_refresh_token` (new refresh-token mode), legacy `biometric_password` (old
  password-mode credential, still read for accounts that haven't re-logged-in yet).
- `SessionService.refreshAccessToken(deviceId, {refreshToken}) -> RefreshOutcome {ok, invalid,
  failed}` exchanges a device refresh token for a new access token via `/auth/refresh`; `invalid`
  (server returned `refresh_invalid`, or no token to use) drops the stored refresh token, `failed`
  (network/timeout/server error) keeps it for a retry. `SessionService.refreshMe()` re-pulls
  `/me` and folds `auth_source`/`device_label` back in via `updateFromMe`.
- Face ID: a password-mode biometric credential migrates to the refresh token on the first login
  that returns one — `BiometricAuthService.adoptRefreshToken(token, login:)` (called from the
  login and activation screens after every success) does `replacePasswordWithRefreshToken` +
  `updateRefreshToken` in one step, so both a fresh opt-in and an already-refresh-mode credential
  end up current. It is LOGIN-SCOPED: it adopts only when `login` matches the stored
  `biometric_login` (trimmed, case-insensitive) and returns false otherwise, so another person
  signing in on the phone never rebinds the owner's Face ID.
- Company lookup: `SessionService.lookupCompany(code, {saasUrl})` resolves on the SaaS WITHOUT
  saving (URL fallback = `effectiveSaasUrl`: typed URL, else session SaaS URL, else
  `DevConstants.defaultSaasUrl`); `saveCompanyInfo(info, saasUrl:)` commits it;
  `resolveCompany` = lookup + save (company-code screen). The activation screen stages another
  company's invite with `lookupCompany`, activates against the looked-up URL, and only on success
  clears a live session, saves the company and the login response — a failed activation leaves
  `clientUrl`/`clientDb`/tokens untouched.
- Deep link: `omnihr://activate?c=<company>&t=<token>` (invite QR/email). iOS:
  `CFBundleURLTypes`/`CFBundleURLSchemes` in ios/Runner/Info.plist. Android: the `omnihr://activate`
  `<intent-filter>` in android/app/src/main/AndroidManifest.xml. Both platforms go through the
  `app_links` package; `lib/services/deep_link_service.dart` (`DeepLinkService` +
  `parseActivationLink`) delivers both the cold-start link and any link opened while running to
  `main.dart`'s `_navigatorKey`, which pushes the activation screen.
- Testable seams (fake-subclass pattern — subclass, override the network call, no real HTTP):
  `SessionService.refreshAccessTokenWith`, `SessionService.refreshMeWith`,
  `SessionService.resolveCompanyWith`/`lookupCompanyWith`, and `apiBuilder` constructor params
  that swap in a fake `OmniMobileApi` for widget tests on `DevicesScreen`,
  `ChangePasswordScreen` (both `(SessionService) -> api`), `LoginScreen` and `ActivationScreen`
  (both `(baseUrl, db) -> api`, plus a `homeBuilder` so tests don't build HomeShell). Profile's
  logic is in top-level `checkPasswordWith` / `logoutWith` (profile_screen.dart).
  `PasswordCheck` is a const-instance class (ok / wrongPassword / rateLimited / error, plus
  `PasswordCheck.failed(message)` for lockout text). Deep-link dedupe is `LinkDeduper` (drops
  only the first repeat within 2 s — the initial-link + stream double delivery).
- Profile's sign-out sheet: App Identity accounts (`supportsIdentity && authSource == 'omni'`)
  get a choice between plain "Sign out" and "Sign out and forget this phone"
  (lib/screens/profile/profile_screen.dart `_onLogoutPressed`/`_logout`) — forgetting calls
  `/logout {forget_device: true}` and also disables Face ID (`BiometricAuthService.disable()`),
  since the refresh token it held is now revoked server-side. Either path calls
  `SessionService.clearSession()`, NOT `logout()` — `clearSession()` wipes just the login session
  and keeps the biometric credential (unless just disabled) and the SaaS/company routing, so the
  user can sign back in without re-typing the company code. `SessionService.logout()` is the full
  reset (also clears SaaS routing) used for switching companies / delete account, not for sign-out.
- Build note: `app_links` resolved to 6.4.1 in pubspec.lock (pubspec.yaml's own constraint is
  `^6.3.2`; environment sdk is still `^3.11.0`), and 6.4.1 raised the resolved SDK floor to
  Dart >= 3.12 / Flutter >= 3.44 — every build machine and fastlane lane needs Flutter >= 3.44
  (this Mac has 3.44.6), and iOS needs `pod install` before the next build.
- Connector dependency: connector >= 2.45.0 (omnihrdemo runs 2.45.1). Known follow-up: the
  connector will return the credential login as `user.login` for app-credential sessions starting
  in 2.45.2 — not yet true on 2.45.1.
