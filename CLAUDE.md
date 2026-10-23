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
  Run it with a UTF-8 locale: `LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 fastlane beta` — without it
  build_app crashes decoding Xcode output (`"Cr" on UTF-16`, FastlanePtyError), seen 2026-10-08.
- Android Play internal: `cd android && fastlane build_and_internal`; then `promote_to_alpha` / `promote_to_prod`.
  Tester notes: android/fastlane/metadata/android/<lang>/changelogs/default.txt (edit per release).
- Signing: android/key.properties (gitignored) points at a keystore OUTSIDE the repo; absent → debug-keystore
  fallback so `flutter run --release` still works. iOS bundle com.omnisoftsolution.omnihr; Android appId
  com.omnisoft.omnihr (Gradle namespace stays com.omnisoft.omni_hr — do not "fix").
- Building from a git worktree: copy `android/key.properties` from the primary checkout first (gitignored, so
  absent in a worktree → debug-signed AAB → Play rejects "signed with the wrong key").
- Run fastlane with `LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8` — without a UTF-8 locale `fastlane beta` crashes in
  gym's output handling (`"sk" on UTF-16 (Encoding::InvalidByteSequenceError)`).
- iOS export failing with `PLA Update available` / `No signing certificate "iOS Distribution"` = Apple's
  updated Program License Agreement is unaccepted; only the Account Holder can accept it at
  developer.apple.com/account (+ App Store Connect → Business). Then re-run `fastlane beta`.

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
- lib/services/attendance_action_controller.dart — client fast-fail gate `isInsideRadius`;
  fallback `defaultRadiusMeters = 200` mirrors the connector default; `sampleLocation()` runs
  every 60 s from `MyDayScreen` (`_gpsTimer`); `placeLabel` / `isOutside` drive the tile's
  place line, pin badge and button. `perform()` = the old `HomeScreen._onCheckAction`.
- lib/models/attendance_status.dart — officeRadiusMeters ← `office_radius_meters`, geofenceSource.
- lib/services/location_service.dart + lib/models/location_result.dart — isMocked from geolocator.
- lib/services/omni_mobile_api.dart — attendance body ALWAYS sends `is_mocked`; `location_accuracy` when known.
- lib/core/error_messages.dart — friendly text for mock_location / outside_geofence /
  office_geofence_not_configured error codes.
- Flexible work location (`AttendanceStatus.flexibleLocation` ← `flexible_location`):
  the controller's `perform()` skips the fast-fail, the My day button stays ready, the
  tile's place line shows neutral "Remote" outside the fence. Server logs coords + tags
  in_work_from/out_work_from and flags remote punches for HR review; coords required +
  mock hard-denied server-side for these employees.
- The Wi-Fi gate never deads the button (1.29.0): only the geofence makes `buttonState`
  `blocked`; a missing / wrong office Wi-Fi is reported at tap time by `perform()` through
  `friendlyError(wifiPreCheckErrorCode(...))`.
Server enforces; the client radius check is UX only. Radius-update bugs: check the
controller's cached status/distance recompute path first.

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
  Since connector 2.48 invites are `https://<tenant>/omni/activate#c=…&t=…&l=…` (a tenant page whose
  button hands off via `intent://` / `omnihr://`, because Samsung cameras and Gmail don't open custom
  schemes). `parseActivationLink` reads both forms (also `?c=`) and IGNORES the host on purpose — the
  server always comes from the company code. No https intent filter / universal link yet (later upgrade).
- Invite QR scanner (1.25.0+86): `lib/screens/activation/invite_scan_screen.dart` (`mobile_scanner`
  7.4.2; `classifyScan` in deep_link_service.dart; seams `scannerBuilder`, `openSettings`). Entry points
  with seams `scanInvite` + `hasCamera`: company-code screen (`company_scan`), login field
  (`login_scan`), invite screen (`activation_scan`); hidden when `cameraAvailable()` is false.
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
- **App login is any string** (connector 2.47): email, phone or username. The
  activation screen's "App login" is prefilled from the invite link's `l` and
  sent as `new_login` only when changed (`normalizeAppLogin` in
  `lib/core/app_login.dart` decides "changed"). Face ID is always keyed to the
  server's `user.login`, never to typed text.

## Leave approvals (connector >= 2.43.0)
- Capability comes from `/me` → `leave_approvals: {enabled, pending_count}`, stored as
  `SessionService.leaveApprovalsEnabled` / `leaveApprovalsPendingCount` (prefs
  `leave_approvals_enabled`, `leave_approvals_pending_count`; cleared by `clearSession()`).
  A `/me` without the key (older connector) means disabled: every entry point stays hidden.
  Re-pull with `SessionService.refreshMe()`; it is called on Home refresh, after every
  decision, and when a `leave_approval_requested` notification arrives.
- Screens in lib/screens/approvals/: `ApprovalsScreen` (Pending / Recent),
  `ApprovalDetailScreen` (Approve / Refuse), `showRefuseReasonSheet` (reason 3 to 500
  characters, root navigator). Entry points (1.29.0): the `leave_approvals` For-you card on
  My day (shown even when Attendance is off), the `LeaveApprovalsRow` at the top of the Leave
  tab, and `HomeShellState.navigateToApproval(leaveId)` for notifications.
