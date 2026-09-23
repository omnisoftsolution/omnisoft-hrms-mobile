import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:omni_hr/core/constants.dart';
import 'package:omni_hr/models/company_info.dart';
import 'package:omni_hr/services/saas_service.dart';
import 'package:omni_hr/services/session_service.dart';

/// Records the SaaS URL + code it was asked for; returns a fixed company
/// or throws [error].
class _FakeSaas extends SaasService {
  _FakeSaas({this.error});
  final Exception? error;
  String? lastSaasUrl;
  String? lastCode;

  @override
  Future<CompanyInfo> resolveCompany(String saasUrl, String companyCode) async {
    lastSaasUrl = saasUrl;
    lastCode = companyCode;
    if (error != null) throw error!;
    return CompanyInfo(
      companyCode: 'NOVAWORKS',
      name: 'Nova Works',
      odooUrl: 'https://nova.example',
      database: 'nova_db',
      features: const {'attendance': true},
      companyLogoB64: 'LOGO',
      showConnectionDetails: true,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('fresh install resolves against the default SaaS URL and saves it',
      () async {
    final s = SessionService();
    final saas = _FakeSaas();
    await s.resolveCompanyWith(saas, 'NOVAWORKS');
    expect(saas.lastSaasUrl, DevConstants.defaultSaasUrl);
    expect(saas.lastCode, 'NOVAWORKS');
    expect(s.saasUrl, DevConstants.defaultSaasUrl);
    expect(s.companyCode, 'NOVAWORKS');
    expect(s.clientUrl, 'https://nova.example');
    expect(s.clientDb, 'nova_db');
    expect(s.companyName, 'Nova Works');
    expect(s.companyLogoB64, 'LOGO');
    expect(s.showConnectionDetails, isTrue);
    expect(s.hasCompany, isTrue);
  });

  test('uses the session SaaS URL when set, an explicit one over both',
      () async {
    final s = SessionService();
    await s.saveCompany(
        saasUrl: 'https://saas.custom', companyCode: 'OLD', clientUrl: 'x');
    final saas = _FakeSaas();
    await s.resolveCompanyWith(saas, 'NOVAWORKS');
    expect(saas.lastSaasUrl, 'https://saas.custom');
    await s.resolveCompanyWith(saas, 'NOVAWORKS', saasUrl: 'https://typed');
    expect(saas.lastSaasUrl, 'https://typed');
    expect(s.saasUrl, 'https://typed');
  });

  test('rethrows the SaaS error and leaves the session untouched', () async {
    final s = SessionService();
    final saas = _FakeSaas(error: Exception('Company code not found'));
    await expectLater(
        s.resolveCompanyWith(saas, 'NOPE'), throwsA(isA<Exception>()));
    expect(s.hasCompany, isFalse);
  });
}
