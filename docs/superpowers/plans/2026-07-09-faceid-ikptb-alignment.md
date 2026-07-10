# Face ID — align to IKPTB Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the biometric-enable bug (a wrong password is stored unverified) by verifying the password against the server before enabling, and switch Face ID to button-only (no auto-prompt) — matching how IKPTB handles Face ID.

**Architecture:** Client-only Flutter change on branch `feat/security-privacy-card`. The Profile "Security & Privacy" card verifies the typed password against `/login` (via an injected callback wired in `profile_screen`) before storing the biometric credential; on success it refreshes the session with the server's fresh token. The login screen loses its auto-prompt and relies solely on the "Sign in with Face ID" button. The `BiometricAuthService`, secure storage, replay flow, and session-clear semantics are unchanged.

**Tech Stack:** Flutter, `provider`, `local_auth ^2.3.0`, `flutter_secure_storage ^9.2.2`, `shared_preferences`.

## Global Constraints

- Branch: `feat/security-privacy-card`. Do NOT merge — the user merges personally after device-testing.
- Client-only. No connector / Odoo change. Verification reuses the existing `/login` endpoint.
- No change to `BiometricAuthService` (the enable-time OS biometric "confirm identity" prompt is deliberately kept).
- UI copy: no emoji. Error snackbars use `AppTheme.error` background.
- Read any file before editing it.
- After each task: `flutter test` all green and `flutter analyze` clean before committing.
- Test device (manual, later): user's Samsung `flutter run -d R8YY921VY1A`.

---

### Task 1: Extract `SessionService.saveLoginResponse(res)` and reuse it in the login screen

Pure refactor (no behavior change) so both the login flow and the new card-verifier persist the login response through one mapper.

**Files:**
- Modify: `lib/services/session_service.dart` (add method near `saveSession`, ~line 305)
- Modify: `lib/screens/login/login_screen.dart:126-160` (`_performLogin` — replace inline mapping)
- Test: `test/services/session_save_login_response_test.dart` (create)

**Interfaces:**
- Produces: `Future<void> SessionService.saveLoginResponse(Map<String, dynamic> res)` — parses `res['access_token']`, `res['expires_at']`, `res['user']`, `res['employee']` and calls `saveSession(...)`. Consumed by Task 2's verifier and by `_performLogin`.

- [ ] **Step 1: Write the failing test**

Create `test/services/session_save_login_response_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:omni_hr/services/session_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  test('saveLoginResponse maps token, user and employee fields', () async {
    final session = SessionService();
    await session.saveLoginResponse({
      'access_token': 'tok123',
      'expires_at': '2026-08-01T00:00:00',
      'user': {'id': 7, 'login': 'budi@acme.sg', 'name': 'Budi'},
      'employee': {
        'id': 42,
        'name': 'Budi Santoso',
        'job_title': 'Engineer',
        'company_name': 'Acme',
      },
    });

    expect(session.accessToken, 'tok123');
    expect(session.userId, 7);
    expect(session.userLogin, 'budi@acme.sg');
    expect(session.userName, 'Budi');
    expect(session.employeeId, 42);
    expect(session.employeeName, 'Budi Santoso');
    expect(session.employeeJobTitle, 'Engineer');
    expect(session.employeeCompanyName, 'Acme');
    expect(session.expiresAt, DateTime.parse('2026-08-01T00:00:00'));
  });

  test('saveLoginResponse tolerates missing user/employee maps', () async {
    final session = SessionService();
    await session.saveLoginResponse({'access_token': 'tok'});
    expect(session.accessToken, 'tok');
    expect(session.userLogin, '');
    expect(session.employeeId, 0);
    expect(session.expiresAt, isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/session_save_login_response_test.dart`
Expected: FAIL — `The method 'saveLoginResponse' isn't defined for the type 'SessionService'`.

- [ ] **Step 3: Add `saveLoginResponse` to `SessionService`**

In `lib/services/session_service.dart`, add this method immediately above `Future<void> saveSession({` (~line 305):

