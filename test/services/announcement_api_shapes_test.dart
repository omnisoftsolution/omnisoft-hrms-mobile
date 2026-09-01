import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/services/omni_mobile_api.dart';

void main() {
  test('ack body shape', () {
    expect(buildAnnouncementAckBody(announcementId: 12),
        {'announcement_id': 12});
  });
}
