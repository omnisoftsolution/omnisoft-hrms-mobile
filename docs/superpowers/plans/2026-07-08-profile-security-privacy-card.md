# Profile "Security & Privacy" Card Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the biometric-login toggle out of Company Settings into a new "Security & Privacy" card on the Profile screen (with the Privacy Policy link), reverting Company Settings to company/diagnostics only.

**Architecture:** A new self-contained `SecurityPrivacyCard` StatefulWidget owns the biometric capability lookup + toggle logic (moved verbatim from `company_settings_screen`) and the Privacy Policy link row. `ProfileScreen` mounts it above LOGOUT, passing `login`/`displayName` from `SessionService`. The biometric feature's behavior is unchanged — only its location moves.

**Tech Stack:** Flutter, Provider (`BiometricAuthService` is a `ChangeNotifier`), `local_auth` behind the injectable `BiometricGate` seam, `url_launcher`, `flutter_secure_storage` + `shared_preferences` (mockable in tests).

## Global Constraints

- Client-only. NO connector / server changes.
- NO change to biometric enable/disable/replay logic, the opt-in sheet (flow A), or the login panel (flow B). This is a relocation.
- NO version bump in this work (handled separately at release time).
- Do NOT merge without the user's explicit permission (he device-tests personally).
- Card gets `login`/`displayName` via constructor params (from `SessionService` at the call site), NOT by reading `SessionService` inside the widget.
- The biometric toggle renders ONLY when the device is biometric-capable; the Privacy Policy row renders always.
- Match existing widget-test style: `FakeBiometricGate`, `FlutterSecureStorage.setMockInitialValues({})` + `SharedPreferences.setMockInitialValues({})` in `setUp`, `MaterialApp(home: Scaffold(...))` harness.

---

### Task 1: Create the `SecurityPrivacyCard` widget

**Files:**
- Create: `lib/widgets/security_privacy_card.dart`
- Test: `test/widgets/security_privacy_card_test.dart`

**Interfaces:**
- Consumes: `BiometricAuthService` (from Provider) — methods `isDeviceCapable()`, `deviceBiometricKind()`, `enable({required String login, required String password, String? displayName})`, `disable()`, getter `isEnabled`. `biometricLabel(BiometricKind)` from `widgets/biometric_optin_sheet.dart`. `AppConstants.privacyPolicyUrl` from `core/constants.dart`. `AppTheme` from `core/theme.dart`.
- Produces: `class SecurityPrivacyCard extends StatefulWidget` with `const SecurityPrivacyCard({super.key, required String login, required String displayName})`.

- [ ] **Step 1: Write the failing tests**

Create `test/widgets/security_privacy_card_test.dart`:

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

Widget _host(BiometricAuthService svc) => MaterialApp(
      home: Scaffold(
        body: ChangeNotifierProvider<BiometricAuthService>.value(
          value: svc,
          child: const SecurityPrivacyCard(
              login: 'budi@acme.sg', displayName: 'Budi'),
        ),
      ),
    );

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
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/widgets/security_privacy_card_test.dart`
Expected: FAIL — `security_privacy_card.dart` / `SecurityPrivacyCard` does not exist (compile error).

- [ ] **Step 3: Implement the widget**

Create `lib/widgets/security_privacy_card.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/constants.dart';
import '../core/theme.dart';
import '../services/biometric_auth_service.dart';
import '../services/biometric_types.dart';
import 'biometric_optin_sheet.dart' show biometricLabel;

/// Profile → "Security & Privacy" card. Hosts the biometric-login toggle
/// (only when the device is biometric-capable) and the Privacy Policy link.
/// [login] and [displayName] come from the signed-in SessionService at the
/// call site and are used when enabling biometric login (the password is
/// confirmed once here — it is not retained after login).
class SecurityPrivacyCard extends StatefulWidget {
  const SecurityPrivacyCard({
    super.key,
    required this.login,
    required this.displayName,
  });

  final String login;
  final String displayName;

  @override
  State<SecurityPrivacyCard> createState() => _SecurityPrivacyCardState();
}

class _SecurityPrivacyCardState extends State<SecurityPrivacyCard> {
  bool _bioCapable = false;
  BiometricKind _bioKind = BiometricKind.none;

  @override
  void initState() {
    super.initState();
    _resolveBio();
  }

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

  Future<void> _toggleBiometric(bool on) async {
    final bio = context.read<BiometricAuthService>();
    if (!on) {
      await bio.disable();
      return;
    }
    final password = await _promptPassword();
    if (password == null || password.isEmpty) return;
    final ok = await bio.enable(
      login: widget.login,
      password: password,
      displayName: widget.displayName,
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

  Future<void> _openExternalUrl(String url) async {
    final messenger = ScaffoldMessenger.of(context);
    final uri = Uri.tryParse(url);
    if (uri == null) {
      messenger.showSnackBar(SnackBar(
          content: const Text('Invalid link.'),
          backgroundColor: AppTheme.error));
      return;
    }
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched) {
      messenger.showSnackBar(SnackBar(
          content: const Text("Couldn't open the link."),
          backgroundColor: AppTheme.error));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.security, size: 18, color: AppTheme.primary),
                const SizedBox(width: 8),
                const Text('Security & Privacy',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ],
            ),
            if (_bioCapable) ...[
              const SizedBox(height: 6),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${biometricLabel(_bioKind)} login'),
                subtitle: Text('Log in with ${biometricLabel(_bioKind)} '
                    'when your session expires.'),
                value: context.watch<BiometricAuthService>().isEnabled,
                onChanged: _toggleBiometric,
              ),
            ],
            const SizedBox(height: 12),
            _linkTile(
              icon: Icons.shield_outlined,
              label: 'Privacy Policy',
              url: AppConstants.privacyPolicyUrl,
            ),
          ],
        ),
      ),
    );
  }

  Widget _linkTile({
    required IconData icon,
    required String label,
    required String url,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _openExternalUrl(url),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.surfaceContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppTheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600)),
            ),
            Icon(Icons.open_in_new, size: 16, color: AppTheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/widgets/security_privacy_card_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Analyze**

Run: `flutter analyze lib/widgets/security_privacy_card.dart test/widgets/security_privacy_card_test.dart`
Expected: "No issues found!"

- [ ] **Step 6: Commit**

```bash
git add lib/widgets/security_privacy_card.dart test/widgets/security_privacy_card_test.dart
git commit -m "feat: SecurityPrivacyCard — biometric toggle + Privacy Policy link"
```

---

### Task 2: Relocate — mount card on Profile, remove Security/Legal from Company Settings

**Files:**
- Modify: `lib/screens/profile/profile_screen.dart` (insert card above LOGOUT; add import)
- Modify: `lib/screens/login/company_settings_screen.dart` (remove biometric Security section, Legal section, now-unused helpers/fields/imports)
- Test: `test/screens/company_settings_no_biometric_test.dart`

**Interfaces:**
- Consumes: `SecurityPrivacyCard(login:, displayName:)` from Task 1. `SessionService` getters `userLogin`, `employeeName` (already used elsewhere in `profile_screen.dart`).
- Produces: nothing new (wiring + removal).

- [ ] **Step 1: Write the failing regression test**

Create `test/screens/company_settings_no_biometric_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:omni_hr/screens/login/company_settings_screen.dart';
import 'package:omni_hr/services/session_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Company Settings no longer renders the biometric login switch '
      'or a Security section', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ChangeNotifierProvider<SessionService>(
        create: (_) => SessionService(),
        child: const CompanySettingsScreen(),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(SwitchListTile), findsNothing);
    expect(find.text('Security'), findsNothing);
  });
}
```

- [ ] **Step 2: Run the regression test to verify it fails**

Run: `flutter test test/screens/company_settings_no_biometric_test.dart`
Expected: FAIL — a `SwitchListTile` and the "Security" text are still present (biometric block not yet removed).

- [ ] **Step 3: Remove biometric + Legal from `company_settings_screen.dart`**

In `lib/screens/login/company_settings_screen.dart`, delete ALL of the following:

1. The two state fields:
```dart
  bool _bioCapable = false;
  BiometricKind _bioKind = BiometricKind.none;
```
2. The `_resolveBio();` call inside `initState` (leave the rest of `initState`).
3. The whole `_resolveBio` method:
```dart
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
4. The `_toggleBiometric` and `_promptPassword` methods (the full method bodies).
5. In `build`, the Security section:
```dart
              if (_bioCapable) ...[
                const SizedBox(height: 32),
                Text(
                  'Security',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: AppTheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('${biometricLabel(_bioKind)} login'),
                  subtitle: Text(
                      'Log in with ${biometricLabel(_bioKind)} when your session expires.'),
                  value: context.watch<BiometricAuthService>().isEnabled,
                  onChanged: (on) => _toggleBiometric(on),
                ),
              ],
```
6. In `build`, the entire Legal section — this exact block (the leading `SizedBox(32)` through the Account-Deletion `_legalLinkTile`):
```dart
              const SizedBox(height: 32),
              // Legal links — required to be discoverable from inside
              // the app for biometric data handling (Apple) and best
              // practice for Play Store data-safety disclosures.
              Text(
                'Legal',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: AppTheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 8),
              _legalLinkTile(
                icon: Icons.shield_outlined,
                label: 'Privacy Policy',
                url: AppConstants.privacyPolicyUrl,
              ),
              const SizedBox(height: 8),
              _legalLinkTile(
                icon: Icons.delete_outline,
                label: 'Account Deletion',
                url: AppConstants.accountDeletionUrl,
              ),
```
**Keep** the `const SizedBox(height: 32),` and the `Center(child: Text('App version ...'))` that immediately follow it — that surviving `SizedBox` provides the spacing before the App-version footer. Net: after "Clear Company", the next thing is one `SizedBox(32)` then the App-version footer.
7. The now-unused helper methods `_legalLinkTile(...)` and `_openExternalUrl(...)` (full bodies).

- [ ] **Step 4: Mount the card on `profile_screen.dart`**

Add the import near the other widget imports:
```dart
import '../../widgets/security_privacy_card.dart';
```

Then in the `ListView` children, replace:
```dart
          if (session.featureFaceVerification) ...[
            const SizedBox(height: 16),
            _faceCard(context, face, session),
          ],
          const SizedBox(height: 32),
          PrimaryButton(
            label: 'LOGOUT',
```
with:
```dart
          if (session.featureFaceVerification) ...[
            const SizedBox(height: 16),
            _faceCard(context, face, session),
          ],
          const SizedBox(height: 16),
          SecurityPrivacyCard(
            login: session.userLogin,
            displayName: session.employeeName,
          ),
          const SizedBox(height: 32),
          PrimaryButton(
            label: 'LOGOUT',
```

- [ ] **Step 5: Remove now-unused imports flagged by analyze**

Run: `flutter analyze`
Expected unused imports in `company_settings_screen.dart` (remove them):
```dart
import 'package:url_launcher/url_launcher.dart';
import '../../services/biometric_auth_service.dart';
import '../../services/biometric_types.dart';
import '../../widgets/biometric_optin_sheet.dart' show biometricLabel;
```
Keep every other import. Re-run `flutter analyze` → "No issues found!" (Leave `AppConstants.accountDeletionUrl` in `core/constants.dart` — an unused public const triggers no warning.)

- [ ] **Step 6: Run the regression test + full suite**

Run: `flutter test test/screens/company_settings_no_biometric_test.dart`
Expected: PASS.

Run: `flutter test`
Expected: all green (previous count + 5 new tests; no failures).

- [ ] **Step 7: Commit**

```bash
git add lib/screens/profile/profile_screen.dart lib/screens/login/company_settings_screen.dart test/screens/company_settings_no_biometric_test.dart
git commit -m "feat: move biometric toggle to Profile Security & Privacy card; drop it + Legal from Company Settings"
```

---

## Post-implementation verification (before requesting review)

- [ ] `flutter analyze` → "No issues found!"
- [ ] `flutter test` → all green.
- [ ] On-device (user): Profile now shows a "Security & Privacy" card with the biometric toggle + Privacy Policy; enabling asks for the password once and works; Company Settings (gear) no longer shows the biometric switch — including when opened from the login screen pre-login.
- [ ] Do NOT merge without the user's explicit permission.