```dart
  /// Persist a `/login` response. Extracts the token/user/employee fields
  /// from [res] and forwards them to [saveSession]. Shared by the login
  /// screen and the Security & Privacy card's password re-verification.
  Future<void> saveLoginResponse(Map<String, dynamic> res) async {
    final user = res['user'] as Map<String, dynamic>? ?? {};
    final employee = res['employee'] as Map<String, dynamic>? ?? {};
    final expiresAtStr = res['expires_at']?.toString() ?? '';
    await saveSession(
      accessToken: res['access_token']?.toString() ?? '',
      expiresAt:
          expiresAtStr.isNotEmpty ? DateTime.tryParse(expiresAtStr) : null,
      userId: (user['id'] as num?)?.toInt() ?? 0,
      userLogin: user['login']?.toString() ?? '',
      userName: user['name']?.toString() ?? '',
      employeeId: (employee['id'] as num?)?.toInt() ?? 0,
      employeeName: employee['name']?.toString() ?? '',
      employeeAvatarB64: employee['avatar_b64']?.toString() ?? '',
      employeeJobTitle: employee['job_title']?.toString() ?? '',
      employeeJobPosition: employee['job_position']?.toString() ?? '',
      employeeDepartment: employee['department_name']?.toString() ?? '',
      employeeManager: employee['manager_name']?.toString() ?? '',
      employeeWorkEmail: employee['work_email']?.toString() ?? '',
      employeeWorkPhone: employee['work_phone']?.toString() ?? '',
      employeeCompanyName: employee['company_name']?.toString() ?? '',
      employeeCompanyLogoB64: employee['company_logo_b64']?.toString() ?? '',
      employeeHrApprover: employee['hr_approver_name']?.toString() ?? '',
      employeeTimeOffApprover:
          employee['time_off_approver_name']?.toString() ?? '',
      employeeAttendanceApprover:
          employee['attendance_approver_name']?.toString() ?? '',
      employeeExpenseApprover:
          employee['expense_approver_name']?.toString() ?? '',
    );
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/services/session_save_login_response_test.dart`
Expected: PASS (both tests).

- [ ] **Step 5: Refactor `_performLogin` to use the new mapper**

In `lib/screens/login/login_screen.dart`, replace the contiguous block (lines ~126-159) that contains: the `final user`/`final employee`/`final expiresAtStr` locals, the whole `await session.saveSession(...)` call, its trailing `if (!mounted) return;`, and the `await _maybeOfferBiometricOptIn(loginText, password, employee['name']?.toString() ?? '');` call — with:

```dart
      await session.saveLoginResponse(res);
      if (!mounted) return;
      await _maybeOfferBiometricOptIn(loginText, password, session.employeeName);
```

