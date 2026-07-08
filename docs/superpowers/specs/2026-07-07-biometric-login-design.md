# Biometric Login (Face / Fingerprint) — Design

**Date:** 2026-07-07
**Repo:** omnisoft-hrms-mobile (Flutter, `omni_hr`)
**Status:** Design approved — ready for implementation plan
**Backend:** No connector change. Client-only.

## 1. Problem & Goal

The app already keeps a user signed in without re-typing a password: on login the
backend issues a 30-day bearer session token (`omni.mobile.session`,
`_SESSION_TTL = timedelta(days=30)`), the app stores it in the Keystore/Keychain
(`access_token`), and on launch it reuses the token and routes straight to Home.
The password is only needed again when that session **lapses** — after ~30 days,
after a server-side revoke, or after explicit logout. There is no refresh-token
flow, so at that point the user must re-type email + password.

**Goal:** at that re-login moment, let the user authenticate with Face ID /
Touch ID / fingerprint instead of typing their password. This is a **convenience
feature at session expiry**, not an app-open lock — a still-valid session keeps
opening straight to Home with no prompt.

**Non-goal:** locking the app behind biometrics on every launch (that was
considered and explicitly deferred).

## 2. Chosen Approach

**Store the credential on-device (client-only), biometric-gated, replay the
existing `/login`.** No backend change.

Decision record (from brainstorming):
- **Goal** = convenience at expiry (not app-lock).
- **Credential source** = store the password on-device (not a backend refresh
  token). Chosen for zero backend change and fastest ship. Accepted trade-off:
  the real password lives on the device (encrypted + biometric-gated), and a
  server-side password change silently breaks biometric login until the next
  manual login (handled gracefully — see §7).
- **Explicit logout clears the stored credential** (logout means logout).
- **Biometric mechanism** = `local_auth` app-level gate shipped now; OS-level
  key binding (auto-invalidate on device biometric-enrollment change) is a
  documented fast-follow, not in this version.

## 3. Architecture

Client-only. One new service beside the existing `SessionService`.

### 3.1 `BiometricAuthService` (new, `ChangeNotifier`)

`lib/services/biometric_auth_service.dart`. Wraps `local_auth` +
`flutter_secure_storage`. Single responsibility: manage the "biometric login"
capability and the stored credential. It does **not** perform the network login
itself — it hands a verified credential back to the caller, which uses the
existing `OmniMobileApi.login(...)`.

Public surface (interface, not final signatures):

| Method | Purpose |
|---|---|
| `Future<bool> isDeviceCapable()` | Hardware present AND at least one biometric enrolled (`local_auth.canCheckBiometrics && isDeviceSupported && getAvailableBiometrics().isNotEmpty`). Feature is gated off below Android API 23. |
| `Future<BiometricLabel> deviceBiometricLabel()` | Which biometric to name in UI: Face ID / Touch ID / fingerprint / face / generic "biometric". Derived from `getAvailableBiometrics()` + platform. |
| `bool get isEnabled` | Fast, non-secret check (reads the `biometric_enabled` prefs flag). Drives what the UI renders without unlocking anything. |
| `Future<void> enable({required String login, required String password})` | Runs a biometric prompt once to confirm; on success writes the credential to secure storage and sets the prefs flag; `notifyListeners`. |
| `Future<void> disable()` | Deletes the secure credential + clears the flag; `notifyListeners`. Idempotent. |
| `Future<BiometricCredential?> authenticateAndRetrieve()` | Shows the biometric prompt; on success returns the stored `(login, password)`; on cancel/lockout/failure returns `null` with a typed reason. |
| `Future<bool> hasDismissedOptIn()` / `markOptInDismissed()` | So the post-login opt-in is offered once, not on every login. |

### 3.2 Storage

