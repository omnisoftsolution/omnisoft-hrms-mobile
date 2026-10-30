# Automatic check-in 1.36.0 (112): M4 release checklist

Every step below needs Willy. Nothing is pushed, uploaded or installed yet. Branch `feat/auto-attendance-app`;
server side (connector 2.66.0, hrmsmanager 1.10.0) is already live on all tenants.

## 1. Before any build leaves this Mac
- [ ] Whole-branch review (Codex gpt-6-astra + Fable 5.1, high) is done and its findings are fixed.
- [ ] Spike field days are done (office walk-in / walk-out on the real iPhone and Samsung, no sim).
- [ ] Final copy check with Willy of the texts the implementer wrote: R14 (opted-out card "Automatic check-in is off
  on this phone...", "Turn on", iOS "One more step", Android step body, paused body), R15 (needsSetup: "Automatic
  check-in needs this phone to be your signed-in phone. Sign out and sign in again on this phone, then come back
  here."), R18 (undo_not_last: "That punch can't be undone any more.").

## 2. Device end-to-end on omnihrdemo (Willy's iPhone and the Samsung)
- [ ] **First, gate (F3):** iPhone, app killed, screen locked: walk in; the event row must appear on the tenant within
  ~1 min of the ENTER. If it does not, shorten the iOS fix limit (≈4 s, fall back to getLastKnownPosition) before any
  store build.

For each phone: setup, then
- [ ] Setup: HR switch on, open the app, disclosure, permission (Always), armed, status screen shows the office.
- [ ] Walk in: an "Automatic check-in" push arrives; My day shows the punch marked "Automatic".
- [ ] Undo from the push or My day: the punch is removed; a second Undo shows "That punch can't be undone any more."
- [ ] Walk out: an automatic check-out push and punch.
- [ ] Locked phone: the same walk-in / walk-out with the screen locked (keychain `first_unlock`, L2).
- [ ] Airplane mode: cross the region offline, switch back: the queued event posts once (same `event_uid`), no
  duplicate; an event older than 30 min is dropped with "Couldn't check you in/out — open Omni HR".
- [ ] Sign out removes the region (no further events) and the key; sign in again on the same phone re-arms.
- [ ] Turn off on this phone, then turn it back on from the setup card.
- [ ] Samsung only: the **release** build starts and a geofence wake runs (R11: the R8 keep rules were checked on the
  mapping file only; the release APK was never started on a phone because the Samsung has the Play-signed install).
  Use the Play internal build, not a locally signed APK.
- [ ] Drop notice shown from a headless isolate (killed app, event older than 30 min).
- [ ] Real `permission_handler` mapping on both phones, including "blocked" (denied twice / restricted): setup shows
  "Open settings" and not a loop; While-using shows the "needs Always" card.
- [ ] Android app update without opening the app leaves automatic check-in off until the app is opened once (R9);
  confirm it re-arms on first open (install over the previous build and check, then say so in the Play notes if needed).

- [ ] Also on both phones: the L4 gap (R24) — an ENTER that never arrived + a manual check-out at the desk + opening the
  app sends a foreground arrive (checks in again). Accepted for v1; note whether it shows up in real use.

Test helpers: see "Automatic check-in (1.36.0)" in `CLAUDE.md` (devicectl location simulation, adb test providers;
wait more than 1 minute after arming on iPhone before simulating). Mock location is a **hard deny** for automatic
events (spec §4.4):
- Samsung: a fix from an `adb` test provider reports `isMocked`, so every such event comes back `rejected /
  mock_location`. It proves only the wake → server path (the event row with that answer); real walks are the only
  proof of an automatic punch on Android.
- iPhone: `devicectl ... simulate location` fixes are mocked too (checked 2026-10-30: `rejected / mock_location`), so
  the punch, push and Undo need real walks on both phones. Simulated crossings still prove wake → server, the offline
  queue and the drop notice.

## 3. A week on omnihrdemo
- [ ] One week with real use by Willy (and any volunteer) on omnihrdemo; no missing / double punches, no battery
  complaint. Log what happened.

## 4. Store paperwork
- [ ] **Play background-location declaration** + a 30 s video: prominent disclosure, then the permission prompt, then
  the walk-in notice. Disclosure text contains "location" and "even when the app is closed or not in use".
- [ ] **Play foreground service type declaration** (App content → Foreground service permissions): the app declares
  `FOREGROUND_SERVICE_LOCATION` (Android 14+, used by the geofence plugin's wake); describe the use (noticing arrival at /
  departure from the office) and attach the same video if asked.
- [ ] **App Store review notes**: opt-in (HR switches it on, then the employee grants Always), office area only, no
  tracking outside the office region, Undo available on every automatic punch. No `location` background mode is used (L1).
- [ ] **Privacy policy paragraph** (omnihr-legal): background location used only to notice arriving at / leaving the
  office, once HR enables the feature and the employee allows it.
- [ ] **Play Data safety** update (precise location, collected, linked, app functionality) and **App Privacy** answers
  in App Store Connect (PrivacyInfo.xcprivacy already declares precise location).

## 5. Release order
1. [ ] TestFlight (`cd ios && LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 fastlane beta`) and Play internal
   (`cd android && fastlane build_and_internal`); smoke test again from the store builds.
2. [ ] Submit to App Store review and Play (alpha, then prod).
3. [ ] After both stores are live and approved: HR switches employees on per tenant (omnihrdemo first, then
   Printart, Omnisoft, Maxhill), one tenant at a time. The server side is already live everywhere.
