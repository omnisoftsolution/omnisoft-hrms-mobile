import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/services/deep_link_service.dart';

void main() {
  test('parses omnihr://activate', () {
    final a = parseActivationLink(
        Uri.parse('omnihr://activate?c=NOVAWORKS&t=abc_DEF-123'));
    expect(a!.companyCode, 'NOVAWORKS');
    expect(a.token, 'abc_DEF-123');
  });
  test('rejects other hosts and missing params', () {
    expect(parseActivationLink(Uri.parse('omnihr://other?c=x&t=y')), isNull);
    expect(parseActivationLink(Uri.parse('omnihr://activate?c=x')), isNull);
  });
}
