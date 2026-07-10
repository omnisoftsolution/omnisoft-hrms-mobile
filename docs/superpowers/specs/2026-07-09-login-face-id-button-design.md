# Design — Face ID / Touch ID sign-in button on the login screen

**Date:** 2026-07-09
**Status:** Approved (brainstormed with user)
**Repo:** omnisoft-hrms-mobile (Flutter)
**Branch:** `feat/security-privacy-card` (same branch as the Security & Privacy card work — both ship together)

## Problem

The user enabled Face ID login, tapped **Log out**, and found **no way to sign back in with Face ID** — the login screen only offered email + password. He wants a Face ID / Touch ID button beside the Sign In button.

## Root cause (not a bug — a deliberate behavior now in the way)

1. **Manual logout deliberately wipes the credential.** `SessionService.signOut()` = `clearSession()` + `onLogout?.call()`; `main.dart` wires `onLogout` → `BiometricAuthService.disable()` (wipes the stored login/password + the enabled flag). Profile "Log out", Delete account, and company-forced-re-login all call `signOut()`. This was a **critical** finding in the biometric-login review: a deliberate sign-out should fully sign the user out with no stored password left behind. Involuntary 30-day expiry uses `clearSession()` (keeps the credential).
2. **Biometric UI only renders when a credential is stored.** In `login_screen.dart`, `_resolveBiometric()` sets `capable = bio.isEnabled ? … : false`, and `build()` shows the full-screen `BiometricLoginPanel` only when `_bioResolved && _capable && !_forcePassword`. After a manual logout `isEnabled` is false → no biometric UI at all.
3. **The biometric UI is a full-screen "Welcome back" panel that replaces the form**, not a button beside Sign In.

So the user hit the "forget" path, and the feature was scoped to auto-expiry only.

## Decisions (user-approved)

- **Log out remembers Face ID** (reverses decision #1 for the Log-out case only). Delete account and company-forced-re-login still wipe it; involuntary expiry unchanged.
- **Unified login screen**: password form always visible, with a **"Sign in with Face ID / Touch ID"** button under SIGN IN when a credential is stored; the separate full-screen panel is removed.
- **Auto-prompt** Face ID when the login screen opens for a returning user — **except immediately after a manual Log out** (don't re-prompt the user into the thing they just left).
- Ships on the **same `feat/security-privacy-card` branch** as the card relocation.

## Design

### A. "Log out" keeps the credential

- **`profile_screen.dart` `_logout`**: change `session.signOut()` → `session.clearSession()`. The server-token revocation (`api.logout()`) still runs before it; only the local-credential wipe stops. Result: `bio.isEnabled` stays true, secrets remain.
- **All other sign-out sites are left untouched**: Delete account (`delete_account_screen.dart`) and company-forced-re-login keep calling `signOut()` (both must wipe the credential — account deletion, and the old-tenant login must not replay against a new company). Involuntary expiry (`main.dart` `onInvalidSession`) stays `clearSession()`. Only the single Profile "Log out" call changes.
- **`session_logout_test.dart`**: flip the assertions to the new truth — Profile logout **keeps** the credential (`onLogout` NOT fired / biometric stays enabled); Delete account **clears** it (`onLogout` fired / biometric disabled). Keep a test proving the `signOut()`→`onLogout` wiring still works for the sites that use it.

### B. Unified login screen with a Face ID button + guarded auto-prompt

- **Remove** the full-screen `BiometricLoginPanel` branch in `login_screen.dart build()`; the password form (Scaffold with "Sign In" AppBar) always renders. Delete `lib/widgets/biometric_login_panel.dart` and `test/widgets/biometric_login_panel_test.dart` (no longer used). Remove the now-dead `_forcePassword` field and the panel import.
- **Add a secondary button** directly under the SIGN IN `PrimaryButton`, shown only when `_bioResolved && _capable` (a credential is stored + device capable):
  - Label: `"Sign in with ${biometricLabel(_bioKind)}"` (e.g. "Sign in with Face ID").
  - Icon: face for faceId/face, fingerprint otherwise.
  - Style: secondary (outlined / lower-emphasis than SIGN IN) so it doesn't compete with the primary action.
  - `onPressed` → the existing `_biometricLogin()`.
  - Disabled while `_submitting`.
- **Auto-prompt**: keep `_resolveBiometric()` auto-calling `_biometricLogin()` when capable — **gated on a new widget flag**. Add `LoginScreen({this.autoPromptBiometric = true})`. `_resolveBiometric()` only auto-triggers when `widget.autoPromptBiometric` is true. The **Profile logout** navigation constructs `LoginScreen(autoPromptBiometric: false)`; every other construction site keeps the default `true` (cold start, expiry). The button is always available regardless of the flag.
- The password form stays fully usable at all times (type email/password + SIGN IN), so a user can always sign in as someone else even with a stored credential.

### Interaction summary

| Entry to login screen | Credential stored? | Face ID button | Auto-prompt |
|---|---|---|---|
| App cold start / session expiry | yes | shown | yes |
| App cold start / session expiry | no | hidden | no |
| Just tapped Log out | yes (now kept) | shown | **no** |
| Just deleted account | no (wiped) | hidden | no |

## Edge cases

- **Stored password no longer valid** (changed on server): biometric replay fails with `invalid_credentials` → existing `fromBiometric` logic disables biometric + shows "password changed" → button disappears, password form remains. Unchanged.
- **Biometric prompt cancelled / lockout**: existing `_biometricLogin` handling (lockout message, otherwise silent) — the button and password form remain usable. Unchanged.
- **Company change while a credential is stored**: company-forced-re-login wipes the credential (`signOut()`), so no stale cross-tenant replay.
- **Device biometric removed at OS level**: `isDeviceCapable()` returns false → button hidden even if `isEnabled` (same guard as today).

## Testing (TDD)

- **`session_logout_test.dart`** (rewrite): Profile-style logout via `clearSession()` keeps the biometric credential enabled; Delete-account-style `signOut()` fires `onLogout` and disables it.
- **`login_screen` widget tests** (new, using `FakeBiometricGate` + a fake/real `SessionService` and `BiometricAuthService` providers):
  - Face ID button is shown when a credential is stored (`isEnabled` + capable) and hidden when not.
  - Tapping the button invokes the biometric retrieve path.
  - With `autoPromptBiometric: true` and a stored credential, the biometric prompt is triggered on open; with `autoPromptBiometric: false`, it is NOT auto-triggered (button still present).
- Existing `BiometricAuthService` unit tests stay green (its logic is untouched).

## Out of scope

- No change to `BiometricAuthService` enable/disable/retrieve logic, the opt-in sheet (flow A), or the Security & Privacy card.
- No server / connector changes; no version bump in this spec (handled at TestFlight/release time).
- The deferred hardware-biometric-binding hardening remains deferred.

## Rollout

- Continue on `feat/security-privacy-card`; TDD per task; `flutter analyze` + full suite green before requesting review.
- Do **not** merge without the user's explicit permission (he device-tests personally).
- After implementation: bump the build number and `cd ios && fastlane beta` so the user can test the Face ID button + logout-remembers behavior on TestFlight (alongside the card relocation).
