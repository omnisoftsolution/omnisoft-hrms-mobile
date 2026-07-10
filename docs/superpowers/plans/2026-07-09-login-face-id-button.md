# Face ID Sign-In Button on the Login Screen — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the user a "Sign in with Face ID / Touch ID" button on the login screen and make it available after a manual Log out (by keeping the credential across logout).

**Architecture:** Two coordinated changes. (1) The login screen becomes one unified screen — the password form always shows, with a secondary Face ID button under SIGN IN when a credential is stored, plus a guarded auto-prompt; the separate full-screen `BiometricLoginPanel` is removed. (2) Profile "Log out" switches from `SessionService.signOut()` (which fires `onLogout` → `BiometricAuthService.disable()`) to `clearSession()`, so the credential survives; Delete account and company-change still use `signOut()`.

**Tech Stack:** Flutter, Provider, `local_auth` behind the injectable `BiometricGate` seam, `flutter_secure_storage` + `shared_preferences` (mockable in tests).

## Global Constraints

- Client-only. NO connector / server changes. NO version bump in this work.
- NO change to `BiometricAuthService` enable/disable/retrieve logic, the opt-in sheet, or the Security & Privacy card.
- Only the single **Profile "Log out"** call changes from `signOut()` → `clearSession()`. Delete account (`delete_account_screen.dart:75`) and company-change (`company_settings_screen.dart:110`) keep `signOut()`. Involuntary expiry (`main.dart` `onInvalidSession`) is unchanged.
- Login screen: the password form is ALWAYS visible; the Face ID button shows ONLY when `_bioResolved && _capable` (a credential is stored + device capable); auto-prompt is gated on the new `LoginScreen({autoPromptBiometric = true})` flag and is set `false` only by the Profile-logout navigation.
- `biometricLabel(kind)` produces the button copy (e.g. "Face ID", "Touch ID", "fingerprint"). On the non-iOS test host, `BiometricType.fingerprint` → `BiometricKind.fingerprint` → label `"fingerprint"`; `BiometricType.face` → `BiometricKind.face` → `"face unlock"`. Tests use `fingerprint` for a deterministic label.
- Match existing widget-test style: `FakeBiometricGate`, `FlutterSecureStorage.setMockInitialValues({})` + `SharedPreferences.setMockInitialValues({...})` in `setUp`.

---

### Task 1: Login screen — Face ID button + guarded auto-prompt; remove the full-screen panel

**Files:**
- Modify: `lib/screens/login/login_screen.dart`
- Delete: `lib/widgets/biometric_login_panel.dart`, `test/widgets/biometric_login_panel_test.dart`
- Test: `test/screens/login_screen_biometric_test.dart` (new)

**Interfaces:**
- Consumes: `BiometricAuthService` (Provider) — `isEnabled`, `isDeviceCapable()`, `deviceBiometricKind()`, `authenticateAndRetrieve()`; `SessionService` (Provider); `biometricLabel(BiometricKind)` (already imported via `biometric_optin_sheet.dart`); `AppTheme` (`core/theme.dart`).
- Produces: `LoginScreen({Key? key, bool autoPromptBiometric = true})` — the new named param that Task 2 sets to `false` from the Profile-logout navigation.

- [ ] **Step 1: Write the failing tests**

