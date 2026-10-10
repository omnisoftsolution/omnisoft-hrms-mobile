import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/screens/activation/activation_screen.dart';
import 'package:omni_hr/screens/activation/add_phone_screen.dart';
import 'package:omni_hr/screens/activation/link_route.dart';
import 'package:omni_hr/services/deep_link_service.dart';

void main() {
  test('an add-phone link opens Add this phone with the link values', () {
    final w = screenForActivationLink(const ActivationArgs('NOVAWORKS', 'T',
        login: 'budi.s', kind: ActivationKind.addPhone));
    expect(w, isA<AddPhoneScreen>());
    final s = w as AddPhoneScreen;
    expect(s.companyCode, 'NOVAWORKS');
    expect(s.token, 'T');
    expect(s.login, 'budi.s');
  });

  test('an invite link opens the activation screen as before', () {
    final w = screenForActivationLink(
        const ActivationArgs('NOVAWORKS', 'T', login: 'budi.s'));
    expect(w, isA<ActivationScreen>());
    final s = w as ActivationScreen;
    expect(s.companyCode, 'NOVAWORKS');
    expect(s.token, 'T');
    expect(s.login, 'budi.s');
  });
}
