import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/services/my_day_memory.dart';
import 'package:omni_hr/services/omni_mobile_api.dart';
import 'package:omni_hr/services/session_service.dart';

import '../fixtures/my_day_fixture.dart';

class _Session extends SessionService {
  _Session({this.employee = 6, this.db = 'acme'});

  int employee;
  String db;
  int epoch = 1;

  @override
  int get employeeId => employee;

  @override
  String get clientDb => db;

  @override
  int get requestEpoch => epoch;
}

void main() {
  setUp(MyDayMemory.clear);

  test('keeps the body for the sign-in it was asked under', () {
    final s = _Session();
    final day = sampleMyDay();
    MyDayMemory.write(s, MyDayMemory.bind(s), day);
    expect(MyDayMemory.read(s), same(day));
  });

  test('an answer asked under another sign-in is not kept', () {
    final s = _Session();
    final asked = MyDayMemory.bind(s);
    s.epoch++; // a sign-out began / a new access token
    MyDayMemory.write(s, asked, sampleMyDay());
    expect(MyDayMemory.read(s), isNull);
  });

  test('another employee, database or session reads nothing and drops it', () {
    final s = _Session();
    MyDayMemory.write(s, MyDayMemory.bind(s), sampleMyDay());
    expect(MyDayMemory.read(_Session(employee: 7)), isNull);
    // Dropped: the first sign-in does not get it back either.
    expect(MyDayMemory.read(s), isNull);

    MyDayMemory.write(s, MyDayMemory.bind(s), sampleMyDay());
    expect(MyDayMemory.read(_Session(db: 'other')), isNull);

    MyDayMemory.write(s, MyDayMemory.bind(s), sampleMyDay());
    s.epoch++;
    expect(MyDayMemory.read(s), isNull);
  });

  test('nothing is kept without an employee', () {
    final s = _Session(employee: 0);
    MyDayMemory.write(s, MyDayMemory.bind(s), sampleMyDay());
    expect(MyDayMemory.read(s), isNull);
  });

  test('access answers drop it; transport errors do not', () {
    for (final code in [
      'no_employee_linked',
      'invalid_session',
      'not_allowed',
      'feature_unavailable',
    ]) {
      expect(MyDayMemory.dropsOn(ApiException(code)), isTrue, reason: code);
    }
    for (final code in ['network_error', 'timeout', 'server_error']) {
      expect(MyDayMemory.dropsOn(ApiException(code)), isFalse, reason: code);
    }
    expect(MyDayMemory.dropsOn(StateError('x')), isFalse);
  });
}