Create `test/screens/login_screen_biometric_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:omni_hr/services/biometric_auth_service.dart';
import 'package:omni_hr/services/biometric_types.dart';
import 'package:omni_hr/services/session_service.dart';
import 'package:omni_hr/screens/login/login_screen.dart';

/// Scriptable gate. Default outcome `canceled` so the biometric path
/// stops before any network login — we only assert the prompt fired.
class FakeBiometricGate implements BiometricGate {
  bool available;
  List<BiometricType> types;
  BiometricAuthOutcome nextOutcome;
  int authCalls = 0;
  FakeBiometricGate({
    this.available = true,
    this.types = const [BiometricType.fingerprint],
    this.nextOutcome = BiometricAuthOutcome.canceled,
  });
  @override
  Future<bool> isAvailable() async => available;
  @override
  Future<List<BiometricType>> enrolledTypes() async => types;
  @override
  Future<BiometricAuthOutcome> authenticate(String reason) async {
    authCalls++;
    return nextOutcome;
  }
}

Widget _host(BiometricAuthService bio, {required bool autoPrompt}) => MultiProvider(
      providers: [
        ChangeNotifierProvider<SessionService>.value(value: SessionService()),
        ChangeNotifierProvider<BiometricAuthService>.value(value: bio),
      ],
      child: MaterialApp(home: LoginScreen(autoPromptBiometric: autoPrompt)),
    );

Future<BiometricAuthService> _loadedBio(FakeBiometricGate gate) async {
  final bio = BiometricAuthService(gate: gate);
  await bio.load();
  return bio;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({'biometric_enabled': true});
  });

  testWidgets('shows the Face ID button when a credential is stored + capable, '
      'and does not auto-prompt when suppressed', (tester) async {
    final gate = FakeBiometricGate(available: true);
    final bio = await _loadedBio(gate);
    await tester.pumpWidget(_host(bio, autoPrompt: false));
    await tester.pumpAndSettle();
    expect(find.text('Sign in with fingerprint'), findsOneWidget);
    expect(gate.authCalls, 0);
  });

  testWidgets('hides the Face ID button when no credential is stored',
      (tester) async {
    SharedPreferences.setMockInitialValues({}); // biometric_enabled absent
    final gate = FakeBiometricGate(available: true);
    final bio = await _loadedBio(gate);
    await tester.pumpWidget(_host(bio, autoPrompt: false));
    await tester.pumpAndSettle();
    expect(find.textContaining('Sign in with'), findsNothing);
  });

  testWidgets('auto-prompts biometric on open when autoPromptBiometric is true',
      (tester) async {
    final gate = FakeBiometricGate(available: true);
    final bio = await _loadedBio(gate);
    await tester.pumpWidget(_host(bio, autoPrompt: true));
    await tester.pumpAndSettle();
    expect(gate.authCalls, 1);
  });

  testWidgets('does not auto-prompt when suppressed, but tapping the button does',
      (tester) async {
    final gate = FakeBiometricGate(available: true);
    final bio = await _loadedBio(gate);
    await tester.pumpWidget(_host(bio, autoPrompt: false));
    await tester.pumpAndSettle();
    expect(gate.authCalls, 0);
    await tester.ensureVisible(find.text('Sign in with fingerprint'));
    await tester.tap(find.text('Sign in with fingerprint'));
    await tester.pumpAndSettle();
    expect(gate.authCalls, 1);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/screens/login_screen_biometric_test.dart`
Expected: FAIL — `LoginScreen` has no `autoPromptBiometric` named parameter (compile error), and no "Sign in with fingerprint" button exists.

- [ ] **Step 3: Add the `autoPromptBiometric` param + gate the auto-prompt**

In `lib/screens/login/login_screen.dart`:

Replace the widget declaration:
```dart
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
```
with:
```dart
class LoginScreen extends StatefulWidget {
  /// Whether to automatically show the biometric prompt on open (when a
  /// credential is stored). Set to false right after a manual Log out so
  /// the user isn't immediately re-prompted into what they just left.
  final bool autoPromptBiometric;
  const LoginScreen({super.key, this.autoPromptBiometric = true});
```

In `_resolveBiometric()`, replace:
```dart
    // Auto-prompt once the panel is shown.
    if (_capable && !_forcePassword) {
      _biometricLogin();
    }
```
with:
```dart
    // Auto-prompt once, unless suppressed (e.g. right after a manual logout).
    if (_capable && widget.autoPromptBiometric) {
      _biometricLogin();
    }
```

