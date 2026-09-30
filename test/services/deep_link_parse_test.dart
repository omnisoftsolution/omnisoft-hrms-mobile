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

  group('LinkDeduper', () {
    final link = Uri.parse('omnihr://activate?c=NOVAWORKS&t=T');
    final t0 = DateTime(2026, 9, 23, 10);

    test('drops the double delivery of the launch link (initial + stream)',
        () {
      final d = LinkDeduper();
      expect(d.shouldHandle(link, t0), isTrue);
      expect(
          d.shouldHandle(link, t0.add(const Duration(milliseconds: 300))),
          isFalse);
    });

    test('the same link tapped again later opens again', () {
      final d = LinkDeduper();
      expect(d.shouldHandle(link, t0), isTrue);
      expect(d.shouldHandle(link, t0.add(const Duration(seconds: 30))),
          isTrue);
      expect(d.shouldHandle(link, t0.add(const Duration(minutes: 5))),
          isTrue);
    });

    test('only the first duplicate is dropped', () {
      final d = LinkDeduper();
      expect(d.shouldHandle(link, t0), isTrue);
      expect(d.shouldHandle(link, t0.add(const Duration(milliseconds: 100))),
          isFalse);
      expect(d.shouldHandle(link, t0.add(const Duration(milliseconds: 900))),
          isTrue);
    });

    test('a different link is always handled', () {
      final d = LinkDeduper();
      final other = Uri.parse('omnihr://activate?c=NOVAWORKS&t=U');
      expect(d.shouldHandle(link, t0), isTrue);
      expect(d.shouldHandle(other, t0), isTrue);
    });
  });

  test('carries the login from l, decoded', () {
    final a = parseActivationLink(Uri.parse(
        'omnihr://activate?c=NOVAWORKS&t=T&l=arjun.patel%40omnihr-sg.com'));
    expect(a!.login, 'arjun.patel@omnihr-sg.com');
  });
  test('links without l (issued before 2.47) still parse', () {
    final a = parseActivationLink(Uri.parse('omnihr://activate?c=N&t=T'));
    expect(a!.login, isNull);
    final b = parseActivationLink(Uri.parse('omnihr://activate?c=N&t=T&l='));
    expect(b!.login, isNull);
  });
}