(The `final res = await api.login(...)` line just above stays, as does the original `if (!mounted) return;` on the line *after* the opt-in call, right before `Navigator.of(context).pushAndRemoveUntil(...)`. This removes the now-unused `user`/`employee`/`expiresAtStr` locals; `_maybeOfferBiometricOptIn`'s display-name arg switches from `employee['name']` to `session.employeeName`, which `saveLoginResponse` just populated.)

- [ ] **Step 6: Run the full suite + analyze**

Run: `flutter test` — Expected: all green (existing login-flow tests still pass; the mapping behavior is unchanged).
Run: `flutter analyze` — Expected: no issues (no unused-variable warnings from the removed locals).

- [ ] **Step 7: Commit**

```bash
git add lib/services/session_service.dart lib/screens/login/login_screen.dart test/services/session_save_login_response_test.dart
git commit -m "refactor: extract SessionService.saveLoginResponse; reuse in login"
```

---

### Task 2: Verify password against the server before enabling (bug fix)

The card gains an injected `verifyPassword` callback; `profile_screen` wires it to a real `/login` verification that refreshes the session on success.

**Files:**
- Modify: `lib/widgets/security_privacy_card.dart` (add `PasswordCheck` enum + `PasswordVerifier` typedef + `verifyPassword` field; rework `_toggleBiometric`; add `_busy`)
- Modify: `lib/screens/profile/profile_screen.dart` (add `device_service` import; pass `verifyPassword` to the card)
- Test: `test/widgets/security_privacy_card_test.dart` (update host + add cases)

**Interfaces:**
- Consumes: `SessionService.saveLoginResponse` (Task 1); `OmniMobileApi.login({required String login, required String password, String? deviceId, String? appVersion}) → Future<Map<String, dynamic>>`; `ApiException.errorCode` (String); `DeviceService().getDeviceId() → Future<String>`; `AppConstants.appVersion`.
- Produces: `enum PasswordCheck { ok, wrongPassword, error }`; `typedef PasswordVerifier = Future<PasswordCheck> Function(String password)`; `SecurityPrivacyCard({required String login, required String displayName, required PasswordVerifier verifyPassword})`.

- [ ] **Step 1: Write the failing tests**

Replace the whole body of `test/widgets/security_privacy_card_test.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:omni_hr/services/biometric_auth_service.dart';
import 'package:omni_hr/services/biometric_types.dart';
import 'package:omni_hr/widgets/security_privacy_card.dart';

/// Scriptable BiometricGate — no platform channel.
class FakeBiometricGate implements BiometricGate {
  bool available;
  List<BiometricType> types;
  BiometricAuthOutcome nextOutcome;
  FakeBiometricGate({
    this.available = true,
    this.types = const [BiometricType.fingerprint],
    this.nextOutcome = BiometricAuthOutcome.success,
  });
  @override
  Future<bool> isAvailable() async => available;
  @override
  Future<List<BiometricType>> enrolledTypes() async => types;
  @override
  Future<BiometricAuthOutcome> authenticate(String reason) async => nextOutcome;
}

Widget _host(BiometricAuthService svc, {PasswordVerifier? verify}) => MaterialApp(
      home: Scaffold(
        body: ChangeNotifierProvider<BiometricAuthService>.value(
          value: svc,
          child: SecurityPrivacyCard(
            login: 'budi@acme.sg',
            displayName: 'Budi',
            verifyPassword: verify ?? (_) async => PasswordCheck.ok,
          ),
        ),
      ),
    );

Future<void> _tapToggleAndConfirm(WidgetTester tester) async {
  await tester.tap(find.byType(SwitchListTile));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), 'whatever');
  await tester.tap(find.text('Confirm'));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('shows biometric toggle + Privacy Policy when device capable',
      (tester) async {
    final svc = BiometricAuthService(gate: FakeBiometricGate(available: true));
    await tester.pumpWidget(_host(svc));
    await tester.pumpAndSettle();
    expect(find.text('Security & Privacy'), findsOneWidget);
    expect(find.byType(SwitchListTile), findsOneWidget);
    expect(find.text('Privacy Policy'), findsOneWidget);
  });

  testWidgets('hides toggle but keeps Privacy Policy when not capable',
      (tester) async {
    final svc = BiometricAuthService(gate: FakeBiometricGate(available: false));
    await tester.pumpWidget(_host(svc));
    await tester.pumpAndSettle();
    expect(find.byType(SwitchListTile), findsNothing);
    expect(find.text('Privacy Policy'), findsOneWidget);
  });

  testWidgets('toggling on opens the "Confirm your password" dialog',
      (tester) async {
    final svc = BiometricAuthService(gate: FakeBiometricGate(available: true));
    await svc.load();
    await tester.pumpWidget(_host(svc));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(find.text('Confirm your password'), findsOneWidget);
  });

  testWidgets('toggling off disables biometric login', (tester) async {
    SharedPreferences.setMockInitialValues({'biometric_enabled': true});
    final svc = BiometricAuthService(gate: FakeBiometricGate(available: true));
    await svc.load();
    expect(svc.isEnabled, isTrue);
    await tester.pumpWidget(_host(svc));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SwitchListTile)); // on -> off
    await tester.pumpAndSettle();
    expect(svc.isEnabled, isFalse);
  });

  testWidgets('wrong password: shows error, does NOT enable', (tester) async {
    final svc = BiometricAuthService(gate: FakeBiometricGate(available: true));
    await svc.load();
    await tester.pumpWidget(
        _host(svc, verify: (_) async => PasswordCheck.wrongPassword));
    await tester.pumpAndSettle();
    await _tapToggleAndConfirm(tester);
    expect(find.textContaining('Incorrect password'), findsOneWidget);
    expect(svc.isEnabled, isFalse);
  });

  testWidgets('network error: shows error, does NOT enable', (tester) async {
    final svc = BiometricAuthService(gate: FakeBiometricGate(available: true));
    await svc.load();
    await tester.pumpWidget(
        _host(svc, verify: (_) async => PasswordCheck.error));
    await tester.pumpAndSettle();
    await _tapToggleAndConfirm(tester);
    expect(find.textContaining("Couldn't verify"), findsOneWidget);
    expect(svc.isEnabled, isFalse);
  });

  testWidgets('correct password: enables + shows confirmation', (tester) async {
    final svc = BiometricAuthService(gate: FakeBiometricGate(available: true));
    await svc.load();
    await tester.pumpWidget(
        _host(svc, verify: (_) async => PasswordCheck.ok));
    await tester.pumpAndSettle();
    await _tapToggleAndConfirm(tester);
    expect(svc.isEnabled, isTrue);
    expect(find.textContaining('login enabled'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/widgets/security_privacy_card_test.dart`
Expected: FAIL to compile — `The named parameter 'verifyPassword' isn't defined` / `Undefined name 'PasswordCheck'`.

- [ ] **Step 3: Add the enum, typedef, field, and busy-guarded verify to the card**

In `lib/widgets/security_privacy_card.dart`, add after the imports (before the `SecurityPrivacyCard` class doc):

```dart
/// Outcome of verifying the signed-in user's password against the server
/// before enabling biometric login.
enum PasswordCheck { ok, wrongPassword, error }

/// Verifies [password] for the signed-in user against the server. Returns
/// [PasswordCheck.ok] only when the server accepts it.
typedef PasswordVerifier = Future<PasswordCheck> Function(String password);
```

Add the field + required constructor param:

```dart
  const SecurityPrivacyCard({
    super.key,
    required this.login,
    required this.displayName,
    required this.verifyPassword,
  });

  final String login;
  final String displayName;
  final PasswordVerifier verifyPassword;
```

Add a busy flag to the state class (next to `_bioCapable`):

```dart
  bool _busy = false;
```

Replace the entire `_toggleBiometric` method with:

```dart
  Future<void> _toggleBiometric(bool on) async {
    final bio = context.read<BiometricAuthService>();
    if (!on) {
      await bio.disable();
      return;
    }
    final password = await _promptPassword();
    if (password == null || password.isEmpty) return;

    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final check = await widget.verifyPassword(password);
    if (!mounted) return;

    if (check != PasswordCheck.ok) {
      setState(() => _busy = false);
      messenger.showSnackBar(SnackBar(
        content: Text(check == PasswordCheck.wrongPassword
            ? 'Incorrect password — ${biometricLabel(_bioKind)} not enabled.'
            : "Couldn't verify — check your connection."),
        backgroundColor: AppTheme.error,
      ));
      return;
    }

    final ok = await bio.enable(
      login: widget.login,
      password: password,
      displayName: widget.displayName,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      messenger.showSnackBar(SnackBar(
          content: Text('${biometricLabel(_bioKind)} login enabled')));
    }
  }
```

Change the `SwitchListTile`'s `onChanged` to respect the busy flag:

```dart
                onChanged: _busy ? null : _toggleBiometric,
```

- [ ] **Step 4: Wire the production verifier in `profile_screen`**

In `lib/screens/profile/profile_screen.dart`, add the import (after the existing `omni_mobile_api.dart` import, line 11):

```dart
import '../../services/device_service.dart';
```

Replace the `SecurityPrivacyCard(...)` construction (lines ~77-80) with:

```dart
          SecurityPrivacyCard(
            login: session.userLogin,
            displayName: session.employeeName,
            verifyPassword: (password) async {
              final api = OmniMobileApi(
                baseUrl: session.clientUrl,
                db: session.clientDb,
                token: '',
              );
              final deviceId = await DeviceService().getDeviceId();
              try {
                final res = await api.login(
                  login: session.userLogin,
                  password: password,
                  deviceId: deviceId,
                  appVersion: AppConstants.appVersion,
                );
                await session.saveLoginResponse(res);
                return PasswordCheck.ok;
              } on ApiException catch (e) {
                return e.errorCode == 'invalid_credentials'
                    ? PasswordCheck.wrongPassword
                    : PasswordCheck.error;
              } catch (_) {
                return PasswordCheck.error;
              }
            },
          ),
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `flutter test test/widgets/security_privacy_card_test.dart`
Expected: PASS (all 7 cases).

- [ ] **Step 6: Full suite + analyze**

Run: `flutter test` — Expected: all green.
Run: `flutter analyze` — Expected: no issues.

- [ ] **Step 7: Commit**

```bash
git add lib/widgets/security_privacy_card.dart lib/screens/profile/profile_screen.dart test/widgets/security_privacy_card_test.dart
git commit -m "fix: verify password against server before enabling Face ID (Security & Privacy card)"
```

---

### Task 3: Button-only Face ID — remove the auto-prompt (match IKPTB)

**Files:**
- Modify: `lib/screens/login/login_screen.dart:26-30, 64-67` (remove param + auto-trigger)
- Modify: `lib/screens/profile/profile_screen.dart:715-719` (drop the `autoPromptBiometric: false` arg + stale comment)
- Test: `test/screens/login_screen_biometric_test.dart` (drop the param; assert no auto-prompt)

**Interfaces:**
- Produces: `const LoginScreen({super.key})` — no `autoPromptBiometric` parameter. All call sites use `const LoginScreen()`.

- [ ] **Step 1: Update the test to the button-only contract (failing)**

Replace the whole body of `test/screens/login_screen_biometric_test.dart` with:

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

Widget _host(BiometricAuthService bio) => MultiProvider(
      providers: [
        ChangeNotifierProvider<SessionService>.value(value: SessionService()),
        ChangeNotifierProvider<BiometricAuthService>.value(value: bio),
      ],
      child: const MaterialApp(home: LoginScreen()),
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
      'and never auto-prompts', (tester) async {
    final gate = FakeBiometricGate(available: true);
    final bio = await _loadedBio(gate);
    await tester.pumpWidget(_host(bio));
    await tester.pumpAndSettle();
    expect(find.text('Sign in with fingerprint'), findsOneWidget);
    expect(gate.authCalls, 0);
  });

  testWidgets('hides the Face ID button when no credential is stored',
      (tester) async {
    SharedPreferences.setMockInitialValues({}); // biometric_enabled absent
    final gate = FakeBiometricGate(available: true);
    final bio = await _loadedBio(gate);
    await tester.pumpWidget(_host(bio));
    await tester.pumpAndSettle();
    expect(find.textContaining('Sign in with'), findsNothing);
  });

  testWidgets('tapping the button triggers biometric', (tester) async {
    final gate = FakeBiometricGate(available: true);
    final bio = await _loadedBio(gate);
    await tester.pumpWidget(_host(bio));
    await tester.pumpAndSettle();
    expect(gate.authCalls, 0);
    await tester.ensureVisible(find.text('Sign in with fingerprint'));
    await tester.tap(find.text('Sign in with fingerprint'));
    await tester.pumpAndSettle();
    expect(gate.authCalls, 1);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/screens/login_screen_biometric_test.dart`
Expected: FAIL — the "never auto-prompts" test expects `authCalls == 0` but the current code still auto-prompts (`authCalls == 1`). (Compiles fine; `LoginScreen()` still accepts the default.)

- [ ] **Step 3: Remove the parameter and auto-trigger from `LoginScreen`**

In `lib/screens/login/login_screen.dart`, replace lines 26-30 (the doc comment + field + constructor) with:

```dart
  const LoginScreen({super.key});
```

Then in `_resolveBiometric`, delete the auto-prompt tail (lines ~64-67):

```dart
    // DELETE these lines:
    // Auto-prompt once, unless suppressed (e.g. right after a manual logout).
    if (_capable && widget.autoPromptBiometric) {
      _biometricLogin();
    }
```

so `_resolveBiometric` ends right after the `setState({... _bioResolved = true;})` block. (`_biometricLogin()` is retained — it is still called by the button's `onPressed`.)

- [ ] **Step 4: Drop the arg + stale comment in `profile_screen` logout**

In `lib/screens/profile/profile_screen.dart`, replace lines ~715-719:

```dart
      // The Face ID button is still available on the login screen; the
      // credential is kept, so the user can sign back in with Face ID.
      Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
      );
```

- [ ] **Step 5: Run the biometric login test to verify it passes**

Run: `flutter test test/screens/login_screen_biometric_test.dart`
Expected: PASS (all 3 cases).

- [ ] **Step 6: Full suite + analyze**

Run: `flutter test` — Expected: all green.
Run: `flutter analyze` — Expected: no issues (no remaining references to `autoPromptBiometric`).

- [ ] **Step 7: Commit**

```bash
git add lib/screens/login/login_screen.dart lib/screens/profile/profile_screen.dart test/screens/login_screen_biometric_test.dart
git commit -m "feat: Face ID is button-only on login (remove auto-prompt), matching IKPTB"
```

---

## Final verification (after all tasks)

- [ ] `flutter test` — full suite green.
- [ ] `flutter analyze` — clean.
- [ ] `grep -rn "autoPromptBiometric" lib/ test/` returns nothing.
- [ ] Request code review (superpowers:requesting-code-review), then hand to the user for on-device testing. Do NOT merge or bump the version — the user merges + releases personally.

## Manual on-device test script (user)

1. Enable Face ID from Profile → Security & Privacy; in the "Confirm your password" dialog type a **wrong** password → expect *"Incorrect password — … not enabled."*, switch stays off.
2. Repeat with the **correct** password → *"… login enabled"*, switch on.
3. Log out → land on login screen; it does **not** auto-prompt; the "Sign in with Face ID" button is shown; tap it → signs in.
4. Kill + reopen the app while the session is valid → straight to Home (no prompt). Let the session expire (or simulate) → login screen → tap the button → signed in.
5. Delete-account path still requires the password and forgets Face ID.
