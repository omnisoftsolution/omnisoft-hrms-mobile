# Device test — pending Willy (omnihrdemo, connector 2.45.1)

See `omnisoft-hrms-odoo-connector/docs/superpowers/plans/2026-09-12-app-identity-mobile.md` §Task 7 Step 3 for the full plan-level context this device test belongs to.

## Preconditions

- [ ] `pod install` run on this Mac (ios/ pods regenerated for the app_links bump) before building.
- [ ] Flutter >= 3.44 on the build machine (this Mac has 3.44.6).
- [ ] Connector 2.45.1 installed on omnihrdemo.
- [ ] HR has sent the invite from the employee's App Access tab (Odoo) for each test employee/phone used below.
- [ ] The tenant setting "Email a code when a new phone signs in" requires an outgoing mail server — omnihrdemo has none configured, so Step 4 below needs a mail server set up first.

## Steps

- [ ] **Step 1 — Phone A: fresh install + QR activation + Face ID**
  Fresh install, scan QR from Odoo -> activation -> home. Enable Face ID. Kill app, reopen -> Face ID -> home.
  Result:

- [ ] **Step 2 — Phone B: email link activation, same employee**
  Open the invite email link from Mail -> activation with the same employee -> both phones listed under Your devices.
  Result:

- [ ] **Step 3 — Revoke phone B from Odoo**
  Odoo App Access -> revoke phone B -> phone B relaunch -> `/me` returns `invalid_session` -> login screen with NO message. Tap Face ID -> "Please sign in again." appears and Face ID turns off.
  Result:

- [ ] **Step 4 — New-device email code (needs mail server)**
  Turn on "Email a code when a new phone signs in" -> phone C password login -> code dialog -> code from email -> home.
  Result:

- [ ] **Step 5 — Odoo password login disabled for a never-activated employee**
  Turn off "Allow Odoo password login" -> an employee who never activated cannot log in with the Odoo password (expected).
  Result:

- [ ] **Step 6 — Old app build stays compatible**
  Old app build (1.23.1) against 2.45.1 with the flag on: password login still works.
  Result:

- [ ] **Step 7 — New app against a pre-2.45 connector (legacy mode)**
  1.25.0 against a tenant still on connector < 2.45: no new UI (no "Forgot password?", no Your devices / Change password tiles, no forget-this-phone sheet); password login works; Face ID enable + relaunch + Face ID replay (password mode) works. "Activate with an invite" -> submit shows "Activation is not available for your company yet. Ask HR."
  Result:

- [ ] **Step 8 — In-place upgrade from 1.24 with a live session and password-mode Face ID**
  Install 1.24 build, sign in, enable Face ID (password mode). Upgrade in place to 1.25.0 -> still signed in, no re-login. Sign out, sign in with the password -> Face ID migrates to the refresh token (sign out again, Face ID signs in via `/auth/refresh`).
  Result:

- [ ] **Step 9 — "Sign out and forget this phone"**
  Profile -> LOGOUT -> "Sign out and forget this phone" -> login screen, Face ID button gone; phone no longer listed under Your devices on the other phone. Repeat in airplane mode: still signs out locally and shows "Could not reach the server. Remove this phone later under Your devices."
  Result:

- [ ] **Step 10 — Change password revokes the other phone**
  Phone A: Profile -> Change password -> success. Phone B (same account) relaunch -> login screen (its refresh token is revoked; Face ID shows "Please sign in again.").
  Result:

- [ ] **Step 11 — Lockout message**
  Enter a wrong password repeatedly until the connector locks the account -> "Too many attempts. Try again in N minutes." (also from Profile -> Face ID enable password check).
  Result:

- [ ] **Step 12 — Forgot password**
  Login screen -> "Forgot password?" (visible only after this company's connector has answered once with identity support) -> email -> neutral confirmation. On omnihrdemo (no mail server) the reply is `mail_not_configured` -> "Password reset by email is not available here. Ask HR to reset it for you."
  Result:

- [ ] **Step 13 — Mixed-case Odoo login signs in (C2)**
  An employee whose Odoo login has capitals (e.g. `Budi.Santoso@Maxhill.com`) signs in by typing it exactly as stored -> home (the app no longer lowercases the /login body).
  Result:

- [ ] **Step 14 — Another person signs in on a Face ID phone (C1)**
  Phone with Face ID on for employee A: sign out, sign in with employee B's password -> sign out -> Face ID still signs in as A (B's login did not take over A's Face ID).
  Result:
