import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/services/identity_bodies.dart';

void main() {
  test('login body omits nulls and trims login', () {
    final b = buildLoginBody(login: '  Say.Puay@Example.com ', password: 'x', deviceId: 'd1');
    expect(b, {'login': 'say.puay@example.com', 'password': 'x', 'device_id': 'd1'});
  });
  test('login body carries label, version and email code when given', () {
    final b = buildLoginBody(login: 'a@b.c', password: 'x', deviceId: 'd1',
        deviceLabel: 'Pixel 8', appVersion: '1.25.0', emailCode: '123456');
    expect(b['device_label'], 'Pixel 8');
    expect(b['app_version'], '1.25.0');
    expect(b['email_code'], '123456');
  });
  test('activate body: token xor code', () {
    final t = buildActivateBody(login: 'a@b.c', token: 'T', password: 'p', deviceId: 'd');
    expect(t.containsKey('token'), isTrue); expect(t.containsKey('code'), isFalse);
    final c = buildActivateBody(login: 'a@b.c', code: '123456', password: 'p', deviceId: 'd');
    expect(c['code'], '123456'); expect(c.containsKey('token'), isFalse);
  });
  test('refresh body', () {
    expect(buildRefreshBody(refreshToken: 'R', deviceId: 'd'), {'refresh_token': 'R', 'device_id': 'd'});
  });
}
