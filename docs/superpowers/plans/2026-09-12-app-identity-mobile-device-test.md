# Device test — pending Willy (omnihrdemo, connector 2.45.1)

See `omnisoft-hrms-odoo-connector/docs/superpowers/plans/2026-09-12-app-identity-mobile.md` §Task 7 Step 3 for the full plan-level context this device test belongs to.

## Preconditions

- [ ] `pod install` run on this Mac (ios/ pods regenerated for the app_links bump) before building.
- [ ] Flutter >= 3.44 on the build machine (this Mac has 3.44.6).
- [ ] Connector 2.45.1 installed on omnihrdemo.
- [ ] HR has sent the invite from the employee's App Access tab (Odoo) for each test employee/phone used below.
- [ ] The tenant setting "Email a code when a new phone signs in" requires an outgoing mail server — omnihrdemo has none configured, so Step 4 below needs a mail server set up first.

## Steps

- [x] **Step 1 — Phone A: fresh install + QR activation + Face ID**
  Fresh install, scan QR from Odoo -> activation -> home. Enable Face ID. Kill app, reopen -> Face ID -> home.
  Result: PASS 2026-09-28 (Arjun Patel, iPhone)

- [x] **Step 2 — Phone B: email link activation, same employee**
  Open the invite email link from Mail -> activation with the same employee -> phone A is signed out (activation sets a new password); only phone B is listed under Your devices.
  Result: PASS 2026-10-02. Since connector 3d3d7fe the activation signs out phone A (new password); only phone B is listed. Add a second phone by signing in with the password instead.

- [x] **Step 3 — Revoke phone B from Odoo**
  Odoo App Access -> revoke phone B -> phone B relaunch -> `/me` returns `invalid_session` -> login screen with NO message. Tap Face ID -> "Please sign in again." appears and Face ID turns off.
  Result: PASS 2026-10-02

- [x] **Step 4 — New-device email code (needs mail server)**
  Turn on "Email a code when a new phone signs in" -> phone C password login -> code dialog -> code from email -> home.
  Result: PASS 2026-10-02 (Willy, iPhone; code email from "Omni HR" within seconds after the mail-queue fix f7ccb1c)

- [x] **Step 5 — Odoo password login disabled for a never-activated employee**
  Turn off "Allow Odoo password login" -> an employee who never activated cannot log in with the Odoo password (expected).
  Result: PASS 2026-10-02

- [x] **Step 6 — Old app build stays compatible**
  Old app build (1.23.1) against 2.45.1 with the flag on: password login still works.
  Result: PASS 2026-10-02

- [x] **Step 7 — New app against a pre-2.45 connector (legacy mode)**
  1.25.0 against a tenant still on connector < 2.45: no new UI (no "Forgot password?", no Your devices / Change password tiles, no forget-this-phone sheet); password login works; Face ID enable + relaunch + Face ID replay (password mode) works. "Activate with an invite" -> submit shows "Activation is not available for your company yet. Ask HR."
  Result: PASS 2026-10-02

- [ ] **Step 8 — In-place upgrade from 1.24 with a live session and password-mode Face ID**
  Install 1.24 build, sign in, enable Face ID (password mode). Upgrade in place to 1.25.0 -> still signed in, no re-login. Sign out, sign in with the password -> Face ID migrates to the refresh token (sign out again, Face ID signs in via `/auth/refresh`).
  Result: SKIP 2026-10-02: no 1.24 build exists (1.23.1 -> 1.25.0)

- [x] **Step 9 — "Sign out and forget this phone"**
  Profile -> LOGOUT -> "Sign out and forget this phone" -> login screen, Face ID button gone; phone no longer listed under Your devices on the other phone. Repeat in airplane mode: still signs out locally and shows "Could not reach the server. Remove this phone later under Your devices."
  Result: PASS 2026-10-02

- [x] **Step 10 — Change password revokes the other phone**
  Phone A: Profile -> Change password -> success. Phone B (same account) relaunch -> login screen (its refresh token is revoked; Face ID shows "Please sign in again.").
  Result: PASS 2026-10-02

- [x] **Step 11 — Lockout message**
  Enter a wrong password repeatedly until the connector locks the account -> "Too many attempts. Try again in N minutes." (also from Profile -> Face ID enable password check).
  Result: PASS 2026-10-02