- [ ] **Step 4: Remove `_forcePassword`, remove the panel branch, add the button**

In `login_screen.dart`:

Delete the field (line ~43):
```dart
  bool _forcePassword = false; // user tapped "Use password instead"
```

In `_biometricLogin()`, replace the lockout branch:
```dart
    if (res.outcome == BiometricAuthOutcome.lockedOut) {
      setState(() {
        _forcePassword = true;
        _error = 'Too many attempts — please log in with your password.';
      });
    }
```
with:
```dart
    if (res.outcome == BiometricAuthOutcome.lockedOut) {
      setState(() {
        _error = 'Too many attempts — please log in with your password.';
      });
    }
```

In `build()`, delete the entire full-screen panel branch:
```dart
    if (_bioResolved && _capable && !_forcePassword) {
      final bio = context.read<BiometricAuthService>();
      return Scaffold(
        body: SafeArea(
          child: BiometricLoginPanel(
            kind: _bioKind,
            greetingName: bio.displayName,
            companyName: session.companyName,
            companyLogoB64: session.companyLogoB64,
            busy: _submitting,
            onBiometric: _biometricLogin,
            onUsePassword: () => setState(() => _forcePassword = true),
          ),
        ),
      );
    }
```
(so `build()` always falls through to the password-form `Scaffold`).

In the form, immediately AFTER the SIGN IN `PrimaryButton(...)` block:
```dart
                      PrimaryButton(
                        label: 'SIGN IN',
                        loading: _submitting,
                        onPressed: _submitting ? null : _login,
                      ),
```
insert:
```dart
                      if (_bioResolved && _capable) ...[
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _submitting ? null : _biometricLogin,
                            icon: Icon(_bioKind == BiometricKind.faceId ||
                                    _bioKind == BiometricKind.face
                                ? Icons.face
                                : Icons.fingerprint),
                            label: Text(
                                'Sign in with ${biometricLabel(_bioKind)}'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppTheme.primary,
                              side: BorderSide(
                                  color:
                                      AppTheme.primary.withValues(alpha: 0.5)),
                              shape: const StadiumBorder(),
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                        ),
                      ],
```

Remove the now-unused import (line ~13):
```dart
import '../../widgets/biometric_login_panel.dart';
```

- [ ] **Step 5: Delete the unused panel widget + its test**

```bash
git rm lib/widgets/biometric_login_panel.dart test/widgets/biometric_login_panel_test.dart
```

- [ ] **Step 6: Run the tests + analyze**

Run: `flutter test test/screens/login_screen_biometric_test.dart`
Expected: PASS (4 tests).

Run: `flutter analyze`
Expected: "No issues found!" (confirms no dangling `_forcePassword` / `BiometricLoginPanel` references).

- [ ] **Step 7: Commit**

```bash
git add lib/screens/login/login_screen.dart test/screens/login_screen_biometric_test.dart
git commit -m "feat: Face ID button on login screen + guarded auto-prompt; drop full-screen panel"
```

---

### Task 2: "Log out" keeps the Face ID credential

**Files:**
- Modify: `lib/screens/profile/profile_screen.dart` (the `_logout` method, ~lines 703-713)
- Test: `test/services/session_logout_test.dart` (add two invariant tests)

**Interfaces:**
- Consumes: `LoginScreen(autoPromptBiometric: false)` from Task 1; `SessionService.clearSession()` / `signOut()`; `BiometricAuthService.disable()` / `enable()` / `isEnabled`.
- Produces: nothing new.

- [ ] **Step 1: Add the invariant tests that lock the logout contract**

Append to `test/services/session_logout_test.dart` (inside `main()`, after the existing tests). These wire `onLogout → biometric.disable` exactly as `main.dart` does, and assert which teardown method preserves vs wipes the biometric credential:

