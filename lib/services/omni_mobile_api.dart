import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../models/approval_detail.dart';
import '../models/approval_item.dart';
import '../models/attendance_record.dart';
import '../models/attendance_status.dart';
import '../models/currency_option.dart';
import '../models/leave_type.dart';
import '../models/my_day.dart';
import '../models/expense_record.dart';
import '../models/leave_duration_preview.dart';
import '../models/leave_record.dart';
import '../models/notification_record.dart';
import '../models/ocr_result.dart';
import '../models/payslip_record.dart';
import '../models/public_holiday.dart';
import 'identity_bodies.dart';

/// Builds the request body map for attendance check-in/out calls.
///
/// This is the single source of truth for attendance request body
/// construction. Extracted as a top-level function so it can be unit-tested
/// without HTTP. Both [OmniMobileApi.checkIn] and [OmniMobileApi.checkOut]
/// delegate to this function.
///
/// - [latitude] / [longitude]: omitted (not sent as JSON null) when geo is
///   off — the connector treats absence of coords as "skip geofence".
/// - [isMocked]: always sent; true when the GPS fix came from a mocked
///   provider (emulator or developer tool).
/// - [accuracy]: omitted when null (GPS accuracy unavailable).
/// - [devLocation]: when true, appends `_dev_location: true` so the server
///   bypasses the geofence. Only set via DevConstants.useDevLocation.
/// - [wifiSsid] / [wifiBssid]: omitted when null, following the same
///   pattern as [latitude] and [accuracy].
Map<String, dynamic> buildAttendanceBody({
  double? latitude,
  double? longitude,
  bool faceVerified = true,
  String? deviceId,
  bool devLocation = false,
  bool isMocked = false,
  double? accuracy,
  String? wifiSsid,
  String? wifiBssid,
}) {
  return {
    'latitude': ?latitude,
    'longitude': ?longitude,
    'face_verified': faceVerified,
    'device_id': ?deviceId,
    'is_mocked': isMocked,
    'location_accuracy': ?accuracy,
    'wifi_ssid': ?wifiSsid,
    'wifi_bssid': ?wifiBssid,
    if (devLocation) '_dev_location': true,
  };
}

/// Builds the request body for /leave/preview — the same shape as
/// /leave/apply minus reason and attachment. Optional fields are
/// omitted (not sent as JSON null): the connector reads "both hour
/// fields absent" as a full-day range request, so a null would be a
/// different request. Top-level so it can be unit-tested without HTTP.
Map<String, dynamic> buildLeavePreviewBody({
  required int holidayStatusId,
  required String dateFrom,
  required String dateTo,
  String? dateFromPeriod,
  String? dateToPeriod,
  double? hourFrom,
  double? hourTo,
}) {
  return {
    'holiday_status_id': holidayStatusId,
    'date_from': dateFrom,
    'date_to': dateTo,
    'date_from_period': ?dateFromPeriod,
    'date_to_period': ?dateToPeriod,
    'hour_from': ?hourFrom,
    'hour_to': ?hourTo,
  };
}

/// Body for /leave/approvals/approve. `expected_state` is the state the
/// approver was looking at; the connector answers `state_changed` when
/// someone else decided first. Top-level so it is unit-testable.
Map<String, dynamic> buildApproveBody({
  required int leaveId,
  required String expectedState,
}) {
  return {'leave_id': leaveId, 'expected_state': expectedState};
}

/// Body for /leave/approvals/refuse. The reason is trimmed here; the
/// connector requires 3 to 500 characters after trimming.
Map<String, dynamic> buildRefuseBody({
  required int leaveId,
  required String expectedState,
  required String reason,
}) {
  return {
    'leave_id': leaveId,
    'expected_state': expectedState,
    'reason': reason.trim(),
  };
}

/// Body for /attendance/declare (connector 2.54.0, spec 2026-10-07 §3.3).
/// [declaredTime] goes out as the API's UTC string; an empty note and a
/// missing time are left out. Top-level so it is unit-testable.
Map<String, dynamic> buildDeclareBody({
  required int attendanceId,
  required String trigger,
  required String answerCode,
  DateTime? declaredTime,
  String note = '',
}) {
  final trimmed = note.trim();
  return {
    'attendance_id': attendanceId,
    'trigger': trigger,
    'answer_code': answerCode,
    if (declaredTime != null)
      'declared_time': DateFormat(
        'yyyy-MM-dd HH:mm:ss',
        'en_US',
      ).format(declaredTime.toUtc()),
    if (trimmed.isNotEmpty) 'note': trimmed,
  };
}