- [x] **Step 12 — Forgot password**
  Login screen -> "Forgot password?" (visible only after this company's connector has answered once with identity support) -> email -> neutral confirmation. On omnihrdemo (no mail server) the reply is `mail_not_configured` -> "Password reset by email is not available here. Ask HR to reset it for you."
  Result: PASS 2026-10-02 (Willy: branded reset email with inline QR -> Samsung activated)

- [x] **Step 13 — Mixed-case Odoo login signs in (C2)**
  An employee whose Odoo login has capitals (e.g. `Budi.Santoso@Maxhill.com`) signs in by typing it exactly as stored -> home (the app no longer lowercases the /login body).
  Result: PASS 2026-10-02

- [x] **Step 14 — Another person signs in on a Face ID phone (C1)**
  Phone with Face ID on for employee A: sign out, sign in with employee B's password -> sign out -> Face ID still signs in as A (B's login did not take over A's Face ID).
  Result: PASS 2026-10-02

- [x] **Step 15 — Phone-only employee (2.47)**
  In Odoo, pick an employee with no work email and a mobile number. App Access shows the
  phone as App login. Send app invite -> scan the QR on the Android -> the App login field
  shows the digits; change it to a username -> Activate -> home. Log out, log in with the
  username. In Odoo the App login now shows the username and the chatter says
  "App login changed to ... at activation."
  Result: PASS 2026-10-02

- [x] **Step 16 — Reset password / new phone**
  On an active employee, "Reset password / new phone" -> dialog titled
  "App password reset / new phone" -> scan on a phone -> activation -> home.
  Result: PASS 2026-10-02

## Invite QR: cameras and in-app scanner (connector 2.48.0, app 1.25.0+86)

Spec: connector repo `docs/superpowers/specs/2026-09-30-invite-https-link-and-scanner-design.md`.
Invites are now `https://<tenant>/omni/activate#c=…&t=…&l=…`. Live tracker:
https://claude.ai/artifact/MAwXbrNT6ejKcT2Jt4pY6a

- [x] **Step 17 — Samsung camera opens the invite** (retest of Step 15 with Budi): camera offers a link,
  page "Activate Omni HR" opens, Open Omni HR -> prefilled activation screen.
  Result: PASS 2026-10-02
- [x] **Step 18 — OPPO and iPhone cameras** -> page -> Open Omni HR -> prefilled activation.
  Result: PASS 2026-10-02
- [x] **Step 19 — In-app scanner from the invite screen** (Scan invite QR above the company code):
  haptic, scanner closes, prefilled activation; Enter code instead returns to the code fields.
  Result: PASS 2026-10-02
- [x] **Step 20 — In-app scanner from the login field** (QR icon): prefilled activation;
  Enter code instead -> manual activation.
  Result: PASS 2026-10-02
- [x] **Step 21 — Wrong QR and torch**: "This is not an Omni HR invite QR." ~3 s, scanning continues; torch toggles.
  Result: PASS 2026-10-02
- [x] **Step 22 — Camera refused, then allowed**: card "Camera access is off. Turn it on in Settings,
  or enter the code instead." with Open Settings / Enter code; after allowing, the camera starts.
  Result: PASS 2026-10-02
- [x] **Step 23 — Phone without Omni HR** (optional): page button -> Google Play.
  Result: PASS 2026-10-02
- [ ] **Step 24 — Older omnihr:// QR** still activates via in-app scanner and iPhone camera.
  Result: SKIP 2026-10-02: no pre-2.48 omnihr:// QR left to scan
- [x] **Step 25 — Fresh install**: uninstall, install build 86; Scan invite QR on the company-code
  screen -> prefilled activation without typing a code.
  Result: PASS 2026-10-02
- [x] **Step 26 — Leave the scanner and come back** (Home, return): preview live, still reads QRs.
  Result: PASS 2026-10-02
- [x] **Step 27 — Printed invite slip**: Samsung camera and in-app scanner both read the denser QR.
  Result: PASS 2026-10-02

Before retesting on a phone that had Face ID enabled on an earlier build: turn Face ID off and on once in Profile, because the old build keyed it to the typed login.