```dart
  test('clearSession() keeps the biometric credential (onLogout not fired)',
      () async {
    SharedPreferences.setMockInitialValues({'biometric_enabled': true});
    final session = SessionService();
    await session.load();
    final bio = BiometricAuthService();
    await bio.load();
    session.onLogout = () => bio.disable();
    expect(bio.isEnabled, isTrue);

    await session.clearSession(); // what Profile "Log out" now calls
    expect(bio.isEnabled, isTrue); // credential survives a manual logout
  });

  test('signOut() wipes the biometric credential (onLogout fired)', () async {
    SharedPreferences.setMockInitialValues({'biometric_enabled': true});
    final session = SessionService();
    await session.load();
    final bio = BiometricAuthService();
    await bio.load();
    // onLogout fires disable() fire-and-forget (void callback); capture the
    // future so the assertion is deterministic rather than delay-based.
    Future<void>? disableFuture;
    session.onLogout = () => disableFuture = bio.disable();
    expect(bio.isEnabled, isTrue);

    await session.signOut(); // what Delete account / company-change call
    await disableFuture; // await the fire-and-forget disable()
    expect(bio.isEnabled, isFalse);
  });
```

Add the import at the top of the file:
```dart
import 'package:omni_hr/services/biometric_auth_service.dart';
```

- [ ] **Step 2: Run the tests**

Run: `flutter test test/services/session_logout_test.dart`
Expected: PASS. (These pass without any production change — `SessionService` is unchanged. They are regression guards: they lock the contract the call-site change relies on, so a future refactor of `signOut`/`clearSession` can't silently break "logout keeps Face ID". Note in the commit that they are characterization/regression tests, not RED-first.)

- [ ] **Step 3: Change the Profile "Log out" call site**

In `lib/screens/profile/profile_screen.dart` `_logout(...)`, replace:
```dart
    await session.signOut();
    if (context.mounted) {
      // Root navigator: tear down the entire HomeShell (including all
      // tab Navigators and the persistent bottom nav). The tab-scoped
      // Navigator.of(context) here would only clear this tab's stack.
      Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
      );
    }
```
with:
```dart
    // clearSession (not signOut) so a deliberate Log out ends the session
    // but KEEPS the biometric credential — the user can sign back in with
    // Face ID. Delete account / company-change still use signOut().
    await session.clearSession();
    if (context.mounted) {
      // Root navigator: tear down the entire HomeShell (including all
      // tab Navigators and the persistent bottom nav). The tab-scoped
      // Navigator.of(context) here would only clear this tab's stack.
      // autoPromptBiometric: false so we don't immediately re-prompt the
      // user into the session they just left — the button is still there.
      Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
        MaterialPageRoute(
            builder: (_) => const LoginScreen(autoPromptBiometric: false)),
        (_) => false,
      );
    }
```

(Leave `delete_account_screen.dart:75` `signOut()` and its `LoginScreen()` at `:84` unchanged — deletion wipes the credential, so its login screen has nothing to prompt.)

- [ ] **Step 4: Run analyze + full suite**

Run: `flutter analyze`
Expected: "No issues found!"

Run: `flutter test`
Expected: all green (existing suite + the 4 login-screen tests from Task 1 + the 2 new invariant tests).

- [ ] **Step 5: Commit**

```bash
git add lib/screens/profile/profile_screen.dart test/services/session_logout_test.dart
git commit -m "feat: Log out keeps the Face ID credential (clearSession, no auto-prompt); Delete account still wipes it"
```

---

## Post-implementation verification (before requesting review)

- [ ] `flutter analyze` → "No issues found!"
- [ ] `flutter test` → all green.
- [ ] On-device (user, via TestFlight): enable Face ID → tap **Log out** → the login screen shows a "Sign in with Face ID / Touch ID" button under SIGN IN and does NOT auto-prompt; tapping it (or reopening the app) logs you in with Face ID. **Delete account** still forces password + hides the button.
- [ ] Do NOT merge without the user's explicit permission.