| Key | Store | Secret? | Notes |
|---|---|---|---|
| `biometric_login` | flutter_secure_storage (Keystore/Keychain) | yes | employee login/email |
| `biometric_password` | flutter_secure_storage | yes | password, replayed to `/login` |
| `biometric_enabled` | SharedPreferences | no | UI gate flag; presence ≠ credential validity |
| `biometric_optin_dismissed` | SharedPreferences | no | suppress the post-login opt-in nag |
| `biometric_display_name` | SharedPreferences | no | first name for the "Welcome back" greeting; written at enable-time so it survives `clearSession()` (which clears `employee_name`) |

Secure keys reuse the existing default `FlutterSecureStorage` config already used
for `access_token` (Android EncryptedSharedPreferences w/ Keystore master key,
iOS Keychain). Distinct key names — never mixed with `access_token`.

### 3.3 Wiring

- `main.dart`: add `ChangeNotifierProvider(create: (_) => BiometricAuthService())`
  to the existing `MultiProvider`.
- `login_screen.dart`: (a) after a successful manual login, offer the opt-in
  (§5); (b) when the screen is shown and `isEnabled`, render the biometric
  variant (§6) with auto-prompt and a "Use password instead" escape.
- Settings screen (`company_settings_screen.dart` or a small new Security
  section): the on/off toggle (§7 Flow C in the design; §8 here).
- `SessionService.clearSession()` vs `logout()`: **explicit `logout()` also calls
  `BiometricAuthService.disable()`**; involuntary `clearSession()` (invalid
  session / expiry) does NOT — that is the case biometric login exists for.

## 4. Auth model recap (why no backend change is needed)

- `/login` body: `{ login, password, device_id, app_version }` →
  returns `{ access_token, expires_at, user, employee }`.
- Biometric login = biometric prompt → retrieve stored `(login, password)` →
  call the **same** `OmniMobileApi.login(...)` → on success `SessionService`
  stores the fresh 30-day token exactly as a manual login does.
- Server sees an ordinary `/login`. Nothing on the connector needs to know
  biometrics were involved.

## 5. Flow A — Enrollment / opt-in

Trigger: immediately after a **successful manual password login**, when
`isDeviceCapable()` is true AND `isEnabled` is false AND `hasDismissedOptIn()`
is false.

Modal bottom-sheet (design-system: teal `#006971`, Inter, pill button, 24px
radius card):

```
        [ biometric icon ]
     Faster sign-in next time
  Use Face ID to log back in when your
  session expires, instead of typing
  your password.
       [   Enable Face ID   ]     (teal pill)
       [      Not now        ]     (text button)
```

- **Enable** → `enable(login, password)` using the credentials just used → on the
  in-method biometric confirmation success, store the credential and also record
  the non-secret `biometric_display_name` from the current session's
  `employee_name` (for the Flow B greeting), then toast "Face ID login enabled."
  On biometric cancel/failure, sheet stays; no credential stored.
- **Not now** → `markOptInDismissed()`; never auto-shown again. Still reachable
  via Settings.
- All "Face ID" text is replaced by the device-appropriate label.

## 6. Flow B — Biometric re-login

Trigger: the app would show the login screen (session gone) AND `isEnabled`.

```
          [ Company logo ]
            Acme Pte Ltd
        Welcome back, Budi           (name from last session prefs)
   ┌──────────────────────────┐
   │  ⊚  Log in with Face ID   │     (prominent; auto-prompts on open)
   └──────────────────────────┘
          Use password instead        (always available)
```

- On screen open, auto-invoke `authenticateAndRetrieve()` (one tap saved).
- **Success** → replay `OmniMobileApi.login(...)` → `SessionService.saveSession`
  → Home.
- **Use password instead** → today's email+password form (unchanged). Does not
  disable biometric.
- Cancel / lockout → stay on the biometric screen; user retries or switches to
  password.

The company logo/name come from the SaaS-routing prefs that survive
`clearSession()` (`company_name`, `company_logo_b64`). The greeting name comes
from the non-secret `biometric_display_name` written at enable-time (note:
`employee_name` is cleared by `clearSession()`, so it cannot be used here). No
secret is read to render this screen. If `biometric_display_name` is absent, the
greeting degrades to a plain "Welcome back".

