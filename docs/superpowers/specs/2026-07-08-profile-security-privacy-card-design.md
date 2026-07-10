# Design — Move biometric login toggle to a "Security & Privacy" card on Profile

**Date:** 2026-07-08
**Status:** Approved (brainstormed with user)
**Repo:** omnisoft-hrms-mobile (Flutter)
**Branch:** `feat/security-privacy-card` (off master `a33d643`)

## Problem

The biometric-login toggle (Face ID / Touch ID / fingerprint re-login at session
expiry) currently lives in **Company Settings** → "Security" section, reached via a
gear icon on the Profile screen (`profile_screen.dart` AppBar → `CompanySettingsScreen`).

This placement is wrong on three counts:

1. **Semantic mismatch.** "Company Settings" is org-level configuration (SaaS URL,
   company code, switch/clear company, diagnostics: URLs/db/version). A *personal*
   login preference is out of place there and hard to discover (two taps deep, behind
   a gear labelled "Company settings").
2. **Pre-login leak (concrete defect).** In `company_settings_screen.dart` the Security
   block is gated only on `_bioCapable` (device *has* biometric hardware), **not** on
   being logged in. But `CompanySettingsScreen` is also opened from the **login screen**
   (`login_screen.dart:266`) to enter/switch a company code before signing in. Result:
   a *"Log in with Face ID when your session expires"* switch can render to a user who
   is **not logged in yet** — semantically broken.
3. **Discoverability.** A security feature users are meant to opt into is buried.

## Decision

Move the toggle to a new **"Security & Privacy"** card on the Profile screen (a
post-login destination), alongside the Privacy Policy link. Remove the "Security" and
"Legal" sections from Company Settings, reverting it to company/diagnostics only. This
also removes the pre-login leak (the switch no longer renders in the pre-login path).

Chosen over: (a) a bare ungrouped `SwitchListTile` on Profile (what the sibling ikptb
app does — reads as an afterthought, doesn't match omni-hr's card system), and (c) a
dedicated Security sub-screen (extra tap; not worth it for one control today).

## Design

### New widget: `SecurityPrivacyCard`

A self-contained `StatefulWidget` (keeps `ProfileScreen` a `StatelessWidget`). It owns
the biometric capability lookup and toggle logic **moved verbatim** from
`company_settings_screen` — the biometric feature's behavior does not change; only its
location does.

Styled to match the existing Face Enrollment / Payslip cards: `Card` → `Padding(20)` →
`Column` with a header row (shield icon + "Security & Privacy" title), then rows.

**Contents (in order):**

1. **Biometric login toggle** — rendered **only** when `_bioCapable` is true.
   `SwitchListTile`:
   - title: `"{biometricLabel(kind)} login"` (e.g. "Face ID login")
   - subtitle: `"Log in with {biometricLabel(kind)} when your session expires."`
   - value: `context.watch<BiometricAuthService>().isEnabled`
   - onChanged: relocated `_toggleBiometric`:
     - **disable** → `bio.disable()` immediately.
     - **enable** → "Confirm your password" dialog (obscured field) → if non-empty,
       `bio.enable(login: session.userLogin, password: pw, displayName: session.employeeName)`
       → success snackbar `"{label} login enabled"`.
2. **Privacy Policy** link row → opens `AppConstants.privacyPolicyUrl` (moved from the
   old Company Settings "Legal" section). Styled like the existing `_legalLinkTile`.

**Capability init:** on `initState`, resolve `_bioCapable` + `_bioKind` via
`BiometricAuthService.isDeviceCapable()` / `deviceBiometricKind()` (the same `_resolveBio`
logic that exists in Company Settings today), guarded by `mounted`.

**No-biometric device:** the card still renders, showing just the header + Privacy Policy
row (Privacy Policy is always relevant, and is the Apple biometric-data disclosure).

**Dependencies:** `BiometricAuthService` (Provider), `SessionService` (Provider, for
`userLogin` + `employeeName`), `AppConstants.privacyPolicyUrl`, `biometricLabel` (from
`biometric_optin_sheet.dart`). The enable flow requires a logged-in session — guaranteed
on the Profile screen.

### Profile screen change (`profile_screen.dart`)

Insert `const SecurityPrivacyCard()` into the `ListView`, **just above the LOGOUT
button** (the account/security housekeeping zone next to the exit actions):

```
 Hero → Company card → Identity → Payslips → Approvers → Face Enrollment
 → [Security & Privacy]   ← NEW
 → LOGOUT
 → Delete my account (unchanged, in-app flow)
```

### Company Settings changes (`company_settings_screen.dart`)

- Remove the "Security" section (the biometric `SwitchListTile` block) and its now-unused
  members: `_resolveBio`, `_toggleBiometric`, `_promptPassword`, `_bioCapable`,
  `_bioKind`, and the `_resolveBio()` call in `initState`, plus biometric-related imports
  (`biometric_auth_service.dart`, `biometric_types.dart`, `biometricLabel` import).
- Remove the entire "Legal" section (Privacy Policy + Account Deletion link tiles). If
  `_legalLinkTile` is now unused here, remove or relocate it (the card provides its own
  Privacy Policy row).
- Net: Company Settings = SaaS URL / company code / switch / clear / diagnostics only.

### Account deletion (unchanged)

The in-app **"Delete my account"** text button stays at the Profile bottom (→
`DeleteAccountScreen`, the real, store-compliant flow). The **external**
`AppConstants.accountDeletionUrl` link is **dropped** (it duplicated the in-app flow).
`AppConstants.accountDeletionUrl` (a public static const) will become unused after the
Legal section is removed; **leave it in place** — an unused public const triggers no
analyzer warning, and it may be reused later.

## Edge cases

- **Not logged in:** N/A — `SecurityPrivacyCard` only appears on the post-login Profile
  screen. (This is the whole point of the move.)
- **Biometric enrolled then removed at OS level:** unchanged from today — existing
  `BiometricAuthService` behavior governs; out of scope for this move.
- **Password prompt cancelled / empty:** enable aborts, toggle stays off (existing logic).
- **Enable fails (wrong password / network):** `bio.enable` returns false, no snackbar —
  existing behavior, unchanged.

## Testing (TDD)

- **`SecurityPrivacyCard` widget tests** (using existing `BiometricGate`/service seams so
  no device is needed):
  - toggle rendered when device capable; **hidden** when not capable (card still shows
    Privacy Policy row).
  - toggling **off** calls `BiometricAuthService.disable()`.
  - toggling **on** opens the "Confirm your password" dialog.
  - Privacy Policy row present and tappable.
- **Company Settings regression test:** the biometric `SwitchListTile` is **no longer**
  rendered in `CompanySettingsScreen` (guards against the pre-login leak returning).
- **Existing `BiometricAuthService` unit tests** stay green (logic relocated, not changed).

## Out of scope

- No change to the biometric enable/disable/replay logic, the opt-in sheet (flow A), or
  the login panel (flow B).
- No server / connector changes (client-only).
- No version bump in this spec (handled at release time, not implementation).
- The deferred security-hardening item (hardware biometric binding) is unrelated and
  remains deferred.

## Rollout

- Feature branch `feat/security-privacy-card`; TDD per task; `flutter analyze` + full
  suite green before requesting review.
- Do **not** merge without the user's explicit permission (he device-tests personally).
- Purely UI relocation → verify on-device that: the toggle now appears under Profile →
  Security & Privacy; enable/disable still works; Company Settings no longer shows the
  switch (incl. the pre-login path from the login screen).
