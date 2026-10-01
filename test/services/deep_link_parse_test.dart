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

  group('https invite links', () {
    test('fragment form, host ignored', () {
      for (final host in ['omnihrdemo.omnisoftsolution.com', 'evil.example']) {
        final a = parseActivationLink(Uri.parse(
            'https://$host/omni/activate#c=NOVAWORKS&t=Zx81kQ&l=1234567890'));
        expect(a!.companyCode, 'NOVAWORKS');
        expect(a.token, 'Zx81kQ');
        expect(a.login, '1234567890');
      }
    });
    test('query form (mail app rewrote #) and trailing slash', () {
      expect(
          parseActivationLink(Uri.parse(
                  'https://h.example/omni/activate?c=NOVAWORKS&t=T'))!
              .token,
          'T');
      expect(
          parseActivationLink(Uri.parse(
                  'https://h.example/omni/activate/#c=NOVAWORKS&t=T'))!
              .companyCode,
          'NOVAWORKS');
    });
    test('percent-encoded awkward login round-trips', () {
      final a = parseActivationLink(Uri.parse(
          'https://h.example/omni/activate#c=NOVAWORKS&t=T&l=a%26b%23c%20%2B1'));
      expect(a!.login, 'a&b#c +1');
    });
    test('empty l means no login', () {
      expect(
          parseActivationLink(Uri.parse(
                  'https://h.example/omni/activate#c=NOVAWORKS&t=T&l='))!
              .login,
          isNull);
    });
    test('rejects http, other paths, missing c or t', () {
      for (final s in [
        'http://h.example/omni/activate#c=NOVAWORKS&t=T',
        'https://h.example/other#c=NOVAWORKS&t=T',
        'https://h.example/omni/activate#c=NOVAWORKS',
        'https://h.example/omni/activate#t=T',
        'https://h.example/omni/activate',
      ]) {
        expect(parseActivationLink(Uri.parse(s)), isNull, reason: s);
      }
    });
  });

  group('classifyScan', () {
    test('invite in both forms, whitespace trimmed', () {
      expect(classifyScan('  omnihr://activate?c=NOVAWORKS&t=T\n'),
          isA<InviteScan>());
      final r = classifyScan(
          'https://h.example/omni/activate#c=NOVAWORKS&t=T&l=budi.s');
      expect((r as InviteScan).args.login, 'budi.s');
    });
    test('anything else is not an invite', () {
      for (final s in [
        'WIFI:S:Office;T:WPA;P:secret;;',
        'hello',
        'https://example.com',
        'omnihr://activate?c=NOVAWORKS',
        '%%%',
        '',
      ]) {
        expect(classifyScan(s), isA<NotInviteScan>(), reason: s);
      }
    });
  });
}
