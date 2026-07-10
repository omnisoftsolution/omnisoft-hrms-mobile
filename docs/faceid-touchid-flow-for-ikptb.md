# Face ID / Touch ID login flow — recommended pattern (hand-off to IKPTB)

**From:** Omni HR Mobile (Flutter)
**To:** IKPTB app (`ikptb-app-new`, Flutter + Riverpod)
**Date:** 2026-07-10

This document describes the biometric-login flow now shipping in Omni HR Mobile
and the specific, small changes to bring the IKPTB app up to the same behaviour.
The two apps already share the same architecture — IKPTB is close; this is a
polish + one-correctness change, not a rewrite.

---

## 1. The architecture both apps already share

- The biometric secret is the member's **plaintext email/login + password**, kept
  in `flutter_secure_storage`, replayed against the normal `/login` endpoint. No
  separate biometric token.
- Biometric (`local_auth`) is an **app-level gate**: `authenticate()` returns
  pass/fail; only on pass does the app read the stored credential and replay login.
- **Log out keeps** the stored credential (so the user can sign back in with
  Face ID); **disabling** biometric — or a **server rejection at replay** — wipes it.
- Replay against `/login` **self-heals**: if the server returns
  `invalid_credentials`/`InvalidCredentialsException`, the app clears the stored
  credential, disables biometric, and falls back to the password form.

IKPTB files that implement this: `credential_store.dart`, `biometric_service.dart`,
`providers.dart` (`AuthController.loginWithSavedCredentials`), `auth_repository.dart`,
`login_screen.dart`, `biometric_toggle.dart` (Profil › Keamanan).

---

## 2. The five rules that make the flow correct and pleasant

### Rule 1 — NEVER store a password the server hasn't accepted *(the important one)*

When enabling biometric from the profile toggle, the user types their password
into a confirm dialog. **Verify that password against the server before storing
anything.** If you skip this, a mistyped password gets saved, Face ID later
replays it, the server rejects it, and the app disables biometric with a
misleading "your password changed" message — the user never knows they simply
fat-fingered the enable dialog.

> IKPTB status: **already correct** in `biometric_toggle.dart` — it calls
> `authRepository.login(email, password)` and only calls `credentialStore.enable(...)`
> on success, showing "Kata sandi salah." on `InvalidCredentialsException`. Keep this.
> (This was the bug we hit in Omni HR — our card used to store blind. Fixed now.)

### Rule 2 — Confirm the biometric actually works *before* the user relies on it

After the password is verified and before (or as part of) storing, run one
`bio.authenticate()` prompt. This proves the user's Face ID / fingerprint is
enrolled and working on this device, so they don't discover at next login that it
doesn't. Do it on **both** enable entry points (the login-screen enroll AND the
profile toggle) so behaviour is consistent.

> IKPTB status: the **login-screen inline enroll** already does this
> (`bio.authenticate(reason: 'Aktifkan ...')` before `store.enable`). The **profile
> toggle does NOT.** → **Add the same `bio.authenticate()` confirm to
> `biometric_toggle._onChanged` after the `login()` verification succeeds and
> before `credentialStore.enable(...)`.** If the confirm is cancelled/fails, do
> not enable (and do not surface an error — the user chose to back out).

### Rule 3 — Refresh the session with the token the verify-login returned

The verify step in Rule 1 is a real `/login` call, so it issues a fresh token.
**Persist that token** (update the current session) instead of discarding it. This
avoids any chance that a server which rotates tokens on login could strand the
current session, and it's a free session-lifetime extension.

> IKPTB status: **already correct** — `authRepository.login()` writes the new token
> to `TokenStorage`. Keep it. (Confirm no long-lived API client caches the old
> token; build the client with the current token per request.)

### Rule 4 — Distinct, honest feedback on every enable outcome

- Wrong password → "Incorrect password — {Face ID/Touch ID} not enabled." (IKPTB:
  "Kata sandi salah.")
- Network / any other error → a **different** message: "Couldn't verify — check
  your connection." (do NOT reuse the wrong-password copy for a network failure).
- While the verify network call is in flight, **disable the toggle** (a `busy`
  flag) so the user can't double-tap or toggle mid-request.
- Keep the switch visually **off** until the credential is actually stored — bind
  its value to the real "is-enabled" state, not to the tap. On any failure it then
  stays off with no manual revert.

> IKPTB status: has the wrong-password SnackBar; **add the distinct network-error
> message, the `busy`/disabled state during verify, and make the switch value
> reflect the stored state** rather than the optimistic toggle.

### Rule 5 — Button-only sign-in; never auto-prompt

On the login screen, show an explicit **"Sign in with {Face ID/Touch ID}"** button
and let the user tap it. **Do not** auto-fire the biometric prompt when the screen
opens — an unexpected Face ID sheet on launch is jarring and, right after a manual
log-out, feels like the app is dragging the user back into what they just left.
The password form stays visible so fallback is always one tap away.

> IKPTB status: **already button-only** (never auto-prompts). Keep it.
> (Omni HR used to auto-prompt; we removed it to match this behaviour.)

---

## 3. Concrete IKPTB change list (summary)

| Rule | IKPTB today | Action |
|---|---|---|
| 1 — verify before store | ✅ done (`biometric_toggle`) | keep |
| 2 — biometric confirm at enable | ⚠️ login-screen only, not profile toggle | **add `bio.authenticate()` to `biometric_toggle._onChanged` after `login()` succeeds** |
| 3 — persist refreshed token | ✅ done (`auth_repository.login` writes token) | keep |
| 4 — distinct feedback + busy + reactive switch | ⚠️ partial | **add network-error copy, `busy` disable, bind switch to stored state** |
| 5 — button-only, no auto-prompt | ✅ done | keep |

Net: IKPTB needs **Rule 2** (one `authenticate()` call) and **Rule 4** (feedback
polish). Everything else already matches.

---

## 4. Reference — the Omni HR enable flow (adapt to IKPTB's Riverpod)

Profile "Security & Privacy" toggle, turning biometric **on**:

```
1. Show "Confirm your password" dialog → get password (empty/cancel ⇒ stop, no-op).
2. busy = true (toggle disabled).
3. Verify: POST /login with { current login, password }.
     - InvalidCredentialsException      → SnackBar "Incorrect password …"; busy=false; stop.
     - network / any other error        → SnackBar "Couldn't verify — check your connection."; busy=false; stop.
     - success                          → persist the returned session/token (refresh).
4. Biometric confirm: bio.authenticate("Confirm your identity to enable …").
     - not success                      → stop (nothing stored).
     - success                          → store { login, password }, set enabled=true.
5. busy = false; SnackBar "{Face ID/Touch ID} login enabled".
   (The switch value is bound to the stored "enabled" state, so it flips on only here.)
```

Login screen (sign back in):

```
- Password form always visible.
- If a credential is stored AND device capable: show "Sign in with {label}" button.
- NO auto-prompt on open.
- Button tap → bio.authenticate() → read stored credential → replay POST /login.
      - success                         → routed to home.
      - server invalid_credentials      → wipe credential, disable biometric,
                                           show "Your password has changed — please
                                           log in with your password." (button hidden).
      - cancel / fail / network         → stay on the login screen; retry or use password.
```

Logout keeps the credential (so the button shows next time); delete-account and
"switch company" wipe it.

---

*Questions: ask the Omni HR Mobile maintainer. The Omni HR implementation lives in
`lib/widgets/security_privacy_card.dart`, `lib/screens/login/login_screen.dart`,
`lib/services/biometric_auth_service.dart`, and `lib/services/session_service.dart`.*