- The app never decides who may act: buttons follow the connector's `can_approve` /
  `can_refuse`, and approve/refuse send `expected_state` so a request someone else already
  decided comes back as `state_changed`.
- Error text for `not_allowed`, `state_changed`, `reason_required`, `not_found`, `not_owner`
  lives in lib/core/error_messages.dart; `friendlyDecisionError` additionally shows an Odoo
  validation sentence as it is.
- Test seams: `apiBuilder` on `ApprovalsScreen` and `ApprovalDetailScreen`
  (`(SessionService) -> OmniMobileApi`, fake-subclass pattern); tests override
  `SessionService.refreshMe()` in a subclass to count refreshes;
  test/services/approvals_api_test.dart drives the real `_post` through
  `http.runWithClient` + `MockClient`.
- Known gap: `/leave/attachment/get` answers `not_owner` for anyone but the leave's own
  employee until connector 2.50.0; an approver cannot open an attachment yet.

## App access scope (1.32.0, connector 2.62.0)
Spec: connector repo `docs/superpowers/specs/2026-10-10-app-access-scope-design.md` §3.3 / §3.8.
- Approvals: pending / recent / get rows carry `waiting_for` `{role, names, you}` → `WaitingFor`
  (lib/models/approval_item.dart). `ApprovalItem.stepLabel` and the current step's
  `ApprovalStep.title` use `WaitingFor.label` ("Your approval", "Waiting for Kelvin (manager)",
  " +N" for more names, "Waiting for HR", "Waiting for manager"); without the key (connector
  < 2.62) the old texts stay. Pending is split by `assigned_to_me` into "Waiting for you" /
  "You can also approve" ("Nothing waiting for you." when only the second part has rows).
