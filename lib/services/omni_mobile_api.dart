import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../models/attendance_record.dart';
import '../models/attendance_status.dart';
import '../models/leave_type.dart';
import '../models/expense_record.dart';
import '../models/leave_record.dart';
import '../models/notification_record.dart';
import '../models/ocr_result.dart';
import '../models/payslip_record.dart';
import '../models/public_holiday.dart';

class OmniMobileApi {
  final String baseUrl;
  final String db;
  final String token;

  OmniMobileApi({
    required this.baseUrl,
    required this.db,
    required this.token,
  });

  /// Wired in main.dart at app boot. Called whenever any /api/v1/...
  /// call returns `error: invalid_session` (or the legacy alias
  /// `invalid_token`). Typical wiring: SessionService.clearSession,
  /// which causes the top-level `Consumer<SessionService>` in
  /// OmniHrApp to re-render and route the user back to LoginScreen.
  static void Function()? onInvalidSession;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (token.isNotEmpty) 'Authorization': 'Bearer $token',
      };

  Uri _uri(String path) =>
      Uri.parse('$baseUrl/api/v1/omni_mobile$path?db=$db');

  Future<Map<String, dynamic>> _post(String path,
      [Map<String, dynamic>? body]) async {
    // 30s timeout so the UI can't hang forever if the server stops
    // responding cleanly (Android symptom: CHECK OUT button stuck on
    // SCANNING…). 30s is generous enough for cellular + a real
    // geofence/overtime computation on the connector.
    final http.Response response;
    try {
      response = await http.post(
        _uri(path),
        headers: _headers,
        body: jsonEncode(body ?? {}),
      ).timeout(
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
      throw ApiException.fromBody(data);
    }
    return data;
  }

  // -- Auth --

  Future<Map<String, dynamic>> login({
    required String login,
    required String password,
    String? deviceId,
    String? appVersion,
  }) async {
    return _post('/login', {
      'login': login,
      'password': password,
      'device_id': ?deviceId,
      'app_version': ?appVersion,
    });
  }

  Future<Map<String, dynamic>> logout() async {
    return _post('/logout');
  }

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

  // -- Notifications --

  Future<List<NotificationRecord>> getNotifications() async {
    final data = await _post('/notifications/list');
    final list = (data['notifications'] as List<dynamic>?) ?? const [];
    return list
        .map((e) =>
            NotificationRecord.fromJson(e as Map<String, dynamic>))
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
  }) async {
    // latitude/longitude are omitted (not sent as JSON null) when the
    // SaaS geolocation flag is off — the connector treats absence of
    // coords as "skip geofence". See controllers/main.py check_in.
    return _post('/attendance/check_in', {
      'latitude': ?latitude,
      'longitude': ?longitude,
      'face_verified': faceVerified,
      'device_id': ?deviceId,
      // Server bypasses geofence when this flag is set. Only sent
      // when DevConstants.useDevLocation is true. Server logs a
      // warning per call so dev usage is auditable.
      if (devLocation) '_dev_location': true,
    });
  }

  Future<Map<String, dynamic>> checkOut({
    double? latitude,
    double? longitude,
    bool faceVerified = true,
    String? deviceId,
    bool devLocation = false,
  }) async {
    return _post('/attendance/check_out', {
      'latitude': ?latitude,
      'longitude': ?longitude,
      'face_verified': faceVerified,
      'device_id': ?deviceId,
      if (devLocation) '_dev_location': true,
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

  /// Fetch one page of the user's expenses. First page omits
  /// `beforeId`; subsequent pages pass the `id` of the oldest row in
  /// the previously-received page. Page size is fixed at 50 server-
  /// side. The returned [ExpenseListPage.hasMore] is `true` when the
  /// server returned a full page (i.e. there may be more).
  Future<ExpenseListPage> getExpenseList({int? beforeId}) async {
    final data = await _post('/expense/list', {
      'before_id': ?beforeId,
    });
    final list = data['expenses'] as List<dynamic>? ?? const [];
    final records = list
        .map((e) => ExpenseRecord.fromJson(e as Map<String, dynamic>))
        .toList();
    return ExpenseListPage(
      records: records,
      hasMore: data['has_more'] == true,
    );
  }

  /// Fetch the bytes of a single expense receipt. Returns the
  /// `{name, mimetype, data_b64}` body the mobile uses for inline
  /// preview / system-viewer hand-off. Mirrors `getAttachment` on
  /// the leave side.
  Future<Map<String, dynamic>> getExpenseAttachment(int attachmentId) {
    return _post('/expense/attachment/get',
        {'attachment_id': attachmentId});
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
    String? attachmentName,
    String? attachmentMimeType,
    String? attachmentDataB64,
    bool devSkipReceipt = false,
  }) async {
    final hasAttachment = attachmentDataB64 != null &&
        attachmentDataB64.isNotEmpty;
    return _post('/expense/submit', {
      'product_id': productId,
      'name': name,
      'total_amount': totalAmount,
      'date': date,
      'payment_mode': paymentMode,
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

  Future<CalendarInfoResponse> getPublicHolidays() async {
    final data = await _post('/public_holidays');
    final list = data['holidays'] as List<dynamic>;
    final weekdays = (data['working_weekdays'] as List<dynamic>?)
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
}

class CalendarInfoResponse {
  final List<PublicHoliday> holidays;
  final List<int> workingWeekdays; // Odoo: Mon=0..Sun=6

  CalendarInfoResponse({
    required this.holidays,
    required this.workingWeekdays,
  });
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
      distanceFromOffice:
          (body['distance_from_office'] as num?)?.toDouble(),
      allowedRadius: (body['allowed_radius'] as num?)?.toDouble(),
    );
  }

  @override
  String toString() => errorCode;
}
