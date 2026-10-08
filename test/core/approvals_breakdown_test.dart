import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/core/approvals_breakdown.dart';
import 'package:omni_hr/models/approval_item.dart';

ApprovalItem _item(String type, {bool mine = true}) =>
    ApprovalItem(id: 1, leaveTypeName: type, assignedToMe: mine);

void main() {
  test('counts my types, most frequent first, then by name', () {
    expect(
      approvalsBreakdown([
        _item('Sick Leave'),
        _item('Annual Leave'),
        _item('Annual Leave'),
        _item('Childcare Leave'),
      ]),
      '2 Annual Leave · 1 Childcare Leave · 1 Sick Leave',
    );
  });

  test('ignores requests on someone else\'s step and empty names', () {
    expect(
      approvalsBreakdown([_item('Sick Leave', mine: false), _item('')]),
      '',
    );
  });
}
