# Biometric Login (Face / Fingerprint) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a user re-authenticate with Face ID / Touch ID / fingerprint instead of typing their password when the 30-day session expires.

**Architecture:** Client-only. A new `BiometricAuthService` stores the login+password biometric-gated in the Keystore/Keychain and, on a passed biometric prompt, hands them back so the existing `/login` is replayed. No connector change. A biometric prompt is an app-level gate via `local_auth`; secrets live in `flutter_secure_storage`.

**Tech Stack:** Flutter, `provider` (state), `local_auth` (new), `flutter_secure_storage` (existing), `shared_preferences` (existing).

**Spec:** `docs/superpowers/specs/2026-07-07-biometric-login-design.md`

## Global Constraints

- Convenience-at-expiry only — NOT an app-open lock. A valid session still opens straight to Home; biometric UI appears only where the login screen would otherwise show.
- No connector/backend change. Biometric login replays the existing `OmniMobileApi.login(...)`.
- Secrets (`biometric_login`, `biometric_password`) go in `flutter_secure_storage` only — never SharedPreferences. Non-secret flags (`biometric_enabled`, `biometric_optin_dismissed`, `biometric_display_name`) go in SharedPreferences.
- **Explicit `logout()` clears the biometric credential; involuntary `clearSession()` does NOT.**
- Feature gates itself off when the device has no enrolled biometric or is below Android API 23 (via `isDeviceCapable()`); no global minSdk bump.
- UI copy adapts: "Face ID" / "Touch ID" / "fingerprint" / "biometric" per device.
- Design system: `AppTheme.primary` `#006971`, `AppTheme.primaryContainer` `#2BB8C4`, Inter font, pill buttons (`PrimaryButton`), 24px card radius.
- Test idiom (match existing repo): `TestWidgetsFlutterBinding.ensureInitialized()`, `FlutterSecureStorage.setMockInitialValues({})`, `SharedPreferences.setMockInitialValues({})`. No mock libraries — inject a `BiometricGate` fake for `local_auth`.
- Run tests with `flutter test`; the suite is green in this repo (no ink_sparkle noise — that's kiosk-only).

---

## File Structure

**New:**
- `lib/services/biometric_types.dart` — value types + `BiometricGate` abstract + pure `biometricKindFor()`.
- `lib/services/biometric_auth_service.dart` — `LocalAuthGate` (real gate) + `BiometricAuthService` (ChangeNotifier).
- `lib/widgets/biometric_optin_sheet.dart` — post-login opt-in bottom sheet (Flow A).
- `lib/widgets/biometric_login_panel.dart` — biometric variant of the login screen (Flow B).
- `test/services/biometric_kind_test.dart`
- `test/services/biometric_auth_service_test.dart` (defines `FakeBiometricGate`, reused conceptually by later tasks)
- `test/services/session_logout_test.dart`
- `test/widgets/biometric_optin_sheet_test.dart`
- `test/widgets/biometric_login_panel_test.dart`

**Modified:**
- `pubspec.yaml` — add `local_auth`.
- `ios/Runner/Info.plist` — `NSFaceIDUsageDescription`.
- `android/app/src/main/AndroidManifest.xml` — `USE_BIOMETRIC`.
- `android/app/src/main/kotlin/com/omnisoft/omni_hr/MainActivity.kt` — `FlutterFragmentActivity`.
- `lib/services/session_service.dart` — `onLogout` hook fired in `logout()`.
- `lib/main.dart` — create + load `BiometricAuthService`, wire `session.onLogout`, add provider.
- `lib/screens/login/login_screen.dart` — extract `_performLogin`, opt-in trigger, biometric panel.
- `lib/screens/login/company_settings_screen.dart` — Security toggle row.

---

## Task 1: Dependency & platform config

**Files:**
- Modify: `pubspec.yaml`
- Modify: `ios/Runner/Info.plist`
- Modify: `android/app/src/main/AndroidManifest.xml`
- Modify: `android/app/src/main/kotlin/com/omnisoft/omni_hr/MainActivity.kt`

**Interfaces:**
- Produces: the `local_auth` package availability + platform permissions/config every later task depends on.

- [ ] **Step 1: Add the dependency**

In `pubspec.yaml`, under `dependencies:` (after `url_launcher: ^6.3.0`), add:

```yaml
  local_auth: ^2.3.0
```

- [ ] **Step 2: Fetch packages**

Run: `flutter pub get`
Expected: resolves with `local_auth` (and its `local_auth_android` / `local_auth_darwin` platform packages) added to `pubspec.lock`.

- [ ] **Step 3: iOS Face ID usage string**

In `ios/Runner/Info.plist`, add after the existing `NSCameraUsageDescription` entry:

```xml
	<key>NSFaceIDUsageDescription</key>
	<string>Use Face ID to log in to Omni HR.</string>
```

- [ ] **Step 4: Android biometric permission**

In `android/app/src/main/AndroidManifest.xml`, after the `ACCESS_COARSE_LOCATION` permission line (line 6), add:

```xml
    <uses-permission android:name="android.permission.USE_BIOMETRIC"/>
```

- [ ] **Step 5: MainActivity must be a FragmentActivity**

Replace the entire contents of `android/app/src/main/kotlin/com/omnisoft/omni_hr/MainActivity.kt` with:

```kotlin
package com.omnisoft.omni_hr

import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity: FlutterFragmentActivity() {
}
```

- [ ] **Step 6: Verify analyze + existing suite still pass**

Run: `flutter analyze`
Expected: No issues.
Run: `flutter test`
Expected: All tests pass (unchanged from before).

- [ ] **Step 7: Commit**

```bash
git add pubspec.yaml pubspec.lock ios/Runner/Info.plist android/app/src/main/AndroidManifest.xml android/app/src/main/kotlin/com/omnisoft/omni_hr/MainActivity.kt
git commit -m "chore: add local_auth + biometric platform config (Face ID usage string, USE_BIOMETRIC, FragmentActivity)"
```

---

## Task 2: Value types + biometric-kind mapping

**Files:**
- Create: `lib/services/biometric_types.dart`
- Test: `test/services/biometric_kind_test.dart`

**Interfaces:**
- Produces:
  - `enum BiometricKind { faceId, touchId, fingerprint, face, iris, generic, none }`
  - `class BiometricCredential { final String login; final String password; const BiometricCredential(this.login, this.password); }`
  - `enum BiometricAuthOutcome { success, canceled, lockedOut, unavailable, failed }`
  - `class BiometricAuthResult { final BiometricAuthOutcome outcome; final BiometricCredential? credential; const BiometricAuthResult(this.outcome, [this.credential]); }`
  - `abstract class BiometricGate { Future<bool> isAvailable(); Future<List<BiometricType>> enrolledTypes(); Future<BiometricAuthOutcome> authenticate(String localizedReason); }`
  - `BiometricKind biometricKindFor(bool isIOS, List<BiometricType> types)`

- [ ] **Step 1: Write the failing test**

Create `test/services/biometric_kind_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:omni_hr/services/biometric_types.dart';

void main() {
  group('biometricKindFor', () {
    test('iOS + face → faceId', () {
      expect(biometricKindFor(true, [BiometricType.face]), BiometricKind.faceId);
    });
    test('iOS + fingerprint → touchId', () {
      expect(biometricKindFor(true, [BiometricType.fingerprint]),
          BiometricKind.touchId);
    });
    test('Android + face → face', () {
      expect(biometricKindFor(false, [BiometricType.face]), BiometricKind.face);
    });
    test('Android + fingerprint → fingerprint', () {
      expect(biometricKindFor(false, [BiometricType.fingerprint]),
          BiometricKind.fingerprint);
    });
    test('iris → iris', () {
      expect(biometricKindFor(false, [BiometricType.iris]), BiometricKind.iris);
    });
    test('face wins over fingerprint when both present on iOS', () {
      expect(
          biometricKindFor(true, [BiometricType.fingerprint, BiometricType.face]),
          BiometricKind.faceId);
    });
    test('only strong/weak (no specific modality) → generic', () {
      expect(biometricKindFor(false, [BiometricType.strong]),
          BiometricKind.generic);
    });
    test('empty → none', () {
      expect(biometricKindFor(false, const []), BiometricKind.none);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/biometric_kind_test.dart`
Expected: FAIL — `biometric_types.dart` / `biometricKindFor` not found.

- [ ] **Step 3: Write minimal implementation**

Create `lib/services/biometric_types.dart`:

```dart
import 'package:local_auth/local_auth.dart';

/// Which biometric modality to name in the UI.
enum BiometricKind { faceId, touchId, fingerprint, face, iris, generic, none }

/// A stored login+password pair, returned once a biometric prompt passes.
class BiometricCredential {
  final String login;
  final String password;
  const BiometricCredential(this.login, this.password);
}

/// Outcome of a biometric prompt / retrieve attempt.
enum BiometricAuthOutcome { success, canceled, lockedOut, unavailable, failed }

/// Result of [BiometricAuthService.authenticateAndRetrieve].
/// [credential] is non-null only when [outcome] == success.
class BiometricAuthResult {
  final BiometricAuthOutcome outcome;
  final BiometricCredential? credential;
  const BiometricAuthResult(this.outcome, [this.credential]);
}

/// Thin seam over `local_auth` so the service is unit-testable without a
/// platform channel. Real implementation: `LocalAuthGate`.
abstract class BiometricGate {
  /// Hardware present AND at least one biometric enrolled.
  Future<bool> isAvailable();

  /// Enrolled modalities, for choosing the UI label.
  Future<List<BiometricType>> enrolledTypes();

  /// Show the OS biometric prompt. Maps platform errors to an outcome.
  Future<BiometricAuthOutcome> authenticate(String localizedReason);
}

/// Pure mapping of platform + enrolled modalities to a UI kind.
/// iOS names face → Face ID and fingerprint → Touch ID.
BiometricKind biometricKindFor(bool isIOS, List<BiometricType> types) {
  if (types.isEmpty) return BiometricKind.none;
  if (types.contains(BiometricType.face)) {
    return isIOS ? BiometricKind.faceId : BiometricKind.face;
  }
  if (types.contains(BiometricType.fingerprint)) {
    return isIOS ? BiometricKind.touchId : BiometricKind.fingerprint;
  }
  if (types.contains(BiometricType.iris)) return BiometricKind.iris;
  return BiometricKind.generic;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/services/biometric_kind_test.dart`
Expected: PASS (8 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/services/biometric_types.dart test/services/biometric_kind_test.dart
git commit -m "feat: biometric value types + biometricKindFor mapping"
```

---

## Task 3: Real gate + service capability

**Files:**
- Create: `lib/services/biometric_auth_service.dart`
- Test: `test/services/biometric_auth_service_test.dart`

**Interfaces:**
- Consumes: everything from `biometric_types.dart` (Task 2).
- Produces:
  - `class LocalAuthGate implements BiometricGate` (real; wraps `LocalAuthentication`).
  - `class BiometricAuthService extends ChangeNotifier` with `BiometricAuthService({BiometricGate? gate})`, and these members used by later tasks: `Future<bool> isDeviceCapable()`, `Future<BiometricKind> deviceBiometricKind()`.
  - `FakeBiometricGate` (in the test file) — reused by Tasks 4/5 test code.

- [ ] **Step 1: Write the failing test**

Create `test/services/biometric_auth_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:omni_hr/services/biometric_types.dart';
import 'package:omni_hr/services/biometric_auth_service.dart';

/// Scriptable BiometricGate for tests — no platform channel.
class FakeBiometricGate implements BiometricGate {
  bool available;
  List<BiometricType> types;
  BiometricAuthOutcome nextOutcome;
  int authCalls = 0;

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
  Future<BiometricAuthOutcome> authenticate(String reason) async {
    authCalls++;
    return nextOutcome;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  group('capability', () {
    test('isDeviceCapable reflects the gate', () async {
      final svc = BiometricAuthService(gate: FakeBiometricGate(available: true));
      expect(await svc.isDeviceCapable(), isTrue);
      final svc2 =
          BiometricAuthService(gate: FakeBiometricGate(available: false));
      expect(await svc2.isDeviceCapable(), isFalse);
    });

    test('deviceBiometricKind maps enrolled types', () async {
      final svc = BiometricAuthService(
          gate: FakeBiometricGate(types: [BiometricType.fingerprint]));
      // Host test platform is not iOS, so fingerprint → fingerprint.
      expect(await svc.deviceBiometricKind(), BiometricKind.fingerprint);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/biometric_auth_service_test.dart`
Expected: FAIL — `biometric_auth_service.dart` / `BiometricAuthService` not found.

- [ ] **Step 3: Write minimal implementation**

Create `lib/services/biometric_auth_service.dart`:

```dart
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth/error_codes.dart' as auth_error;

import 'biometric_types.dart';

/// Real gate over `local_auth`.
class LocalAuthGate implements BiometricGate {
  final LocalAuthentication _auth = LocalAuthentication();

  @override
  Future<bool> isAvailable() async {
    try {
      final supported = await _auth.isDeviceSupported();
      if (!supported) return false;
      final canCheck = await _auth.canCheckBiometrics;
      if (!canCheck) return false;
      final enrolled = await _auth.getAvailableBiometrics();
      return enrolled.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<List<BiometricType>> enrolledTypes() async {
    try {
      return await _auth.getAvailableBiometrics();
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<BiometricAuthOutcome> authenticate(String localizedReason) async {
    try {
      final ok = await _auth.authenticate(
        localizedReason: localizedReason,
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
      return ok ? BiometricAuthOutcome.success : BiometricAuthOutcome.canceled;
    } on Exception catch (e) {
      final code = _codeOf(e);
      if (code == auth_error.lockedOut ||
          code == auth_error.permanentlyLockedOut) {
        return BiometricAuthOutcome.lockedOut;
      }
      if (code == auth_error.notAvailable ||
          code == auth_error.notEnrolled ||
          code == auth_error.passcodeNotSet) {
        return BiometricAuthOutcome.unavailable;
      }
      return BiometricAuthOutcome.failed;
    }
  }

  String _codeOf(Object e) {
    try {
      // PlatformException has a `.code`; read defensively.
      return (e as dynamic).code?.toString() ?? '';
    } catch (_) {
      return '';
    }
  }
}

/// Owns the "biometric login" capability and the stored credential.
/// Does NOT perform the network login — it returns a verified credential
/// for the caller to replay against the existing `/login`.
class BiometricAuthService extends ChangeNotifier {
  BiometricAuthService({BiometricGate? gate}) : _gate = gate ?? LocalAuthGate();

  final BiometricGate _gate;
  final FlutterSecureStorage _secure = const FlutterSecureStorage();

  // Secure (Keystore/Keychain)
  static const _sLogin = 'biometric_login';
  static const _sPassword = 'biometric_password';
  // Non-secret (SharedPreferences)
  static const _kEnabled = 'biometric_enabled';
  static const _kOptInDismissed = 'biometric_optin_dismissed';
  static const _kDisplayName = 'biometric_display_name';

  Future<bool> isDeviceCapable() => _gate.isAvailable();

  Future<BiometricKind> deviceBiometricKind() async {
    final types = await _gate.enrolledTypes();
    return biometricKindFor(Platform.isIOS, types);
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/services/biometric_auth_service_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/services/biometric_auth_service.dart test/services/biometric_auth_service_test.dart
git commit -m "feat: LocalAuthGate + BiometricAuthService capability/kind"
```

---

## Task 4: Enable / disable / enabled-state / opt-in flag

**Files:**
- Modify: `lib/services/biometric_auth_service.dart`
- Test: `test/services/biometric_auth_service_test.dart`

**Interfaces:**
- Consumes: `BiometricAuthService`, `FakeBiometricGate` (Task 3).
- Produces on `BiometricAuthService`:
  - `Future<void> load()` — reads `biometric_enabled` + `biometric_display_name` into memory.
  - `bool get isEnabled`
  - `String get displayName`
  - `Future<bool> enable({required String login, required String password, String? displayName})` — prompts; on success stores secrets + flag (+ display name); returns whether it was enabled.
  - `Future<void> disable()` — clears secrets + flag + display name; idempotent.
  - `Future<bool> hasDismissedOptIn()` / `Future<void> markOptInDismissed()`

- [ ] **Step 1: Write the failing tests**

Append to the `main()` of `test/services/biometric_auth_service_test.dart`:

```dart
  group('enable / disable', () {
    test('enable stores creds + flag + display name on prompt success',
        () async {
      final svc = BiometricAuthService(
          gate: FakeBiometricGate(nextOutcome: BiometricAuthOutcome.success));
      await svc.load();
      final ok = await svc.enable(
          login: 'budi@acme.sg', password: 'pw123', displayName: 'Budi');
      expect(ok, isTrue);
      expect(svc.isEnabled, isTrue);
      expect(svc.displayName, 'Budi');
      const secure = FlutterSecureStorage();
      expect(await secure.read(key: 'biometric_login'), 'budi@acme.sg');
      expect(await secure.read(key: 'biometric_password'), 'pw123');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('biometric_enabled'), isTrue);
      expect(prefs.getString('biometric_display_name'), 'Budi');
    });

    test('enable stores nothing when the prompt is cancelled', () async {
      final svc = BiometricAuthService(
          gate: FakeBiometricGate(nextOutcome: BiometricAuthOutcome.canceled));
      await svc.load();
      final ok = await svc.enable(login: 'a@b.c', password: 'pw');
      expect(ok, isFalse);
      expect(svc.isEnabled, isFalse);
      const secure = FlutterSecureStorage();
      expect(await secure.read(key: 'biometric_login'), isNull);
    });

    test('disable clears creds + flag + display name', () async {
      final svc =
          BiometricAuthService(gate: FakeBiometricGate());
      await svc.load();
      await svc.enable(login: 'a@b.c', password: 'pw', displayName: 'A');
      await svc.disable();
      expect(svc.isEnabled, isFalse);
      expect(svc.displayName, '');
      const secure = FlutterSecureStorage();
      expect(await secure.read(key: 'biometric_login'), isNull);
      expect(await secure.read(key: 'biometric_password'), isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('biometric_enabled'), anyOf(isFalse, isNull));
    });

    test('load reflects a previously enabled state', () async {
      SharedPreferences.setMockInitialValues({
        'biometric_enabled': true,
        'biometric_display_name': 'Sarah',
      });
      final svc = BiometricAuthService(gate: FakeBiometricGate());
      await svc.load();
      expect(svc.isEnabled, isTrue);
      expect(svc.displayName, 'Sarah');
    });

    test('opt-in dismissal persists', () async {
      final svc = BiometricAuthService(gate: FakeBiometricGate());
      expect(await svc.hasDismissedOptIn(), isFalse);
      await svc.markOptInDismissed();
      expect(await svc.hasDismissedOptIn(), isTrue);
    });
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/services/biometric_auth_service_test.dart`
Expected: FAIL — `load`, `enable`, `disable`, `isEnabled`, `displayName`, `hasDismissedOptIn`, `markOptInDismissed` not defined.

- [ ] **Step 3: Write minimal implementation**

In `lib/services/biometric_auth_service.dart`, add to `BiometricAuthService` (after `deviceBiometricKind`):

```dart
  bool _enabled = false;
  String _displayName = '';

  bool get isEnabled => _enabled;
  String get displayName => _displayName;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_kEnabled) ?? false;
    _displayName = prefs.getString(_kDisplayName) ?? '';
    notifyListeners();
  }

  Future<bool> enable({
    required String login,
    required String password,
    String? displayName,
  }) async {
    final outcome =
        await _gate.authenticate('Confirm your identity to enable biometric login');
    if (outcome != BiometricAuthOutcome.success) return false;
    await _secure.write(key: _sLogin, value: login);
    await _secure.write(key: _sPassword, value: password);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEnabled, true);
    if (displayName != null && displayName.isNotEmpty) {
      await prefs.setString(_kDisplayName, displayName);
      _displayName = displayName;
    }
    _enabled = true;
    notifyListeners();
    return true;
  }

  Future<void> disable() async {
    try {
      await _secure.delete(key: _sLogin);
      await _secure.delete(key: _sPassword);
    } catch (_) {
      // Continue — prefs cleanup below must always run.
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kEnabled);
    await prefs.remove(_kDisplayName);
    _enabled = false;
    _displayName = '';
    notifyListeners();
  }

  Future<bool> hasDismissedOptIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kOptInDismissed) ?? false;
  }

  Future<void> markOptInDismissed() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kOptInDismissed, true);
  }
```

Add `import 'package:shared_preferences/shared_preferences.dart';` at the top of the file.

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/services/biometric_auth_service_test.dart`
Expected: PASS (7 tests total in the file).

- [ ] **Step 5: Commit**

```bash
git add lib/services/biometric_auth_service.dart test/services/biometric_auth_service_test.dart
git commit -m "feat: BiometricAuthService enable/disable/load + opt-in flag"
```

---

## Task 5: authenticateAndRetrieve + outcomes

**Files:**
- Modify: `lib/services/biometric_auth_service.dart`
- Test: `test/services/biometric_auth_service_test.dart`

**Interfaces:**
- Consumes: `BiometricAuthService` (Tasks 3-4), `BiometricAuthResult`, `BiometricAuthOutcome`, `BiometricCredential`.
- Produces: `Future<BiometricAuthResult> authenticateAndRetrieve()` on `BiometricAuthService`.

- [ ] **Step 1: Write the failing tests**

Append to the `main()` of `test/services/biometric_auth_service_test.dart`:

```dart
  group('authenticateAndRetrieve', () {
    test('success returns the stored credential', () async {
      final gate = FakeBiometricGate(nextOutcome: BiometricAuthOutcome.success);
      final svc = BiometricAuthService(gate: gate);
      await svc.load();
      await svc.enable(login: 'budi@acme.sg', password: 'pw123');
      final res = await svc.authenticateAndRetrieve();
      expect(res.outcome, BiometricAuthOutcome.success);
      expect(res.credential!.login, 'budi@acme.sg');
      expect(res.credential!.password, 'pw123');
    });

    test('cancel returns canceled + no credential', () async {
      final gate = FakeBiometricGate();
      final svc = BiometricAuthService(gate: gate);
      await svc.load();
      await svc.enable(login: 'a@b.c', password: 'pw');
      gate.nextOutcome = BiometricAuthOutcome.canceled;
      final res = await svc.authenticateAndRetrieve();
      expect(res.outcome, BiometricAuthOutcome.canceled);
      expect(res.credential, isNull);
    });

    test('lockedOut propagates', () async {
      final gate = FakeBiometricGate();
      final svc = BiometricAuthService(gate: gate);
      await svc.load();
      await svc.enable(login: 'a@b.c', password: 'pw');
      gate.nextOutcome = BiometricAuthOutcome.lockedOut;
      final res = await svc.authenticateAndRetrieve();
      expect(res.outcome, BiometricAuthOutcome.lockedOut);
    });

    test('missing stored credential after a passed prompt → failed', () async {
      final gate = FakeBiometricGate(nextOutcome: BiometricAuthOutcome.success);
      final svc = BiometricAuthService(gate: gate);
      await svc.load(); // never enabled → no secret stored
      final res = await svc.authenticateAndRetrieve();
      expect(res.outcome, BiometricAuthOutcome.failed);
      expect(res.credential, isNull);
    });
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/services/biometric_auth_service_test.dart`
Expected: FAIL — `authenticateAndRetrieve` not defined.

- [ ] **Step 3: Write minimal implementation**

In `lib/services/biometric_auth_service.dart`, add to `BiometricAuthService` (after `disable`):

```dart
  /// Show the biometric prompt and, on success, return the stored
  /// credential. Returns a non-success outcome (with null credential)
  /// on cancel / lockout / unavailable / missing-secret.
  Future<BiometricAuthResult> authenticateAndRetrieve() async {
    final outcome =
        await _gate.authenticate('Log in to Omni HR');
    if (outcome != BiometricAuthOutcome.success) {
      return BiometricAuthResult(outcome);
    }
    final login = await _secure.read(key: _sLogin);
    final password = await _secure.read(key: _sPassword);
    if (login == null || login.isEmpty || password == null) {
      return const BiometricAuthResult(BiometricAuthOutcome.failed);
    }
    return BiometricAuthResult(
        BiometricAuthOutcome.success, BiometricCredential(login, password));
  }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/services/biometric_auth_service_test.dart`
Expected: PASS (11 tests total in the file).

- [ ] **Step 5: Commit**

```bash
git add lib/services/biometric_auth_service.dart test/services/biometric_auth_service_test.dart
git commit -m "feat: BiometricAuthService.authenticateAndRetrieve"
```

---

## Task 6: SessionService logout hook

**Files:**
- Modify: `lib/services/session_service.dart:527-538` (the `logout()` method)
- Test: `test/services/session_logout_test.dart`

**Interfaces:**
- Produces on `SessionService`: `void Function()? onLogout;` — invoked inside `logout()` only (NOT `clearSession()`).

- [ ] **Step 1: Write the failing test**

Create `test/services/session_logout_test.dart`:

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

  test('logout() fires onLogout', () async {
    final svc = SessionService();
    await svc.load();
    var fired = 0;
    svc.onLogout = () => fired++;
    await svc.logout();
    expect(fired, 1);
  });

  test('clearSession() does NOT fire onLogout', () async {
    final svc = SessionService();
    await svc.load();
    var fired = 0;
    svc.onLogout = () => fired++;
    await svc.clearSession();
    expect(fired, 0);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/session_logout_test.dart`
Expected: FAIL — `onLogout` not defined on `SessionService`.

- [ ] **Step 3: Write minimal implementation**

In `lib/services/session_service.dart`, add a public field near the top of the class (e.g. just after `final FlutterSecureStorage _secure = const FlutterSecureStorage();`):

```dart
  /// Fired on explicit logout only (NOT involuntary clearSession).
  /// main() wires this to BiometricAuthService.disable so a deliberate
  /// sign-out also forgets the biometric credential.
  void Function()? onLogout;
```

Then in the `logout()` method, add `onLogout?.call();` immediately before the final `notifyListeners();`:

```dart
  Future<void> logout() async {
    _saasUrl = '';
    _companyCode = '';
    _clientUrl = '';
    _clientDb = '';
    await clearSession();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keySaasUrl);
    await prefs.remove(_keyCompanyCode);
    await prefs.remove(_keyClientUrl);
    await prefs.remove(_keyClientDb);
    onLogout?.call();
    notifyListeners();
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/services/session_logout_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/services/session_service.dart test/services/session_logout_test.dart
git commit -m "feat: SessionService.onLogout hook (explicit logout only)"
```

---

## Task 7: Wire the service into main.dart

**Files:**
- Modify: `lib/main.dart`

**Interfaces:**
- Consumes: `BiometricAuthService` (Tasks 3-5), `SessionService.onLogout` (Task 6).
- Produces: `BiometricAuthService` provided app-wide via `ChangeNotifierProvider.value`; `OmniHrApp` gains a `biometric` field.

- [ ] **Step 1: Add the import + create/load/wire in main()**

In `lib/main.dart`, add after the `session_service.dart` import:

```dart
import 'services/biometric_auth_service.dart';
```

Replace the body of `main()` (lines 14-28) with:

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppConstants.initAppVersion();
  final session = SessionService();
  await session.load();

  final biometric = BiometricAuthService();
  await biometric.load();

  // A deliberate sign-out also forgets the biometric credential.
  session.onLogout = () {
    biometric.disable();
  };

  // When any /api/v1 call returns invalid_session, wipe the local
  // auth session so the top-level Consumer below re-renders to the
  // Login screen. SaaS routing (company code) is preserved. Biometric
  // credential is intentionally KEPT — this is the case it exists for.
  OmniMobileApi.onInvalidSession = () {
    session.clearSession();
  };

  runApp(OmniHrApp(session: session, biometric: biometric));
}
```

- [ ] **Step 2: Add the field to OmniHrApp**

Replace the `OmniHrApp` field/constructor (lines 30-32) with:

```dart
class OmniHrApp extends StatefulWidget {
  final SessionService session;
  final BiometricAuthService biometric;
  const OmniHrApp({super.key, required this.session, required this.biometric});
```

- [ ] **Step 3: Register the provider**

In `_OmniHrAppState.build`, add to the `providers:` list (after the `ChangeNotifierProvider.value(value: widget.session)` line):

```dart
        ChangeNotifierProvider.value(value: widget.biometric),
```

- [ ] **Step 4: Verify**

Run: `flutter analyze`
Expected: No issues.
Run: `flutter test`
Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/main.dart
git commit -m "feat: provide BiometricAuthService + wire logout→disable in main"
```

---

## Task 8: Opt-in bottom sheet widget

**Files:**
- Create: `lib/widgets/biometric_optin_sheet.dart`
- Test: `test/widgets/biometric_optin_sheet_test.dart`

**Interfaces:**
- Consumes: `BiometricKind` (Task 2), `PrimaryButton` (`lib/widgets/primary_button.dart`), `AppTheme`.
- Produces:
  - `String biometricLabel(BiometricKind kind)` (top-level in this file) → "Face ID" / "Touch ID" / "fingerprint" / "biometric".
  - `class BiometricOptInSheet extends StatelessWidget` with `final BiometricKind kind; final VoidCallback onEnable; final VoidCallback onNotNow;`
  - `Future<void> showBiometricOptInSheet(BuildContext, {required BiometricKind kind, required VoidCallback onEnable, required VoidCallback onNotNow})`

- [ ] **Step 1: Write the failing test**

Create `test/widgets/biometric_optin_sheet_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/services/biometric_types.dart';
import 'package:omni_hr/widgets/biometric_optin_sheet.dart';

void main() {
  testWidgets('shows label + fires callbacks', (tester) async {
    var enabled = 0;
    var notNow = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BiometricOptInSheet(
          kind: BiometricKind.faceId,
          onEnable: () => enabled++,
          onNotNow: () => notNow++,
        ),
      ),
    ));
    expect(find.text('Enable Face ID'), findsOneWidget);
    await tester.tap(find.text('Enable Face ID'));
    expect(enabled, 1);
    await tester.tap(find.text('Not now'));
    expect(notNow, 1);
  });

  test('biometricLabel maps kinds', () {
    expect(biometricLabel(BiometricKind.faceId), 'Face ID');
    expect(biometricLabel(BiometricKind.touchId), 'Touch ID');
    expect(biometricLabel(BiometricKind.fingerprint), 'fingerprint');
    expect(biometricLabel(BiometricKind.face), 'face unlock');
    expect(biometricLabel(BiometricKind.generic), 'biometric');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widgets/biometric_optin_sheet_test.dart`
Expected: FAIL — file/class not found.

- [ ] **Step 3: Write minimal implementation**

Create `lib/widgets/biometric_optin_sheet.dart`:

```dart
import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../services/biometric_types.dart';
import 'primary_button.dart';

/// Human label for a biometric kind, used in button/body copy.
String biometricLabel(BiometricKind kind) {
  switch (kind) {
    case BiometricKind.faceId:
      return 'Face ID';
    case BiometricKind.touchId:
      return 'Touch ID';
    case BiometricKind.fingerprint:
      return 'fingerprint';
    case BiometricKind.face:
      return 'face unlock';
    case BiometricKind.iris:
      return 'iris';
    case BiometricKind.generic:
    case BiometricKind.none:
      return 'biometric';
  }
}

IconData _iconFor(BiometricKind kind) {
  switch (kind) {
    case BiometricKind.faceId:
    case BiometricKind.face:
      return Icons.face;
    default:
      return Icons.fingerprint;
  }
}

/// Post-login opt-in prompt (Flow A). Pure widget — callbacks injected.
class BiometricOptInSheet extends StatelessWidget {
  final BiometricKind kind;
  final VoidCallback onEnable;
  final VoidCallback onNotNow;

  const BiometricOptInSheet({
    super.key,
    required this.kind,
    required this.onEnable,
    required this.onNotNow,
  });

  @override
  Widget build(BuildContext context) {
    final label = biometricLabel(kind);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_iconFor(kind), size: 56, color: AppTheme.primary),
          const SizedBox(height: 16),
          Text('Faster sign-in next time',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center),
          const SizedBox(height: 12),
          Text(
            'Use $label to log back in when your session expires, '
            'instead of typing your password.',
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          PrimaryButton(label: 'Enable $label', onPressed: onEnable),
          const SizedBox(height: 8),
          TextButton(onPressed: onNotNow, child: const Text('Not now')),
        ],
      ),
    );
  }
}

/// Shows [BiometricOptInSheet] as a modal bottom sheet. Both callbacks
/// close the sheet first, then run.
Future<void> showBiometricOptInSheet(
  BuildContext context, {
  required BiometricKind kind,
  required VoidCallback onEnable,
  required VoidCallback onNotNow,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppTheme.surfaceContainerLowest,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => BiometricOptInSheet(
      kind: kind,
      onEnable: () {
        Navigator.of(ctx).pop();
        onEnable();
      },
      onNotNow: () {
        Navigator.of(ctx).pop();
        onNotNow();
      },
    ),
  );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/widgets/biometric_optin_sheet_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/biometric_optin_sheet.dart test/widgets/biometric_optin_sheet_test.dart
git commit -m "feat: biometric opt-in bottom sheet + label helper"
```

---

## Task 9: Offer opt-in after a successful manual login

**Files:**
- Modify: `lib/screens/login/login_screen.dart` (extract `_performLogin`, add opt-in offer)

**Interfaces:**
- Consumes: `BiometricAuthService` (via provider), `showBiometricOptInSheet` (Task 8).
- Produces: `_performLogin(String login, String password)` used later by Task 11 (biometric replay). Opt-in is offered once when capable, not enabled, and not previously dismissed.

- [ ] **Step 1: Add imports**

In `lib/screens/login/login_screen.dart`, add:

```dart
import '../../services/biometric_auth_service.dart';
import '../../services/biometric_types.dart';
import '../../widgets/biometric_optin_sheet.dart';
```

- [ ] **Step 2: Extract `_performLogin` and offer opt-in**

Replace the existing `_login()` method (lines 45-115) with the two methods below. `_login()` keeps reading the text fields; `_performLogin()` does the network + session save + opt-in offer + navigation, and is reusable by the biometric path.

```dart
  Future<void> _login() async {
    final loginText = _loginController.text.trim();
    final password = _passwordController.text;
    if (loginText.isEmpty || password.isEmpty) {
      setState(() => _error = 'Enter your email and password.');
      return;
    }
    await _performLogin(loginText, password);
  }

  /// Shared login path for both the password form and biometric replay.
  Future<void> _performLogin(String loginText, String password) async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final session = context.read<SessionService>();
      final api = OmniMobileApi(
        baseUrl: session.clientUrl,
        db: session.clientDb,
        token: '', // login has no auth header
      );
      final deviceId = await _deviceService.getDeviceId();
      final res = await api.login(
        login: loginText,
        password: password,
        deviceId: deviceId,
        appVersion: AppConstants.appVersion,
      );
      final user = res['user'] as Map<String, dynamic>? ?? {};
      final employee = res['employee'] as Map<String, dynamic>? ?? {};
      final expiresAtStr = res['expires_at']?.toString() ?? '';
      await session.saveSession(
        accessToken: res['access_token']?.toString() ?? '',
        expiresAt: expiresAtStr.isNotEmpty
            ? DateTime.tryParse(expiresAtStr)
            : null,
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
        employeeCompanyLogoB64:
            employee['company_logo_b64']?.toString() ?? '',
        employeeHrApprover: employee['hr_approver_name']?.toString() ?? '',
        employeeTimeOffApprover:
            employee['time_off_approver_name']?.toString() ?? '',
        employeeAttendanceApprover:
            employee['attendance_approver_name']?.toString() ?? '',
        employeeExpenseApprover:
            employee['expense_approver_name']?.toString() ?? '',
      );
      if (!mounted) return;
      await _maybeOfferBiometricOptIn(loginText, password,
          employee['name']?.toString() ?? '');
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeShell()),
        (_) => false,
      );
    } on ApiException catch (e) {
      setState(() => _error = _humanize(e));
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// Offer to enable biometric login once, right after a successful
  /// manual login, when the device is capable, it is not already
  /// enabled, and the user has not dismissed the offer before.
  Future<void> _maybeOfferBiometricOptIn(
      String loginText, String password, String displayName) async {
    final bio = context.read<BiometricAuthService>();
    if (bio.isEnabled) return;
    if (await bio.hasDismissedOptIn()) return;
    if (!await bio.isDeviceCapable()) return;
    final kind = await bio.deviceBiometricKind();
    if (!mounted) return;
    await showBiometricOptInSheet(
      context,
      kind: kind,
      onEnable: () async {
        final ok = await bio.enable(
            login: loginText, password: password, displayName: displayName);
        if (ok && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('${biometricLabel(kind)} login enabled')));
        }
      },
      onNotNow: () => bio.markOptInDismissed(),
    );
  }
```

- [ ] **Step 3: Verify analyze + suite**

Run: `flutter analyze`
Expected: No issues.
Run: `flutter test`
Expected: All tests pass (existing widget tests unaffected).

- [ ] **Step 4: Commit**

```bash
git add lib/screens/login/login_screen.dart
git commit -m "feat: offer biometric opt-in after a successful manual login"
```

---

## Task 10: Biometric login panel widget

**Files:**
- Create: `lib/widgets/biometric_login_panel.dart`
- Test: `test/widgets/biometric_login_panel_test.dart`

**Interfaces:**
- Consumes: `BiometricKind`, `biometricLabel` (Task 8), `PrimaryButton`, `BrandLogo`, `AppTheme`.
- Produces: `class BiometricLoginPanel extends StatelessWidget` with:
  `final BiometricKind kind; final String greetingName; final String companyName; final String? companyLogoB64; final bool busy; final VoidCallback onBiometric; final VoidCallback onUsePassword;`

- [ ] **Step 1: Write the failing test**

Create `test/widgets/biometric_login_panel_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/services/biometric_types.dart';
import 'package:omni_hr/widgets/biometric_login_panel.dart';

void main() {
  testWidgets('renders greeting + button, fires callbacks', (tester) async {
    var bio = 0;
    var pwd = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BiometricLoginPanel(
          kind: BiometricKind.faceId,
          greetingName: 'Budi',
          companyName: 'Acme',
          companyLogoB64: null,
          busy: false,
          onBiometric: () => bio++,
          onUsePassword: () => pwd++,
        ),
      ),
    ));
    expect(find.textContaining('Budi'), findsOneWidget);
    expect(find.text('Log in with Face ID'), findsOneWidget);
    await tester.tap(find.text('Log in with Face ID'));
    expect(bio, 1);
    await tester.tap(find.text('Use password instead'));
    expect(pwd, 1);
  });

  testWidgets('falls back to generic greeting when name empty',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BiometricLoginPanel(
          kind: BiometricKind.fingerprint,
          greetingName: '',
          companyName: 'Acme',
          companyLogoB64: null,
          busy: false,
          onBiometric: () {},
          onUsePassword: () {},
        ),
      ),
    ));
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Log in with fingerprint'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widgets/biometric_login_panel_test.dart`
Expected: FAIL — file/class not found.

- [ ] **Step 3: Write minimal implementation**

Create `lib/widgets/biometric_login_panel.dart`:

```dart
import 'dart:convert';
import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../services/biometric_types.dart';
import 'biometric_optin_sheet.dart' show biometricLabel;
import 'primary_button.dart';

/// Biometric variant of the login screen (Flow B). Pure widget —
/// callbacks and data injected; no provider/network access here.
class BiometricLoginPanel extends StatelessWidget {
  final BiometricKind kind;
  final String greetingName;
  final String companyName;
  final String? companyLogoB64;
  final bool busy;
  final VoidCallback onBiometric;
  final VoidCallback onUsePassword;

  const BiometricLoginPanel({
    super.key,
    required this.kind,
    required this.greetingName,
    required this.companyName,
    required this.companyLogoB64,
    required this.busy,
    required this.onBiometric,
    required this.onUsePassword,
  });

  @override
  Widget build(BuildContext context) {
    final label = biometricLabel(kind);
    final greeting =
        greetingName.isEmpty ? 'Welcome back' : 'Welcome back, $greetingName';
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _logo(),
            const SizedBox(height: 16),
            Text(companyName,
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center),
            const SizedBox(height: 24),
            Text(greeting,
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center),
            const SizedBox(height: 24),
            PrimaryButton(
              label: 'Log in with $label',
              icon: kind == BiometricKind.faceId || kind == BiometricKind.face
                  ? Icons.face
                  : Icons.fingerprint,
              loading: busy,
              onPressed: busy ? null : onBiometric,
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: busy ? null : onUsePassword,
              child: const Text('Use password instead'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _logo() {
    final b64 = companyLogoB64;
    if (b64 != null && b64.isNotEmpty) {
      try {
        return ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Image.memory(base64Decode(b64), width: 88, height: 88),
        );
      } catch (_) {
        // fall through to the icon
      }
    }
    return Icon(Icons.badge_outlined, size: 72, color: AppTheme.primary);
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/widgets/biometric_login_panel_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/biometric_login_panel.dart test/widgets/biometric_login_panel_test.dart
git commit -m "feat: biometric login panel widget"
```

---

## Task 11: Show the panel on the login screen + handle replay

**Files:**
- Modify: `lib/screens/login/login_screen.dart`

**Interfaces:**
- Consumes: `BiometricLoginPanel` (Task 10), `BiometricAuthService.authenticateAndRetrieve/disable` (Tasks 4-5), `_performLogin` (Task 9).
- Produces: login screen renders the biometric panel when capable + enabled + not forced to password; biometric success replays `_performLogin`; a `invalid_credentials` replay disables biometric and shows the password form with a "password changed" message.

- [ ] **Step 1: Add capability state + resolve on init**

In `_LoginScreenState`, add fields:

```dart
  bool _capable = false;
  bool _bioResolved = false;
  bool _forcePassword = false; // user tapped "Use password instead"
  BiometricKind _bioKind = BiometricKind.none;
```

Add an `initState` that resolves capability once:

```dart
  @override
  void initState() {
    super.initState();
    _resolveBiometric();
  }

  Future<void> _resolveBiometric() async {
    final bio = context.read<BiometricAuthService>();
    final capable = bio.isEnabled ? await bio.isDeviceCapable() : false;
    final kind = capable ? await bio.deviceBiometricKind() : BiometricKind.none;
    if (!mounted) return;
    setState(() {
      _capable = capable;
      _bioKind = kind;
      _bioResolved = true;
    });
    // Auto-prompt once the panel is shown.
    if (_capable && !_forcePassword) {
      _biometricLogin();
    }
  }
```

- [ ] **Step 2: Add the biometric login handler**

Add to `_LoginScreenState`:

```dart
  Future<void> _biometricLogin() async {
    final bio = context.read<BiometricAuthService>();
    final res = await bio.authenticateAndRetrieve();
    if (!mounted) return;
    if (res.outcome == BiometricAuthOutcome.success && res.credential != null) {
      await _performLogin(res.credential!.login, res.credential!.password);
      return;
    }
    if (res.outcome == BiometricAuthOutcome.lockedOut) {
      setState(() {
        _forcePassword = true;
        _error = 'Too many attempts — please log in with your password.';
      });
    }
    // canceled / failed / unavailable: stay on the panel; user can retry
    // or tap "Use password instead".
  }
```

- [ ] **Step 3: Handle a stale stored password (password changed server-side)**

In `_performLogin`, replace the `on ApiException catch (e)` block with one that clears biometric on an invalid-credentials replay:

```dart
    } on ApiException catch (e) {
      if (e.errorCode == 'invalid_credentials' &&
          context.read<BiometricAuthService>().isEnabled) {
        await context.read<BiometricAuthService>().disable();
        if (mounted) {
          setState(() {
            _forcePassword = true;
            _capable = false;
            _error =
                'Your password has changed — please log in with your password.';
          });
        }
      } else {
        setState(() => _error = _humanize(e));
      }
    } catch (e) {
```

- [ ] **Step 4: Render the panel in build()**

In the `build()` method, wrap the existing password form so the biometric panel shows first when appropriate. Find the top of the returned body and add this early branch (adjust to the existing `Scaffold`/body structure — return the panel instead of the form when `_capable && !_forcePassword`):

```dart
    if (_bioResolved && _capable && !_forcePassword) {
      final session = context.read<SessionService>();
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
    // ...existing password-form Scaffold below unchanged...
```

Add the imports if not already present:

```dart
import '../../widgets/biometric_login_panel.dart';
```

(`session.companyName` and `session.companyLogoB64` getters exist on `SessionService` — they back the `company_name` / `company_logo_b64` prefs that survive `clearSession`.)

- [ ] **Step 5: Verify analyze + suite**

Run: `flutter analyze`
Expected: No issues.
Run: `flutter test`
Expected: All tests pass.

- [ ] **Step 6: Manual on-device note (not automated)**

The `/login` replay is network-dependent and verified on-device in Task 13. Automated tests here cover widget composition only.

- [ ] **Step 7: Commit**

```bash
git add lib/screens/login/login_screen.dart
git commit -m "feat: biometric login panel on the login screen + stale-credential fallback"
```

---

## Task 12: Settings — Security toggle

**Files:**
- Modify: `lib/screens/login/company_settings_screen.dart`

**Interfaces:**
- Consumes: `BiometricAuthService`, `biometricLabel`, `BiometricKind`.
- Produces: a Security section with a switch; OFF calls `disable()`; ON prompts for the current password (one-time confirm) then `enable(...)`. Row hidden when the device is not capable.

- [ ] **Step 1: Add imports**

In `lib/screens/login/company_settings_screen.dart`, add:

```dart
import '../../services/biometric_auth_service.dart';
import '../../services/biometric_types.dart';
import '../../widgets/biometric_optin_sheet.dart' show biometricLabel;
```

- [ ] **Step 2: Resolve capability in the screen state**

In `_CompanySettingsScreenState`, add fields + an init resolve:

```dart
  bool _bioCapable = false;
  BiometricKind _bioKind = BiometricKind.none;

  Future<void> _resolveBio() async {
    final bio = context.read<BiometricAuthService>();
    final capable = await bio.isDeviceCapable();
    final kind = capable ? await bio.deviceBiometricKind() : BiometricKind.none;
    if (!mounted) return;
    setState(() {
      _bioCapable = capable;
      _bioKind = kind;
    });
  }
```

Call `_resolveBio()` from the screen's existing `initState` (add one if absent, calling `super.initState()` first).

- [ ] **Step 3: Add the Security switch to build()**

Insert this widget into the settings list (near the account/logout section). It reads the enabled state reactively via `context.watch`:

```dart
          if (_bioCapable)
            SwitchListTile(
              title: Text('${biometricLabel(_bioKind)} login'),
              subtitle: Text(
                  'Log in with ${biometricLabel(_bioKind)} when your session expires.'),
              value: context.watch<BiometricAuthService>().isEnabled,
              onChanged: (on) => _toggleBiometric(on),
            ),
```

- [ ] **Step 4: Add the toggle handler (enable needs a password confirm)**

Add to `_CompanySettingsScreenState`:

```dart
  Future<void> _toggleBiometric(bool on) async {
    final bio = context.read<BiometricAuthService>();
    if (!on) {
      await bio.disable();
      return;
    }
    final session = context.read<SessionService>();
    final password = await _promptPassword();
    if (password == null || password.isEmpty) return;
    final ok = await bio.enable(
      login: session.userLogin,
      password: password,
      displayName: session.employeeName,
    );
    if (ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${biometricLabel(_bioKind)} login enabled')));
    }
  }

  Future<String?> _promptPassword() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm your password'),
        content: TextField(
          controller: controller,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Password'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: const Text('Confirm')),
        ],
      ),
    );
  }
```

(`session.userLogin` and `session.employeeName` getters exist on `SessionService`. Note: this stores whatever password the user types; if wrong, the first biometric replay will fail with `invalid_credentials` and Task 11's fallback disables it — acceptable per spec §8.)

- [ ] **Step 5: Verify analyze + suite**

Run: `flutter analyze`
Expected: No issues.
Run: `flutter test`
Expected: All tests pass.

- [ ] **Step 6: Commit**

```bash
git add lib/screens/login/company_settings_screen.dart
git commit -m "feat: Security settings toggle for biometric login"
```

---

## Task 13: Release prep + on-device verification

**Files:**
- Modify: `pubspec.yaml` (version bump)
- Modify: `android/fastlane/metadata/android/en-US/changelogs/default.txt`
- Modify: `ios/fastlane/Fastfile` (TESTFLIGHT_CHANGELOG)

**Interfaces:**
- Consumes: everything above.

- [ ] **Step 1: Bump the version**

In `pubspec.yaml`, bump `version:` (minor feature → `1.21.0`, next build number). Set:

```yaml
version: 1.21.0+71
```

- [ ] **Step 2: Play tester notes**

Replace `android/fastlane/metadata/android/en-US/changelogs/default.txt` with (≤500 chars):

```
Biometric login.

- Log back in with Face ID / fingerprint instead of typing your password when your session expires.
- Turn it on when prompted after signing in, or under Settings.

Testers: sign in, enable biometric login when asked, then force a re-login (log out is a full sign-out and clears it; or wait for expiry) and confirm the Face ID / fingerprint button signs you in.
```

- [ ] **Step 3: TestFlight notes**

Update `TESTFLIGHT_CHANGELOG` in `ios/fastlane/Fastfile` to describe biometric login (mirror the Play copy).

- [ ] **Step 4: Full verification**

Run: `flutter analyze`
Expected: No issues.
Run: `flutter test`
Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add pubspec.yaml android/fastlane/metadata/android/en-US/changelogs/default.txt ios/fastlane/Fastfile
git commit -m "chore: bump to 1.21.0+71 + biometric login release notes"
```

- [ ] **Step 6: On-device verification (user, manual — NOT automated)**

On the Samsung (fingerprint) and an iOS Face ID device, in `--release` or a signed build:
1. Fresh login → opt-in sheet appears → Enable → biometric confirm → "enabled" toast.
2. Force re-auth (Settings → involuntary expiry, or clear app data keeping keystore is not possible; simplest: shorten server TTL on a test tenant, OR verify via logout+login that the panel does NOT appear after explicit logout — credential cleared).
3. Reopen at the login screen → biometric panel auto-prompts → pass → lands on Home.
4. "Use password instead" reveals the password form.
5. Change the server password → biometric replay → "password has changed" → password form; biometric now off.
6. Settings toggle: off clears it; on prompts for password then re-enables.
7. Device with no enrolled biometric → no opt-in, no panel (identical to today).

---

## Notes for the implementer

- **DRY:** `FakeBiometricGate` is defined once in `test/services/biometric_auth_service_test.dart` (Task 3). If a later service test needs it, keep it in that same file.
- **Do not** put biometric-disable in `clearSession()` — only `logout()` (Task 6). Involuntary expiry must keep the credential.
- **Do not** bump global Android `minSdk`; the feature self-gates via `isDeviceCapable()`.
- The existing MLKit face code (`face_recognition_service.dart`, `face_capture_screen.dart`) is attendance-only — do not touch it for login.
- Repo test noise: this repo has NO ink_sparkle failures (kiosk-only); a green run is truly green.