class OmniMobileApi {
  final String baseUrl;
  final String db;
  final String token;

  OmniMobileApi({required this.baseUrl, required this.db, required this.token});

  /// Wired in main.dart at app boot. Called whenever any /api/v1/...
  /// call returns `error: invalid_session` (or the legacy alias
  /// `invalid_token`). Typical wiring: SessionService.clearSession,
  /// which causes the top-level `Consumer<SessionService>` in
  /// OmniHrApp to re-render and route the user back to LoginScreen.
  static void Function()? onInvalidSession;

  /// Wired in main.dart. Called whenever a call is refused with
  /// `kiosk_only`: HR switched "Attendance on kiosk only" on after the
  /// last /me, so the session flag is stale. Typical wiring:
  /// SessionService.refreshMe (My day's tile drops its check-in button
  /// on the next day load, which also reports `kiosk_only`).
  static void Function()? onKioskOnly;

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    if (token.isNotEmpty) 'Authorization': 'Bearer $token',
  };

  Uri _uri(String path) => Uri.parse('$baseUrl/api/v1/omni_mobile$path?db=$db');

  Future<Map<String, dynamic>> _post(
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    // 30s timeout so the UI can't hang forever if the server stops
    // responding cleanly (Android symptom: CHECK OUT button stuck on
    // SCANNING…). 30s is generous enough for cellular + a real
    // geofence/overtime computation on the connector.
    final http.Response response;
    try {
      response = await http
          .post(_uri(path), headers: _headers, body: jsonEncode(body ?? {}))
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              throw ApiException('timeout');
            },
          );
    } on ApiException {
      // Our own timeout sentinel from onTimeout — re-throw as-is.
      rethrow;
    } catch (e) {
      // Raw network failures (SocketException, http.ClientException,
      // HandshakeException, etc.) carry the full request URI in their
      // .toString() — which includes the database name. NEVER let that
      // reach the UI. Convert to a clean 'network_error' code that
      // _humanize maps to a friendly "no connection" message. This is
      // the single chokepoint for every API call in the app.
      throw ApiException('network_error');
    }
    Map<String, dynamic> data;
    try {
      data = jsonDecode(response.body) as Map<String, dynamic>;
    } on FormatException {
      // Server returned non-JSON (typically an HTML 500 page). Convert
      // to a synthetic ApiException so _humanize falls through to the
      // friendly default ("Login failed. Please try again or contact
      // your administrator.") instead of leaking <!doctype html> to
      // the screen.
      throw ApiException('server_error');
    }
    if (data['success'] != true) {
      final code = data['error']?.toString();
      // 'invalid_token' kept for legacy; new server returns 'invalid_session'.
      if (code == 'invalid_session' || code == 'invalid_token') {
        onInvalidSession?.call();
      }
      if (code == 'kiosk_only') {
        onKioskOnly?.call();
      }
      throw ApiException.fromBody(data);
    }
    return data;
  }

  // -- Auth --

  Future<Map<String, dynamic>> login({
    required String login,
    required String password,
    String? deviceId,
    String? deviceLabel,
    String? appVersion,
    String? emailCode,
  }) => _post(
    '/login',
    buildLoginBody(
      login: login,
      password: password,
      deviceId: deviceId,
      deviceLabel: deviceLabel,
      appVersion: appVersion,
      emailCode: emailCode,
    ),
  );

  Future<Map<String, dynamic>> activate({
    required String login,
    String? token,
    String? code,
    required String password,
    required String deviceId,
    String? deviceLabel,
    String? appVersion,
    String? newLogin,
  }) => _post(
    '/auth/activate',
    buildActivateBody(
      login: login,
      token: token,
      code: code,
      password: password,
      deviceId: deviceId,
      deviceLabel: deviceLabel,
      appVersion: appVersion,
      newLogin: newLogin,
    ),
  );

  Future<Map<String, dynamic>> refresh({
    required String refreshToken,
    required String deviceId,
  }) => _post(
    '/auth/refresh',
    buildRefreshBody(refreshToken: refreshToken, deviceId: deviceId),
  );

  Future<List<Map<String, dynamic>>> devicesList() async {
    final data = await _post('/auth/devices/list');
    return (data['devices'] as List? ?? const []).cast<Map<String, dynamic>>();
  }

  Future<void> deviceRevoke(String deviceId) =>
      _post('/auth/devices/revoke', {'device_id': deviceId});

  Future<void> passwordChange({
    required String currentPassword,
    required String newPassword,
  }) => _post('/auth/password/change', {
    'current_password': currentPassword,
    'new_password': newPassword,
  });

  /// Always resolves on 200; the body may carry error == 'mail_not_configured'.
  Future<Map<String, dynamic>> passwordResetRequest(String login) => _post(
    '/auth/password/reset_request',
    {'login': login.trim().toLowerCase()},
  );

  Future<Map<String, dynamic>> logout({bool forgetDevice = false}) =>
      _post('/logout', {if (forgetDevice) 'forget_device': true});

  /// Account deletion request. The connector revokes the mobile
  /// session and logs the request; full server-side data cleanup is
  /// handled by a separate backend pass. Idempotent — calling twice
  /// from a re-logged-in account is safe.
  Future<Map<String, dynamic>> deleteAccount() async {
    return _post('/account/delete');
  }

  Future<Map<String, dynamic>> me() async {
    return _post('/me');
  }

  // -- Home --

  /// The whole My day home in one call (connector 2.51.0+). Only called
  /// for employees whose session says `attendanceKioskOnly`, so an older
  /// connector never sees it.
  Future<MyDay> fetchMyDay() async {
    final data = await _post('/home/my_day');
    return MyDay.fromJson(data);
  }

  // -- Notifications --

  Future<List<NotificationRecord>> getNotifications() async {
    final data = await _post('/notifications/list');
    final list = (data['notifications'] as List<dynamic>?) ?? const [];
    return list
        .map((e) => NotificationRecord.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<int> getUnreadNotificationCount() async {
    final data = await _post('/notifications/unread_count');
    return (data['count'] as num?)?.toInt() ?? 0;
  }

  /// Empty `ids` marks ALL unread for the current user.
  Future<int> markNotificationsRead({List<int> ids = const []}) async {
    final data = await _post('/notifications/mark_read', {
      if (ids.isNotEmpty) 'ids': ids,
    });
    return (data['marked'] as num?)?.toInt() ?? 0;
  }

  // -- Attendance --

  Future<AttendanceStatus> getAttendanceStatus() async {
    final data = await _post('/attendance/status');
    return AttendanceStatus.fromJson(data);
  }

  Future<Map<String, dynamic>> checkIn({
    double? latitude,
    double? longitude,
    bool faceVerified = true,
    String? deviceId,
    bool devLocation = false,
    bool isMocked = false,
    double? accuracy,
    String? wifiSsid,
    String? wifiBssid,
  }) async {
    return _post(
      '/attendance/check_in',
      buildAttendanceBody(
        latitude: latitude,
        longitude: longitude,
        faceVerified: faceVerified,
        deviceId: deviceId,
        devLocation: devLocation,
        isMocked: isMocked,
        accuracy: accuracy,
        wifiSsid: wifiSsid,
        wifiBssid: wifiBssid,
      ),
    );
  }

  Future<Map<String, dynamic>> checkOut({
    double? latitude,
    double? longitude,
    bool faceVerified = true,
    String? deviceId,
    bool devLocation = false,
    bool isMocked = false,
    double? accuracy,
    String? wifiSsid,
    String? wifiBssid,
  }) async {
    return _post(
      '/attendance/check_out',
      buildAttendanceBody(
        latitude: latitude,
        longitude: longitude,
        faceVerified: faceVerified,
        deviceId: deviceId,
        devLocation: devLocation,
        isMocked: isMocked,
        accuracy: accuracy,
        wifiSsid: wifiSsid,
        wifiBssid: wifiBssid,
      ),
    );
  }

  // -- Forgot something? (connector 2.54.0+) --

  /// Sends the sheet's answer. True when the server recorded a declaration
  /// (false for the "nothing to declare" answers).
  Future<bool> declare({
    required int attendanceId,
    required String trigger,
    required String answerCode,
    DateTime? declaredTime,
    String note = '',
  }) async {
    final data = await _post(
      '/attendance/declare',
      buildDeclareBody(
        attendanceId: attendanceId,
        trigger: trigger,
        answerCode: answerCode,
        declaredTime: declaredTime,
        note: note,
      ),
    );
    return data['recorded'] == true;
  }

  /// Undoes the punch [attendanceId] inside the server's window and returns
  /// the fresh attendance status, so no second call is needed (spec §3.5).
  Future<AttendanceStatus> undoPunch(int attendanceId) async {
    final data = await _post('/attendance/undo', {
      'attendance_id': attendanceId,
    });
    final status = data['status'];
    return AttendanceStatus.fromJson(
      status is Map ? Map<String, dynamic>.from(status) : <String, dynamic>{},
    );
  }

  /// Answers HR's "Ask the employee" (the existing review/answer route).
  /// [time] (connector 2.55.0) is the corrected time of a
  /// `declared_change` answer, sent as UTC like a declaration's.
  Future<void> answerReview({
    required int notificationId,
    required String answerCode,
    String note = '',
    DateTime? time,
  }) async {
    final trimmed = note.trim();
    await _post('/attendance/review/answer', {
      'notification_id': notificationId,
      'answer_code': answerCode,
      if (trimmed.isNotEmpty) 'note': trimmed,
      if (time != null)
        'time': DateFormat('yyyy-MM-dd HH:mm:ss', 'en_US').format(time.toUtc()),
    });
  }

  Future<List<AttendanceRecord>> getAttendanceHistory() async {
    final data = await _post('/attendance/history');
    final list = (data['attendances'] as List<dynamic>?) ?? const [];
    return list
        .map((e) => AttendanceRecord.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // -- Leave --

  Future<List<LeaveType>> getLeaveTypes() async {
    final data = await _post('/leave/types');
    final list = data['leave_types'] as List<dynamic>;
    return list
        .map((e) => LeaveType.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, dynamic>> applyLeave({
    required int holidayStatusId,
    required String dateFrom,
    required String dateTo,
    String reason = '',
    String? dateFromPeriod,
    String? dateToPeriod,
    double? hourFrom,
    double? hourTo,
    Map<String, dynamic>? attachment,
  }) async {
    return _post('/leave/apply', {
      'holiday_status_id': holidayStatusId,
      'date_from': dateFrom,
      'date_to': dateTo,
      'reason': reason,
      'date_from_period': ?dateFromPeriod,
      'date_to_period': ?dateToPeriod,
      'hour_from': ?hourFrom,
      'hour_to': ?hourTo,
      'attachment': ?attachment,
    });
  }

  // -- Face enrollment --

  Future<Map<String, dynamic>> getEnrolledFace() async {
    return _post('/face/enrolled');
  }

  Future<Map<String, dynamic>> enrollFace({
    required String faceImageBase64,
    String filename = 'enrollment.jpg',
  }) async {
    return _post('/face/enroll', {
      'face_image_base64': faceImageBase64,
      'filename': filename,
    });
  }

  Future<Map<String, dynamic>> clearEnrolledFace() async {
    return _post('/face/clear');
  }

  Future<List<LeaveRecord>> getLeaveHistory() async {
    final data = await _post('/leave/history');
    final list = data['leaves'] as List<dynamic>;
    return list
        .map((e) => LeaveRecord.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, dynamic>> cancelLeave({
    required int leaveId,
    String? reason,
  }) async {
    return _post('/leave/cancel', {
      'leave_id': leaveId,
      if (reason != null && reason.isNotEmpty) 'reason': reason,
    });
  }

  // -- Expenses --

  Future<List<ExpenseCategory>> getExpenseCategories() async {
    final data = await _post('/expense/categories');
    final list = data['categories'] as List<dynamic>? ?? const [];
    return list
        .map((e) => ExpenseCategory.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Active currencies + formatting metadata + informational rates
  /// (connector 2.40.0+, spec §4.1). Returns null when the endpoint
  /// is unavailable — an old connector 404s here — or on any other
  /// failure. Null means "single-currency behavior": the create
  /// screen hides the picker and everything renders as before, so
  /// failing soft is the correct contract, not an error to surface.
  Future<CurrencyListResult?> getCurrencyList() async {
    try {
      final data = await _post('/currency/list');
      return CurrencyListResult.fromJson(data);
    } catch (_) {
      return null;
    }
  }

  /// Fetch one page of the user's expenses. First page omits
  /// `beforeId`; subsequent pages pass the `id` of the oldest row in
  /// the previously-received page. Page size is fixed at 50 server-
  /// side. The returned [ExpenseListPage.hasMore] is `true` when the
  /// server returned a full page (i.e. there may be more).
  Future<ExpenseListPage> getExpenseList({int? beforeId}) async {
    final data = await _post('/expense/list', {'before_id': ?beforeId});
    final list = data['expenses'] as List<dynamic>? ?? const [];
    final records = list
        .map((e) => ExpenseRecord.fromJson(e as Map<String, dynamic>))
        .toList();
    return ExpenseListPage(records: records, hasMore: data['has_more'] == true);
  }

  /// Fetch the bytes of a single expense receipt. Returns the
  /// `{name, mimetype, data_b64}` body the mobile uses for inline
  /// preview / system-viewer hand-off. Mirrors `getAttachment` on
  /// the leave side.
  Future<Map<String, dynamic>> getExpenseAttachment(int attachmentId) {
    return _post('/expense/attachment/get', {'attachment_id': attachmentId});
  }

  /// Modify a submitted (or draft) expense before approval. Server
  /// walks reset → write → submit so the admin sees a fresh submitted
  /// queue item with the new values. Only the fields you pass are
  /// updated. Attachment is preserved if you omit it; passing one
  /// replaces the existing receipt.
  Future<Map<String, dynamic>> modifyExpense({
    required int expenseId,
    int? productId,
    String? name,
    double? totalAmount,
    String? date,
    String? paymentMode,
    int? currencyId,
    String? attachmentName,
    String? attachmentMimeType,
    String? attachmentDataB64,
  }) async {
    final hasAttachment =
        attachmentDataB64 != null && attachmentDataB64.isNotEmpty;
    return _post('/expense/modify', {
      'expense_id': expenseId,
      'product_id': ?productId,
      'name': ?name,
      'total_amount': ?totalAmount,
      'date': ?date,
      'payment_mode': ?paymentMode,
      'currency_id': ?currencyId,
      if (hasAttachment)
        'attachment': {
          'name': attachmentName ?? 'receipt',
          'mimetype': attachmentMimeType ?? 'image/jpeg',
          'data_b64': attachmentDataB64,
        },
    });
  }

  /// Hard-delete a pre-approval expense. Server-side guard rejects
  /// anything past `submitted` state (approved / posted / refused
  /// etc.) with `invalid_state`. Mirrors the existing `_isModifiable`
  /// gate on the detail screen.
  Future<Map<String, dynamic>> deleteExpense(int expenseId) {
    return _post('/expense/delete', {'expense_id': expenseId});
  }

  /// List the employee's published payslips (state in 'done'/'paid').
  /// Drafts and cancelled payslips are filtered out server-side.
  Future<List<PayslipRecord>> getPayslips() async {
    final data = await _post('/payslip/list');
    final list = data['payslips'] as List<dynamic>? ?? const [];
    return list
        .map((e) => PayslipRecord.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Fetch the official PDF bytes for a single payslip. Returns the
  /// `{data_b64, mimetype, filename}` envelope — feed straight into
  /// `openBase64File()` to hand off to the OS PDF viewer. Throws
  /// `ApiException('render_failed')` if Odoo's report engine
  /// (wkhtmltopdf) is missing or unhappy.
  Future<Map<String, dynamic>> getPayslipPdf(int payslipId) {
    return _post('/payslip/pdf/get', {'payslip_id': payslipId});
  }

  /// Submit a single expense. Creates the hr.expense and immediately
  /// flips it to `submitted` via Odoo's action_submit.
  /// `date` should be `yyyy-MM-dd`. Receipt is required by default
  /// — pass `null` attachment fields together with
  /// `devSkipReceipt: true` to bypass (DEV ONLY; the connector logs
  /// every bypass at WARNING).
  Future<Map<String, dynamic>> submitExpense({
    required int productId,
    required String name,
    required double totalAmount,
    required String date,
    String paymentMode = 'own_account',
    int? currencyId,
    String? attachmentName,
    String? attachmentMimeType,
    String? attachmentDataB64,
    bool devSkipReceipt = false,
  }) async {
    final hasAttachment =
        attachmentDataB64 != null && attachmentDataB64.isNotEmpty;
    return _post('/expense/submit', {
      'product_id': productId,
      'name': name,
      'total_amount': totalAmount,
      'date': date,
      'payment_mode': paymentMode,
      'currency_id': ?currencyId,
      if (hasAttachment)
        'attachment': {
          'name': attachmentName ?? 'receipt',
          'mimetype': attachmentMimeType ?? 'image/jpeg',
          'data_b64': attachmentDataB64,
        },
      if (!hasAttachment && devSkipReceipt) '_dev_skip_receipt': true,
    });
  }

  /// Send a receipt image to the connector for OCR auto-fill. The
  /// server validates every field returned by the model — `amount`
  /// is either a finite positive number or null; `suggestedCategoryId`
  /// is either one of the user's actual categories or null; `date` is
  /// either a valid YYYY-MM-DD in a sane window or empty.
  ///
  /// Throws ApiException on `ollama_unreachable`, `ollama_timeout`,
  /// `ollama_bad_response`, `image_too_large`, or `invalid_image`.
  Future<OcrResult> scanReceipt({
    required Uint8List bytes,
    required String mimetype,
  }) async {
    final data = await _post('/expense/ocr_scan', {
      'image_b64': base64Encode(bytes),
      'mimetype': mimetype,
    });
    final result = data['result'] as Map<String, dynamic>? ?? const {};
    return OcrResult.fromJson(result);
  }

  /// Multi-page variant — sends a list of page images (rasterized from a
  /// PDF receipt). The connector OCRs each page and merges the result,
  /// counting the whole call as a single OCR attempt. `pages` must be
  /// non-empty; the connector caps at its own max-pages limit.
  Future<OcrResult> scanReceiptPages({required List<Uint8List> pages}) async {
    final data = await _post('/expense/ocr_scan', {
      'images_b64': [for (final p in pages) base64Encode(p)],
      'mimetype': 'image/jpeg',
    });
    final result = data['result'] as Map<String, dynamic>? ?? const {};
    return OcrResult.fromJson(result);
  }

  Future<CalendarInfoResponse> getPublicHolidays() async {
    final data = await _post('/public_holidays');
    final list = data['holidays'] as List<dynamic>;
    final weekdays =
        (data['working_weekdays'] as List<dynamic>?)
            ?.map((e) => (e as num).toInt())
            .toList() ??
        const [0, 1, 2, 3, 4]; // server convention: Mon=0..Sun=6
    return CalendarInfoResponse(
      holidays: list
          .map((e) => PublicHoliday.fromJson(e as Map<String, dynamic>))
          .toList(),
      workingWeekdays: weekdays,
    );
  }

  Future<Map<String, dynamic>> deleteAttachment(int attachmentId) {
    return _post('/leave/attachment/delete', {'attachment_id': attachmentId});
  }

  Future<Map<String, dynamic>> getAttachment(int attachmentId) {
    return _post('/leave/attachment/get', {'attachment_id': attachmentId});
  }

  /// Duration Odoo would store for a prospective request (connector
  /// 2.41.0+). Nothing is created. On an older connector the route is
  /// missing and this throws an [ApiException] like any other call —
  /// callers keep their local estimate in that case.
  Future<LeaveDurationPreview> previewLeave({
    required int holidayStatusId,
    required String dateFrom,
    required String dateTo,
    String? dateFromPeriod,
    String? dateToPeriod,
    double? hourFrom,
    double? hourTo,
  }) async {
    final data = await _post(
      '/leave/preview',
      buildLeavePreviewBody(
        holidayStatusId: holidayStatusId,
        dateFrom: dateFrom,
        dateTo: dateTo,
        dateFromPeriod: dateFromPeriod,
        dateToPeriod: dateToPeriod,
        hourFrom: hourFrom,
        hourTo: hourTo,
      ),
    );
    return LeaveDurationPreview.fromJson(data);
  }

  Future<Map<String, dynamic>> modifyLeave({
    required int leaveId,
    required String dateFrom,
    required String dateTo,
    required String reason,
    String? dateFromPeriod,
    String? dateToPeriod,
    double? hourFrom,
    double? hourTo,
    Map<String, dynamic>? attachment,
  }) async {
    return _post('/leave/modify', {
      'leave_id': leaveId,
      'date_from': dateFrom,
      'date_to': dateTo,
      'reason': reason,
      'date_from_period': ?dateFromPeriod,
      'date_to_period': ?dateToPeriod,
      'hour_from': ?hourFrom,
      'hour_to': ?hourTo,
      'attachment': ?attachment,
    });
  }

  // -- Leave approvals (connector 2.43.0+) --
  //
  // On an older connector these routes do not exist and every call
  // throws ApiException('server_error'). The app never reaches them
  // there: /me has no `leave_approvals` key, so the entry points stay
  // hidden.

  /// Requests the user can act on now, "my step" first.
  Future<List<ApprovalItem>> getPendingApprovals() async {
    final data = await _post('/leave/approvals/pending');
    return _approvalItems(data);
  }

  /// The user's own decisions of the last 30 days, newest first.
  Future<List<ApprovalItem>> getRecentApprovals() async {
    final data = await _post('/leave/approvals/recent');
    return _approvalItems(data);
  }

  static List<ApprovalItem> _approvalItems(Map<String, dynamic> data) {
    final list = (data['items'] as List<dynamic>?) ?? const [];
    return list
        .whereType<Map>()
        .map((e) => ApprovalItem.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// One request with everything needed to decide. Throws
  /// ApiException('not_found') when it is gone or not visible to the user.
  Future<ApprovalDetail> getApprovalDetail(int leaveId) async {
    final data = await _post('/leave/approvals/get', {'leave_id': leaveId});
    final leave = data['leave'];
    return ApprovalDetail.fromJson(
      leave is Map ? Map<String, dynamic>.from(leave) : <String, dynamic>{},
    );
  }

  /// Approve as the signed-in user. Returns the new Odoo state
  /// ('validate1' when HR still has to approve, else 'validate').
  Future<String> approveLeave({
    required int leaveId,
    required String expectedState,
  }) async {
    final data = await _post(
      '/leave/approvals/approve',
      buildApproveBody(leaveId: leaveId, expectedState: expectedState),
    );
    return data['state']?.toString() ?? '';
  }

  /// Refuse as the signed-in user; [reason] is posted to the request's
  /// chatter. Returns the new Odoo state ('refuse').
  Future<String> refuseLeave({
    required int leaveId,
    required String expectedState,
    required String reason,
  }) async {
    final data = await _post(
      '/leave/approvals/refuse',
      buildRefuseBody(
        leaveId: leaveId,
        expectedState: expectedState,
        reason: reason,
      ),
    );
    return data['state']?.toString() ?? '';
  }
}

class CalendarInfoResponse {
  final List<PublicHoliday> holidays;
  final List<int> workingWeekdays; // Odoo: Mon=0..Sun=6

  CalendarInfoResponse({required this.holidays, required this.workingWeekdays});
}

/// One page of the user's expenses, returned by [OmniMobileApi.getExpenseList].
/// `hasMore` is `true` when the server returned a full page — call
/// `getExpenseList(beforeId: records.last.id)` to fetch the next page.
class ExpenseListPage {
  final List<ExpenseRecord> records;
  final bool hasMore;

  ExpenseListPage({required this.records, required this.hasMore});
}

class ApiException implements Exception {
  /// Server-side error code, e.g. "outside_geofence",
  /// "office_geofence_not_configured", "face_not_verified".
  final String errorCode;

  /// Whole response body for inspection by the UI.
  final Map<String, dynamic>? data;

  /// Populated for outside_geofence — meters from office at submit time.
  final double? distanceFromOffice;

  /// Populated for outside_geofence — meters of allowed radius.
  final double? allowedRadius;

  ApiException(
    this.errorCode, {
    this.data,
    this.distanceFromOffice,
    this.allowedRadius,
  });

  /// Backwards-compatible getter for callers that still inspect
  /// `e.toString()` for keyword matching.
  String get error => errorCode;

  factory ApiException.fromBody(Map<String, dynamic> body) {
    final code = body['error']?.toString() ?? 'Unknown error';
    return ApiException(
      code,
      data: body,
      distanceFromOffice: (body['distance_from_office'] as num?)?.toDouble(),
      allowedRadius: (body['allowed_radius'] as num?)?.toDouble(),
    );
  }

  @override
  String toString() => errorCode;
}