- Add this phone: links carry `k=add` (`omnihr://activate?k=add&c=…&t=…&l=…`, or the https
  `/omni/activate#k=add&…` page that hands off to it). `ActivationArgs.kind`; an unknown `k`
  is not opened. `screenForActivationLink` (lib/screens/activation/link_route.dart) is the one
  switch for main.dart and the company-code / login / activation scanners; the sign-in screen
  has an always-visible "Add this phone" (`login_add_phone`). `AddPhoneScreen` posts
  `auth/add_device` (`buildAddDeviceBody`: login, token or code, app password, device_id,
  device_label, app_version) and saves the session like activation (staged company switch,
  `saveLoginResponse`, Face ID adopts the refresh token). Errors go through
  `friendlyError(e, context: ErrorContext.addPhone…)` only (error_messages.dart: add-phone words
  for `mobile_not_enabled`, a lost answer after the post, `invalid_code` after a lost answer
  ("may already be added", `ErrorContext.addPhoneAfterLostAnswer`; only for an unchanged retry:
  `_lostAnswerKey` = company + login + token/code, snapshotted at submit and the same snapshot
  is what `addDevice` sends; cleared when any changes; `network_error` counts like `timeout`
  because the transport cannot tell "never sent" apart, so both texts end "If sign-in doesn't
  work, ask HR for a new code."; while switching
  company the words name it via `addPhoneCompany`), an older connector; before
  the post `addPhoneLookup` keeps the usual network words; the rest as usual: `invalid_code`,
  `invalid_credentials`, `not_active`, `account_locked`, `seat_limit_exceeded`,
  `rate_limit_exceeded`). A static "New to Omni HR? Use Activate with an invite." opens
  activation (the server answers invited accounts with `invalid_credentials`, no state oracle).
  Once the server answers success the form is spent (`_added`); a failed staged
  `saveCompanyInfo` is retried once, then the message names the new company; only a failed
  session save shows "sign in"; Face ID adopt / opt-in are best effort. Success pushes a
  fresh `SessionGate` (lib/screens/session_gate.dart, also main.dart's home) so a later
  `invalid_session` still lands on sign-in. An app older than 1.32 opens an add link as an
  invite and gets `activation_invalid` (the page says "Update the Omni HR app first").
- Older connector (< 2.62, no `auth/add_device`): Odoo answers an HTML 404, which `_post`
  reports as `server_error` with `data.http_status` 404; on this call only (also a JSON
  `unknown_route`) the screen says "Adding a phone isn't available for your company yet. Ask
  HR." and the saved session is untouched. An HTML 500 keeps the generic server-error words.
- Rollout: the connector's Add phone button needs this app (1.32). HR should not use it until
  1.32 is live on the stores, or the tenant's Minimum App Version on hrmsmanager is 1.32.

## My day (1.26.0)

Spec + plan live in the connector repo:
`docs/superpowers/specs/2026-10-05-my-day-kiosk-only-design.md`,
`docs/superpowers/plans/2026-10-05-my-day-kiosk-only.md`.

- `SessionService.attendanceKioskOnly` ← `employee.attendance_kiosk_only` on `/login` and
  `/me` (connector 2.51.0+; missing key = false; prefs key `attendance_kiosk_only`).
- The Home tab is `MyDayScreen` for everyone since 1.29.0 (`home_tab_root.dart` and the
  classic `home_screen.dart` are gone), except for employees HR grants the Team overview (1.34.0):
  `HomeRoot` then shows `TeamOverviewScreen` or the Team overview | My day switch (see "Team leave +
  Team overview" below). `SessionService.attendanceKioskOnly` only has to
  agree with `today.kiosk_only`; My day re-pulls `/me` when the day says the flag is off
  while the session still says on (HR cleared it).
- `lib/screens/home/my_day/`: `my_day_screen.dart` (one call, `OmniMobileApi.fetchMyDay()`
  → `POST /home/my_day`; keeps the last loaded day on a failed refresh),
  `status_tile.dart` (1.27.0; replaced `today_card.dart` — the action slot was dropped,
  phone users are out of scope), `day_timeline.dart`, `for_you_list.dart`. Models in `lib/models/my_day.dart`; unknown
  For-you kinds are dropped at parse time.
- The server enforces kiosk-only (`kiosk_only`, HTTP 403). `OmniMobileApi.onKioskOnly`
  (wired in `main.dart`) re-pulls `/me` when any call is refused that way. Since 1.29.0
  (My day for everyone) every employee sees My day; the kiosk-only flag decides only
  whether the tile shows the check-in button.
- Refresh: first build, pull down, Home tab tap/re-tap (`HomeShell._onTabTap`), return
  from a pushed screen, app resume (`AppLifecycleListener`). No polling. Overlapping
  `refresh()` calls share one in-flight request. A `kiosk_only: false` answer re-pulls
  `/me` (the tile gets its check-in button back; My day stays). `_onTap` ignores taps while
  one is in progress.
- For-you rows: `ForYouItem.id == 0` (server omitted it) means a `my_leave` / `my_expense`
  row does nothing on tap. `my_expense.state` shows `submitted` → "Waiting for approval",
  `approved` / `posted` / `in_payment` / `paid` → "Approved", `refused` → "Refused".
  Dates: `my_leave.date_from` / `date_to` are plain dates, `oldest_at` is a UTC datetime.
  `DateFormat` / `NumberFormat` in For you are pinned to `en_US` (no l10n in this app).
- `no_employee_linked` from `/home/my_day` is HTTP 404 (not 403): it comes from the
  connector's shared `_get_employee` helper.
- `today.punches` may include a check-in carried over from the previous day (night
  shift); `DayTimeline` orders purely by time and does not look at the date.
- Tests: `test/screens/my_day/`,
  `test/models/my_day_test.dart`, `test/services/my_day_api_test.dart`,
  `test/services/session_kiosk_only_test.dart`; fixture `test/fixtures/my_day_fixture.dart`.

### 1.27.0 — My day v2 (spec `…/2026-10-06-my-day-v2-design.md` in the connector repo)
- `lib/screens/home/my_day/`: `status_tile.dart` (replaces `today_card.dart`; `showKioskSheet`),
  `week_strip.dart`, `day_timeline.dart` (pure `buildTimeline(day, {now})` + `_RailPainter`),
  `for_you_list.dart` (`missing:` prepends the app's own red row), `my_day_display.dart`
  (pure `displayOf` / `toneOf` / titles; one display state per spec §4.2 row, first match
  wins), `my_day_colors.dart` (the seven `MyDayTone`s of spec §4.1).
- Every 2.52.0 key is optional in `MyDay.fromJson`; against a 2.51.0 connector the week
  strip is hidden, minutes are 0 and `off` is null (no shift + no punches reads "Day off").
  `MyDay.hasMinutes` (= the body carries `late_minutes`) gates the timeline's "On time" badge,
  so a 2.51.0 connector never shows a false "On time". An off day with punches shows the
  live state, not "Day off".
- Copy stays literal in the widgets; `DateFormat` pinned to `en_US`.
- Tests: `test/screens/my_day/{my_day_display,status_tile,week_strip,day_timeline,for_you_list,my_day_screen}_test.dart`.

### 1.28.0 — Tap a day (spec §8 of the My day v2 spec, connector 2.52.1)
- `lib/screens/home/my_day/day_sheet.dart`: pure `daySummaryOf(MyDayWeekDay)` → `DaySummary`
  (title / head / sub / tone / icon per kind) and `showDaySheet(context, day)`. The sheet is
  **deliberately on the tab navigator** (`useRootNavigator: false`) so it rises from the bottom
  bar and stops there — the bar stays visible and tappable. `showKioskSheet` keeps the root
  navigator; that remains the rule for every other modal in a tab.
- `week_strip.dart`: every non-today cell is an `InkWell` (`week-tap-<date>`) with a `Semantics`
  button label "<Day>, <kind>"; today is not tappable; the legend chips are gone.
- `MyDayWeekDay` parses the 2.52.1 keys (`shift`, `first_in`, `last_out`, `worked_minutes`,
  `late_minutes`, `early_minutes`, `place`, `approver`); on a 2.52.0 connector the sheet shows
  the kind only ("Worked · on time", "Public holiday", …).
- Tests: `test/screens/my_day/day_sheet_test.dart`, `week_strip_test.dart`, `test/models/my_day_test.dart`.

### 1.29.0 — My day for everyone (spec `…/2026-10-07-my-day-for-everyone-design.md` in the connector repo)
- `lib/services/attendance_action_controller.dart`: `AttendanceActionController` (ChangeNotifier)
  holds `/attendance/status`, the GPS + Wi-Fi samples, `needsEnrollment`, `buttonState`
  (`enroll` / `ready` / `blocked` / `acting`) and `perform({captureFace, enrol})`, the punch flow
  moved verbatim from the deleted `HomeScreen`. Every external call is an injectable seam
  (`apiBuilder`, `getLocation`, `getWifi`, `getDeviceId`, `isEnrolled`, `verifyFace`,
  `refreshEnrolled`); no widgets, no navigator.
- `MyDayScreen` owns one controller while `today.kiosk_only` is false (`_syncController`),
  samples GPS every 60 s, pushes `FaceCaptureScreen` / `FaceEnrollmentScreen` on the **root**
  navigator, shows the `AutoClosedBanner` above the week strip, and re-pulls `/me` when the
  session knows the user approves and the For-you `leave_approvals` count differs from
  `session.leaveApprovalsPendingCount`.
- `StatusTile(action:, place:, pinOn:)`: `TileAction` (filled / outlined, face / faceSetup icon,
  `enabled`), the live place appended to the subtitle, a pin badge instead of the kiosk button.
  Labels: "Check in", "Check out", "Check in again" (outlined, after a closed row), "Set up your
  face · 10 seconds"; dimmed and dead while outside the office.
- `buildTimeline(day, {now, phoneHint})`: phone wording when `!day.kioskOnly`; the missing day's
  red For-you row is kiosk-only.
- Check out only while checked in: the tile's label comes from `controller.status?.checkedIn`
  (the truth `perform()` punches on), not the day state. `on_break` is a closed attendance, so
  it shows outlined "Check in again" and the tap posts a check-in.
- Off days (`leave` / `public_holiday` / `not_scheduled`, no shift): phone users get a live
  outlined "Check in" (same gates: enrolment first, dead while outside); kiosk-only days keep no
  button.
- Attendance off (`!session.featureAttendance`): `MyDayScreen` owns no controller (no GPS timer,
  no punch) and shows `FeatureLockedPane` in place of the tile + timeline; the week strip and
  For you stay.
- Leave approvals: the `leave_approvals` For-you card is the only Home entry (no card when nothing
  waits). `LeaveApprovalsRow` (`lib/screens/leave/leave_approvals_row.dart`) tops the Leave tab
  for approvers and opens `ApprovalsScreen(initialSegment: 1)` (Recent) when nothing waits.
  `LeaveTabIcon` (`lib/screens/home/leave_tab_icon.dart`) badges the LEAVE destination with the
  count and wiggles once when it goes up (not on the Leave tab, not under reduced motion).
  `approvalsBreakdown()` lives in `lib/core/approvals_breakdown.dart`.
- Tests: `test/services/attendance_action_controller_test.dart`,
  `test/screens/my_day/{status_tile,day_timeline,my_day_screen}_test.dart`,
  `test/screens/leave_approvals_row_test.dart`, `test/screens/home/leave_tab_icon_test.dart`,
  `test/core/approvals_breakdown_test.dart`.

### 1.30.0 — Forgot something? (spec `…/2026-10-07-forgot-something-design.md` in the connector repo, connector 2.54.0)
- `lib/models/attendance_ask.dart`: `AttendanceAsk.tryParse(resp['ask'])` (null on 2.53.x → nothing
  asked), `AskOption` (`needsTime`, `suggestedTime` UTC), `DeclarationAnswer`, `awayLabel`,
  `nothingToDeclare` (`start_now`, `just_arriving`, `overtime` post nothing). Titles and the
  footnote ("Your check-in stays at 09:12. HR will review your answer.") are built in the app;
  option labels come from the server.
- `AttendanceActionController.perform` parses `ask` (check-in only), `undo_until` and
  `attendance_id` into the outcome; `applyStatus()` takes the status `attendance/undo` returns.
- `lib/screens/home/my_day/declaration_sheet.dart`: `showDeclarationSheet` on the **root**
  navigator (covers the bar); one option at a time, time chip → `showTimePicker` 24 h `en_US`,
  optional note, "Send to HR" / "Skip" ("Undo check-in" in red for `undo`). Used after a
  check-in (`MyDayScreen._askAfterPunch`), by the For-you `YesterdayCard` (`trigger: yesterday`)
  and by the bell for HR's `attendance_query` (posts to `review/answer`, then marks read).
- Punch snackbar: `UNDO` while `now < undoUntil`, `persist: false` (Flutter keeps a bar with an
  action until tapped otherwise), duration min(window, 10 s); Undo → `undoPunch` →
  `applyStatus` → reload, "Punch undone".
- Bell: `attendance_declaration_applied` ("HR updated your attendance", `event_available`) opens
  My day via `HomeShellState.navigateToMyDay()`; `NotificationRecord.answered` stops a second
  answer.
- API: `OmniMobileApi.declare` / `undoPunch` / `answerReview`, `buildDeclareBody` (declared time
  as the API's UTC string). New error codes in `friendlyError`: `undo_expired`, `undo_not_last`,
  `bad_time`, `too_old`, `not_yours`, `already_answered`, `invalid_answer`.
- Tests: `test/models/attendance_ask_test.dart`, `test/services/forgot_something_api_test.dart`,
  `test/core/error_messages_forgot_test.dart`, `test/screens/my_day/declaration_sheet_test.dart`,
  `test/screens/notifications_screen_forgot_test.dart`, plus groups in
  `attendance_action_controller_test.dart`, `my_day_screen_test.dart`, `for_you_list_test.dart`.

### 1.30.1 — signature check-in page restored
1.29.0 had replaced the classic home's signature punch (pulsing `BigCheckButton` + inline 3-2-1
`InlineFaceCapture`) with the bare full-screen `FaceCaptureScreen`; Willy wants the signature back.
- `lib/widgets/big_check_button.dart` and `lib/widgets/silent_face_capture.dart` are restored
  unchanged from master (ccd2554). **Do not delete them again.**
- `CheckInOutScreen` (`lib/screens/home/my_day/check_in_out_screen.dart`): the tile's Check in /
  Check out pushes it on the root navigator and it starts by itself — pulsing circle while the
  GPS / Wi-Fi gates run (at least `minPulse` 900 ms), the 3-2-1 camera, the scanning circle while
  verify + POST run, a green tick ("Checked in HH:MM", `successHold` 1.1 s), then it pops a
  `CheckInOutResult(outcome)`. My day then shows the snackbar, UNDO and any question.
  `PopScope(canPop: false)` while running: the camera's ✕ is the way out. Face setup (enrol
  state) skips the page.
- **Layout C (Willy, 2026-10-08; canvas row "Check-in page — 3 options", boards K-*)**: header
  card (initials, name, date · shift, clock, amber late note on the day's first check-in), the
  circle (centred, `FittedBox` scales it down on short screens), a 4-row checklist (Location,
  Office Wi-Fi, Face, Record the check-in → "Checked in HH:MM") and "Hours today · Last out".
  Rows follow `perform(onStep:)` (`PunchStep` running/done/skipped, "Not required" when the
  tenant doesn't need it). A failure keeps the page open: the running step turns red with the
  friendly reason, the circle reads NOT READY, Close pops `outcome: null` (My day shows nothing).
  The 1.30.1 (93) first cut had the circle off-centre (a shrink-wrapped Column) and no context.
- Circle size `_kCircle` = 260 (the 1.28 button's 200 + 30%, Willy 2026-10-08); halo +48 → 308 for
  the button, the camera and the tick alike. Title of the Home tab: `helloTitle()` → "Hello, Ethan".
- `FaceCaptureScreen` is now only used by face enrolment.
- Seams: `MyDayScreen.captureFace` (punch without the page, the older tests) and
  `MyDayScreen.signatureCaptureBuilder` / `CheckInOutScreen.captureBuilder` (fake camera).
  Tests: `test/screens/my_day/check_in_out_screen_test.dart` + one My day test.

### 1.31.0 — leave e2e fixes (connector 2.57.0 adds two keys; both optional)
- `leave/apply` → `approver` ('' = approved on creation): the receipt's Approver row uses it
  (`receiptApprover` in leave_screen.dart); no key (older connector) = /me's Time Off approver.
- `leave/history` items → `refusal_reason`: "Refusal reason" row on a refused card.
- `validate1` reads "Waiting for HR" in the Pending colour (History chip, For-you).
- Dates everywhere go through `leaveDatesLabel` (lib/core/leave_dates.dart; approvals cards and
  `LeaveRecord.summaryLabel`); amounts through `unitCount` ("1 day", "3 hours", core/leave_units.dart).
- History reloads itself: `isLeaveChangedError` (error_messages.dart: not_cancellable /
  not_modifiable / not_found / state_changed) after cancel/edit; `refresh(quiet: true)` keeps the
  cards; leave notifications while the History tab shows (`reloadsLeaveHistory`) and the Leave
  segment switch reload too.
- `/login` has no `leave_approvals` block: `SessionService.refreshMeIfStale()` (30 s) runs on every
  Leave tab open, and My day re-pulls /me whenever its approvals card count differs from the session.
- Half-day Morning/Afternoon: `PeriodSegmentedRow` (lib/widgets/) shared by apply + edit sheets.
  Range picker draws its own month header ("Previous month" / "Next month" tooltips) and sizes the
  weekday row from the text scale.
- Seams: `LeaveScreen(apiBuilder, appBar)`, `LeaveHistoryScreen(apiBuilder)`,
  `SessionService.clock`. Tests: `test/screens/leave_screen_test.dart`,
  `test/screens/leave_history_screen_test.dart`, `test/widgets/{period_segmented_row,range_picker_dialog}_test.dart`,
  `test/core/leave_dates_test.dart`.

## Push notifications (1.33.0, connector 2.63.0, hrmsmanager omni_hrms_saas 1.9.0)
Spec: connector repo `docs/superpowers/specs/2026-10-11-push-notifications-design.md` §6.
- Firebase project `omni-hr-omnisoft`. Client configs are committed: `android/app/google-services.json`
  (read by the `com.google.gms.google-services` 4.4.4 Gradle plugin) and `ios/Runner/GoogleService-Info.plist`
  (a Runner resource in project.pbxproj). Pins: firebase_core 4.15.0, firebase_messaging 16.7.0 (Firebase iOS
  SDK 12.19.0), flutter_local_notifications 22.3.1 (core library desugaring, desugar_jdk_libs 2.1.4).
- iOS: `aps-environment` + time-sensitive entitlements in Runner.entitlements, `UIBackgroundModes`
  `remote-notification`. **Willy gates:** the App ID needs Push Notifications + Time Sensitive Notifications in
  the developer portal; the APNs key must be uploaded to Firebase (key `8KU7H22B9A`, done).
- **SwiftPM is OFF for this project** (`flutter: config: enable-swift-package-manager: false` in pubspec.yaml), so
  Firebase and ML Kit share one set of Google pods (GoogleUtilities, GoogleDataTransport, Promises) via CocoaPods;
  with SwiftPM on, both define the same ObjC classes. Don't re-enable it without moving ML Kit to SwiftPM too.
  Backlog: Firebase stops publishing to CocoaPods after Oct 2026, so later Firebase upgrades need a plan.
- **Before the first 1.33 `fastlane beta` from the main checkout:** discard that checkout's leftover uncommitted
  SwiftPM changes (project.pbxproj, the Runner scheme, the `swiftpm/` folders, Podfile.lock), then `flutter clean`
  and `pod install` with `LANG=en_US.UTF-8` (CocoaPods needs a UTF-8 locale; `ios/fastlane/Fastfile` sets
  `ENV['LANG'] ||= 'en_US.UTF-8'` itself, a manual `pod install` / `flutter build ios` still needs it).
- Android manifest: `default_notification_channel_id` = `requests` (fallback for a push naming no channel or one
  the app has not created yet; otherwise FCM makes a "Miscellaneous" channel).
- `omnihr/push` native channel (`ios/Runner/PushPlugin.swift`, registered in AppDelegate after the face plugin)
  behind `PushNative` (lib/services/push_native.dart): removeDelivered / clearDelivered / setBadge on iOS;
  Android goes through flutter_local_notifications (`cancelTag` = cancel id 0 + tag omni_key, `cancelAll`, one
  channel per group from lib/core/push_groups.dart). Android status-bar icon `@drawable/ic_stat_notify` (kept from
  the resource shrinker by res/raw/keep.xml).
- `PushService` (lib/services/push_service.dart): registers the FCM token whenever the session's access token
  changes (sign-in, refresh, app start), except the token being signed out (`_retiredToken`: it is never
  re-registered, even if the session still shows it), on onTokenRefresh and on resume after a failure; iOS `apns-token-not-set`
  is retried 3 times (2 s, 3 s, 5 s). Every push call uses `PushTarget` (a snapshot of base URL, db and token taken
  when the token arrived) plus a generation counter: never read `SessionService` fields inside a push call — Settings
  → Company saves the new company *before* `signOut()`, and a routing change under the same token registers nothing.
  **One serialized lifecycle** (review fix round 1): registrations run one at a time per generation (a worker;
  a token refresh while one is on the wire queues exactly one follow-up that reads the newest token;
  `_registeredToken` = the FCM token the server accepted); a registration first lets every older push/register on
  the wire land (≤ 5 s) and waits for the last sign-out's teardown — the **real** `deleteToken` future, not a
  timed-out wait — up to a 30 s safety cap (`teardownWaitCap`; past it it registers now and again with the fresh
  token once the deletion ends); right before sending it re-checks that the snapshot is still the live session
  (token, client URL, db, signed in, no sign-out running) and sends nothing otherwise.
  `SessionService.onSessionClearing` runs before every sign-out (clearSession, signOut, logout — logout runs it
  before wiping the company routing) → waits for every `push/register` on the wire, `push/unregister` with the
  snapshot (quiet `_send(fireHooks: false)`: never fires onInvalidSession), clear delivered, badge 0, deleteToken;
  unregister and the on-wire wait time out after 5 s. **Sign-out waits at most ~2 s** for this clean-up
  (`signOutCap`); the rest finishes in the background. While the hook runs (`PushService._clearing`) and until
  SessionService has finished the sign-out (`SessionService.isClearing`), no access token is adopted; SessionService
  notifies when it ends. With nothing to tear down (signed out already, nothing on the wire: Clear Company on the
  login screen, a late invalid_session) the hook only clears delivered + badge and returns at once — no deleteToken.
- `SessionService` sign-outs: concurrent `clearSession()` calls join one in-flight sign-out (a call from inside the
  hook — marked by a zone — returns at once instead of waiting for itself; `logout()` waits for a running one, and a
  `clearSession()` during `logout()` joins it). The fields are wiped only if no new access token was saved while the
  hook ran (`_authEpoch`, re-checked inside the persistence queue): a sign-in completed meanwhile is newer and stays.
  **Every write/removal of the stored session goes through one queue (`_persisting`)** — saveSession, refresh,
  /me updates, kiosk flag, saveCompany, the wipe, logout's wipe — so an older wipe never deletes a newer sign-in's
  keys. Never call a locked method from inside a `_persisting` body (it would wait for itself); the idle queue runs
  at once and keeps no completed future (a cross-zone future hangs fake-async widget tests). An `auth/refresh` that was on the wire when a sign-out of a signed-in session
  started is dropped (`RefreshOutcome.failed`). `refreshAccessToken` itself is only called by LoginScreen (Face ID).
- Receiving: a push whose `company_code` is not the session's is ignored, and so is every foreground push while no
  push session is active (signed out, or a sign-out running). Foreground notice →
  `NotificationService.refreshNow()` (the usual arrival snackbar), then the iOS badge is set to the bell's unread
  count (iOS applies no `aps.badge` while the app is open); reminder → `pushArrivalSnackBar` ("Open" → My
  day; an empty title becomes the connector's wording via `reminderTitle`: "Time to check in" / "Still at
  work?"); `remove` → `applyRemove` (foreground and `firebaseBackgroundHandler`, which first calls
  `DartPluginRegistrant.ensureInitialized()` and reloads SharedPreferences before reading `company_code`). The
  background `remove` sets its badge only while the `push_signed_in` marker says a session exists (set when a
  session is adopted, removed at sign-out — the company code survives sign-out), re-read after the removal.
  The FCM streams (token, onMessage, onMessageOpenedApp) have token-free `onError` handlers.
- Taps: the launch message (`getInitialMessage`) is looked up in the background with a 3 s timeout — `init()`
  never holds `runApp`; its tap waits in `consumePendingTap` like any other. `PushService.sessionStillCurrent()`
  lets HomeShell drop a `notifications/get` answer that arrives after a sign-out or a new access token, and
  `LatestTap` drops an older tap's answer once a newer tap arrived (the same check is passed into
  `handleNotificationTap(stillCurrent:)` and asked again after `markRead`; the bell passes none).
  `PushService.consumePendingTap()` in HomeShell
  → `popAbove` (closes Profile / Payslips / the bell / the explainer on the root navigator) → `openPushTap`
  (lib/screens/notifications/notification_tap.dart): reminders → Home; notices → `notifications/get` →
  `handleNotificationTap` (the bell's handler, shared with NotificationsScreen), else the bell (announcements,
  system, 404, offline, an unanswered HR question without usable options).
- Permission (firebase_messaging 16.7.0, five `AuthorizationStatus` values): Android 13+ `notDetermined` = never
  asked, `denied` = may ask again ("Turn on notifications"), `deniedPermanently` = settings ("Open settings"); iOS
  `denied` = settings. **Android < 13 (API ≤ 32) refused notifications → "Open settings"** (no system prompt exists;
  `androidSdk` seam in PushService). The explainer (lib/widgets/push_explainer_card.dart) shows once per phone when
  push_available, the status is `notDetermined` and `push_explainer_seen` is unset.
  Profile → Notifications (lib/screens/profile/notification_settings_screen.dart) only when push_available; mute
  saves are serialized (`savePrefs`) and every switch waits while one saves. A `push/prefs/get` that failed after
  the registration worked is asked again on resume while the prefs are unknown, then the explainer is re-checked.
- Badge: bell open (`PushService.onBellOpened`) → clearDelivered + setBadge(unread) — the badge only when the list
  came (`refreshList` left no `lastError`); resume → refresh + setBadge(unread) (0 signed out); foreground notice →
  refresh + setBadge(unread). Resume / foreground set it only when `NotificationService.refreshNow()` answered true
  (a count was fetched: not 0 before HomeShell started the bell, not a stale count offline). Each needs an active
  push session, takes the generation before its await and sets nothing if the session ended meanwhile (a
  sign-out's own clean-up already set the badge to 0); the bell also skips it when closed meanwhile.
- Tests: `test/services/push_*_test.dart` (lifecycle races in `push_lifecycle_test.dart`), `test/services/session_push_hook_test.dart`,
  `test/core/push_groups_test.dart`, `test/screens/notification_tap_test.dart`, `test/screens/company_switch_push_test.dart`,
  `test/screens/notification_settings_screen_test.dart`, `test/screens/notifications_screen_push_test.dart`,
  `test/screens/home/push_arrival_snackbar_test.dart`, `test/widgets/push_explainer_card_test.dart`; fakes in
  `test/services/push_fakes.dart`.
- Older apps (≤ 1.32) never register a token: no pushes, they keep polling. No minimum-version change.

## Team leave + Team overview (1.34.0, connector 2.65.0)
Design: `session-assets/2026-10-22-team-leave-mgmt-day/proposal.md` (r3); plans: this repo
`docs/superpowers/plans/2026-10-22-team-leave-overview-app-1.34.0.md`, connector
`docs/superpowers/plans/2026-10-22-team-leave-overview-connector-2.65.0.md` (API contract).
- `/login` + `/me` employee keys → `SessionService.attendanceTracked` / `overviewAccess` / `teamLeaveSource` /
  `teamScopeSig` (prefs `attendance_tracked`, `overview_access`, `team_leave_source`, `team_scope_sig`; missing =
  false / none / off / ''). `homeView` (myDay | overview | dual) and `teamLeaveEnabled` are derived; both also
  need a SaaS feature: Team overview is part of **Attendance** (`homeView` needs `featureAttendance`, Time Off
  plays no part), Team leave needs Time Off. With an overview grant but no Attendance, Home stays My day (locked
  attendance pane + week strip + For you; plan A-L16, A-L24). With Attendance but no Time Off the server sends
  `who_out: null` and the overview hides Who's out and its 30 / 60 / 90 link.
- Pending (not yet approved) leave of colleagues is an HR setting, **off by default**: `TeamDisclosure.showPending`
  is true only when the server sends `true` (plan D3, A-L25). Pending chips follow each row's `state`.
- LEAVE tab: `TeamLeaveTile` after the approvals row (one `leave/team_outlook` call, `summary`); screen
  `lib/screens/team/team_leave_screen.dart` (heat map `heat_map.dart`, text `team_format.dart`, colours
  `team_colors.dart` — the only hex values, dark mode goes there). Apply sheet: `AlsoOffLine` (informational,
  never blocks submit).
- HOME: `HomeRoot` (`lib/screens/home/home_root.dart`) picks My day / `TeamOverviewScreen` / the switch
  (`PillSegments`, remembered per employee `home_mode|<db>|<id>`). Overview: counts, Yesterday (reviewed),
  drill-down `OverviewDrillScreen` (tab navigator), person sheet (root navigator), Who's out, For you (shared
  `openForYouItem`; `yesterday_incomplete` stays on My day). Missing route / any access-lost answer → My day for the run +
  `refreshMe()`. A Who's out row opens the person sheet only with `names` and `WhoOutToday.tracked`.
- Errors on these screens: `friendlyError(e, context: ErrorContext.team)` (own branch: `not_allowed` / `not_found`
  wording, usual transport words otherwise); `names_hidden` / `invalid_department` have words in every context.
- Cache: `TeamCache` (`team_v1|<db>|<employee>|…`, signature = `team_scope_sig`, else
  overview_access/team_leave_source/department/company), keys only via `TeamCache.outlookKey` / `overviewKey`
  (the LEAVE row and the outlook share the 30-day entry); cleared on sign-out, logout and any access-lost answer.
  A caller takes the key and `TeamCache.bind(s)` (employee, `teamCacheSignature`, `TeamCache.generation`,
  `SessionService.requestEpoch`) **before** its request; the outlook, the LEAVE tile, the overlap line and the
  overview check `binding.isCurrent(s)` before every setState an answer or cached read drives, and `write` checks
  it too: a stale answer is neither shown nor stored, the screen clears and asks again (not while signed out).
  Every clear bumps the generation; `requestEpoch` advances when a sign-out / logout begins and on every new
  access token, even when a sign-in during the hook skips the wipe. Writes and clears are serialised. The person
  sheet is never cached. A clear sets a read barrier before it notifies (`read` misses the cleared entries even
  while the removal waits behind an earlier write) and sends the removal to storage at once, ahead of the queue,
  so a killed app keeps no entry (A-L23). Never let a clear notify before reads miss its entries.
- A shown answer keeps its binding (A-L22): the outlook, the LEAVE tile, the overlap line, the overview, the
  drill-down and the person sheet listen to `TeamCache.watch(s)` (every session notify + every clear; the
  generation is a `ValueNotifier`) and drop a stale answer before the next frame, then ask again (not while a
  request is on the wire, signed out or during a sign-out). A failed refresh never keeps a stale answer under the
  strip. Never keep an `OmniMobileApi` across attempts: build it from the session next to `TeamCache.bind`
  (its token is final, and an `invalid_session` answer clears the session via `onInvalidSession`).
  `showOverviewPersonSheet` takes an `apiFor` builder for that reason.
- The Team overview's `for_you` cards are never served from `TeamCache` (A-X2). The overview writes its cache body
  with `for_you: []`, strips `for_you` on read, and shows no For you section (no header, no empty state) when it
  shows a cached answer. The reason is that the expenses and payroll flags behind those cards are not part of
  `team_scope_sig`.
- Tests: `test/screens/team/`, `test/screens/home/overview/`, `test/screens/home/home_root_test.dart`,
  `test/services/session_team_flags_test.dart`, `test/services/team_api_test.dart`, `test/services/team_cache_test.dart`,
  `test/models/team_*_test.dart`, `test/widgets/pill_segments_test.dart`.
- Needs connector 2.65.0 for anything to show; older connectors keep 1.33 behaviour (matrix in the plan).
