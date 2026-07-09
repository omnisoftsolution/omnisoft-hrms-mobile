# Face ID — align to IKPTB (verify-before-enable + button-only)

**Date:** 2026-07-09
**Branch:** `feat/security-privacy-card` (this work lands on the same branch as the Security & Privacy card + Face ID button; merges with the rest)
**Scope:** Flutter client only. No connector / server change.

## Problem

On-device testing of TestFlight 1.21.0(75) surfaced a real bug in the biometric-login **enable** path:

1. User enables Face ID from the Profile → "Security & Privacy" card.
2. The "Confirm your password" dialog accepts **any non-empty string** — it is never checked against the server.
3. That unverified password is written to secure storage.
4. Later, Face ID re-login replays the stored (wrong) password against `/login` → server rejects it → the app shows *"Your password has changed — please log in with your password."* and silently disables Face ID.

Root cause: `BiometricAuthService.enable()` performs only a local OS biometric prompt and then writes `login`+`password` to `flutter_secure_storage` with **zero server verification**; its caller `security_privacy_card.dart` `_toggleBiometric` only guards `password.isEmpty`.

The user's directive: **"follow exactly like IKPTB way handling face id."**

## Reference: how IKPTB handles it (`ikptb-app-new`)

IKPTB and omni-hr are architecturally near-identical: both store the plaintext `login`+`password` in `flutter_secure_storage` (default options), gate the read behind an OS biometric prompt, and replay the stored credential against the login endpoint. Both self-heal on a server `invalid_credentials` at replay (wipe the credential, fall back to the password form). Both keep the credential on logout and wipe it on disable/delete.

The **one** thing IKPTB does that omni-hr does not: its Profile toggle (`biometric_toggle.dart`) **validates the password against the server before storing**:

```dart
// IKPTB biometric_toggle.dart _onChanged(true)
final password = await _askPassword();
if (password == null || password.isEmpty) return;
await ref.read(authRepositoryProvider).login(widget.memberEmail, password); // server verifies
await ref.read(credentialStoreProvider).enable(email: ..., password: password); // then store
// on InvalidCredentialsException → SnackBar('Kata sandi salah.') — NOT stored
```

A second divergence (a UX choice, not a bug): **IKPTB never auto-prompts** biometric — the user always taps the "Sign in with Face ID" button. omni-hr currently auto-prompts on app open. Per the user's decision (2026-07-09), omni-hr will switch to **button-only** to match IKPTB.

## Design

### Change 1 — Verify the password before enabling (the bug fix)

**File: `lib/widgets/security_privacy_card.dart`**

- Add an injected verifier to the widget:
  ```dart
  enum PasswordCheck { ok, wrongPassword, error }
  typedef PasswordVerifier = Future<PasswordCheck> Function(String password);
  ```
  Constructor gains `required PasswordVerifier verifyPassword`. Keeping it injected (rather than reading `SessionService`/building the API inside the widget) preserves the card's unit-testability — the existing rationale for injecting `login`/`displayName`.
- `_toggleBiometric(true)` becomes: prompt password → if empty, return → `await widget.verifyPassword(password)`:
  - `PasswordCheck.wrongPassword` → SnackBar *"Incorrect password — {biometricLabel} not enabled."* → return (nothing stored).
  - `PasswordCheck.error` → SnackBar *"Couldn't verify — check your connection."* → return (nothing stored).
  - `PasswordCheck.ok` → `await bio.enable(login: widget.login, password: password, displayName: widget.displayName)` (unchanged call) → on success, existing "{label} login enabled" snackbar.
- Add a `_busy` flag that disables the switch while verification is in flight (prevents double-toggle; gives a hint that work is happening).
- The `SwitchListTile.value` stays bound to `context.watch<BiometricAuthService>().isEnabled`, so the switch remains visually **off** throughout verification and only flips on once `enable()` succeeds. No manual revert needed, no wrong-state flash.