## 7. Edge cases

| Situation | Behavior |
|---|---|
| No biometric hardware / none enrolled | Opt-in never shown; biometric variant never shown; behaves exactly as today |
| Biometric later removed from device | Biometric button hidden; fall back to password; credential cleared on next detect |
| **Explicit "Log out"** | `logout()` → `disable()` clears the credential; re-enter password + re-opt-in |
| Involuntary expiry / server revoke (`invalid_session`) | Credential kept → biometric login offered |
| OS biometric lockout (too many fails) | Typed lockout reason → "Too many attempts — use your password" → password form |
| Password changed server-side | `/login` replay returns invalid credentials → show "Your password has changed — please log in with your password" → `disable()` → password form → re-offer opt-in after next manual login |
| App backgrounded during prompt | `local_auth` returns a cancel-class result; no state change; screen still offers retry |

**Security note (accepted, documented):** the baseline uses `local_auth` as an
app-level gate. It does NOT auto-invalidate the stored password when the device's
enrolled biometrics change (e.g., a new fingerprint added). OS-level key binding
(Android `setUserAuthenticationRequired` / iOS `.biometryCurrentSet`) closes that
gap but is less reliable across Android OEMs; scheduled as a fast-follow, not in
this version.

## 8. Flow C — Settings toggle

A **Security** row in the settings/company screen:

```
Security
  Face ID login              [ ●━ ]
     Log in with Face ID when your session expires.
```

- **On** → `enable(...)` — needs the current credential. Since the password is
  not held in memory post-login, enabling from Settings prompts the user to
  confirm their password once (a small inline confirm), then stores it. (Simpler
  alternative considered: only allow enabling via the post-login opt-in and make
  Settings a disable-only control — decide in the plan; default is the
  password-confirm-on-enable above.)
- **Off** → `disable()` immediately deletes the credential.
- Row hidden entirely when `isDeviceCapable()` is false.

## 9. Platform changes

- `pubspec.yaml`: add `local_auth` (latest 2.x).
- **iOS** (`ios/Runner/Info.plist`): add `NSFaceIDUsageDescription`
  ("Use Face ID to log in to Omni HR."). Deployment target 15.5 already fine.
- **Android**:
  - `AndroidManifest.xml`: add `<uses-permission android:name="android.permission.USE_BIOMETRIC"/>`.
  - `MainActivity.kt`: change base class `FlutterActivity` →
    `FlutterFragmentActivity` (required by `local_auth`'s BiometricPrompt).
  - `minSdk`: biometric needs API 23+. Effective minSdk is ~21; gate the feature
    off below 23 via `isDeviceCapable()` (do not force a global minSdk bump in
    this change unless the plan decides to).

## 10. Testing

TDD, per repo convention (`flutter test`, no ink_sparkle noise in this repo).

- `BiometricAuthService` unit tests with a mocked `local_auth` + in-memory secure
  storage: enable → credential stored + flag set; disable → cleared; capability
  gating; opt-in dismissal persistence; `authenticateAndRetrieve` success →
  returns credential; cancel/lockout → null + typed reason.
- Credential-lifecycle tests: `logout()` clears credential; `clearSession()`
  (involuntary) does NOT; stale-credential path clears on replay failure.
- Label-derivation tests (Face ID vs Touch ID vs fingerprint vs generic).
- Widget tests: login screen renders biometric variant when enabled +
  capable; "Use password instead" reveals the password form; opt-in sheet shows
  once.
- Manual on-device verification (user): Samsung fingerprint + an iOS Face ID
  device — enable, expire/logout-involuntary, biometric re-login, password-change
  fallback, explicit-logout clears.

## 11. Scope

**In:** `BiometricAuthService`, Flows A/B/C, adaptive labels, edge-case handling,
iOS/Android config, tests.

**Out (documented follow-ups):** app-open security lock; backend refresh token;
OS-level biometric key binding (enrollment-change invalidation); PIN fallback;
per-tenant admin enable/disable.
