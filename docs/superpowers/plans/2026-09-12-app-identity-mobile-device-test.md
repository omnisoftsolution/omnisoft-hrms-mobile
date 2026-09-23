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
  Odoo App Access -> revoke phone B -> phone B relaunch -> login screen shows "Please sign in again."
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