**Deliberate deviation from IKPTB (flagged for review):** omni-hr's `BiometricAuthService.enable()` keeps its existing OS biometric "confirm your identity" prompt at enable time. IKPTB's *profile toggle* has none (though IKPTB's *login-screen* enroll does). Rationale for keeping it: it confirms the user's Face ID actually works before they rely on it, keeps omni-hr's two enable paths (card toggle + post-login opt-in sheet) consistent, and requires **zero change to `BiometricAuthService`** (smaller, safer diff). The bug is fully fixed by the server verification regardless of this prompt. Can be dropped later if exact IKPTB parity is preferred.

**File: `lib/services/session_service.dart`**

- Extract the login-response → session mapping (currently inline in `login_screen.dart` `_performLogin`, ~lines 126–156) into a reusable method:
  ```dart
  Future<void> saveLoginResponse(Map<String, dynamic> res) async { ... }
  ```
  It parses `res['access_token']`, `res['expires_at']`, `res['user']`, `res['employee']` and calls `saveSession(...)` with all the fields. No behavior change — pure extraction so both the login screen and the card-verifier reuse one mapper.

**File: `lib/screens/login/login_screen.dart`**

- `_performLogin` switches its inline `saveSession(...)` block to `await session.saveLoginResponse(res);` (dedup). Everything else in `_performLogin` unchanged.

**File: `lib/screens/profile/profile_screen.dart`**

- Construct the card with the production verifier:
  ```dart
  SecurityPrivacyCard(
    login: session.userLogin,
    displayName: session.employeeName,
    verifyPassword: (password) async {
      final api = OmniMobileApi(baseUrl: session.clientUrl, db: session.clientDb, token: '');
      final deviceId = await DeviceService().getDeviceId();
      try {
        final res = await api.login(
          login: session.userLogin, password: password,
          deviceId: deviceId, appVersion: AppConstants.appVersion);
        await session.saveLoginResponse(res); // refresh session with fresh token
        return PasswordCheck.ok;
      } on ApiException catch (e) {
        return e.errorCode == 'invalid_credentials'
            ? PasswordCheck.wrongPassword : PasswordCheck.error;
      } catch (_) {
        return PasswordCheck.error;
      }
    },
  )
  ```
  Verifying against `/login` refreshes the current session token on success — mirroring IKPTB (which re-saves its bearer token on verify) so a server that rotates/invalidates tokens on new login cannot strand the current session.

### Change 2 — Button-only Face ID (remove auto-prompt), exactly like IKPTB

**File: `lib/screens/login/login_screen.dart`**

- Remove the `autoPromptBiometric` constructor parameter.
- In `_resolveBiometric`, keep the capability/kind resolution (needed to show the "Sign in with Face ID" button) but **remove** the trailing auto-trigger:
  ```dart
  // DELETE:
  if (_capable && widget.autoPromptBiometric) { _biometricLogin(); }
  ```
- `_biometricLogin()` is retained unchanged — now invoked only by the button's `onPressed`.

**Call sites** (drop the parameter; all become plain `const LoginScreen()`):
- `lib/main.dart:152` — already `const LoginScreen()` (the 30-day-expiry path; now shows the button instead of auto-prompting).
- `lib/screens/profile/profile_screen.dart:719` — change `const LoginScreen(autoPromptBiometric: false)` → `const LoginScreen()`. The `clearSession()` (keeps credential) at logout is unchanged.
- `lib/screens/profile/delete_account_screen.dart:84`, `lib/screens/company_code/company_code_screen.dart:56`, `lib/screens/login/company_settings_screen.dart:113` — already `const LoginScreen()`, no edit beyond the param removal compiling.

This removes the "suppress auto-prompt after logout" machinery from Feature 2 and eliminates the latent delete-account/company-change fire-and-forget-`disable()` auto-prompt race noted in the biometric backlog. Net simplification.

### Unchanged (already identical to IKPTB)

- Secure-storage of plaintext `login`+`password` (default `flutter_secure_storage` options).
- Replay flow: button → OS biometric gate → read stored credential → replay `/login` → fresh token via `saveSession`.
- Self-heal on server `invalid_credentials` at replay: `bio.disable()` + password fallback message.
- Session semantics: Profile logout `clearSession()` keeps the credential; delete-account + company-change `signOut()` wipe it; involuntary `invalid_session` `clearSession()` keeps it.
- Post-login opt-in sheet path (`_maybeOfferBiometricOptIn`) — already safe (reuses a just-succeeded login); left as-is.

## Testing (TDD — tests written before implementation)

**`test/widgets/security_privacy_card_test.dart`** (update + add; card now requires a `verifyPassword`):
- Wrong password: verifier returns `wrongPassword` → error snackbar shown, `enable()` NOT called, switch stays off.
- Network error: verifier returns `error` → error snackbar, nothing stored.
- Correct password: verifier returns `ok` → `enable()` called with the typed password, success snackbar.
- Empty password (Cancel / empty): verifier NOT called, `enable()` NOT called.

**`test/services/session_service_*` (new or existing session test file):**
- `saveLoginResponse(res)` maps token/expiry/user/employee fields into the persisted session correctly (round-trip via getters).

**`test/screens/login_screen_biometric_test.dart`** (update):
- On open with a stored credential + capable device: biometric is **NOT** auto-invoked (no auto-prompt); the "Sign in with Face ID" button is shown.
- Tapping the button triggers `authenticateAndRetrieve` → replay login.
- Replay `invalid_credentials` → `bio.disable()` called + password-fallback error shown (existing behavior, still green).

**`test/services/session_logout_test.dart`** (unchanged, must stay green):
- `clearSession()` keeps the biometric credential; `signOut()` wipes it.

**Full suite** `flutter test` green + `flutter analyze` clean before requesting review.

## Out of scope

- No connector/server change; no dedicated "verify password" endpoint (verification reuses `/login`, as IKPTB does).
- Post-login opt-in **sheet** is not converted to IKPTB's inline login-screen checkbox (functionally equivalent and already safe).
- No change to storage hardening (accessibility / EncryptedSharedPreferences) — IKPTB uses defaults too; tracked separately.
- Android Play build (+74) is a post-merge release step, not part of this spec.
