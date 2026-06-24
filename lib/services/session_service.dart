import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'saas_service.dart';

/// Session state for the mobile app. Persists across launches.
///
/// Layout:
/// - SaaS routing (saasUrl, companyCode, clientUrl, clientDb) survives
///   logout — re-login on the same device should not require re-typing
///   the company code.
/// - Login session (accessToken, expiresAt, userLogin, userName,
///   employeeId, employeeName) is wiped on logout or when the server
///   returns invalid_session.
class SessionService extends ChangeNotifier {
  final FlutterSecureStorage _secure = const FlutterSecureStorage();

  // Keys: SaaS routing (kept across logout)
  static const _keySaasUrl = 'saas_url';
  static const _keyCompanyCode = 'company_code';
  static const _keyClientUrl = 'client_url';
  static const _keyClientDb = 'client_db';
  // SaaS-side subscription feature flags. Persisted with company
  // routing — they come from /resolve_company, not from /login.
  // Default true so a fresh install (or upgrade from a previous build
  // that didn't store these) doesn't accidentally lock the user out.
  static const _keyFeatAttendance = 'feature_attendance';
  static const _keyFeatTimeOff = 'feature_time_off';
  static const _keyFeatFaceVerification = 'feature_face_verification';
  static const _keyFeatGeolocation = 'feature_geolocation';
  static const _keyFeatPayroll = 'feature_payroll';
  static const _keyFeatExpenses = 'feature_expenses';
  static const _keyFeatExpenseOcr = 'feature_expense_ocr';
  static const _keyCompanyName = 'company_name';
  static const _keyCompanyLogoB64 = 'company_logo_b64';
  static const _keyShowConnectionDetails = 'show_connection_details';

  // Keys: login session (cleared on logout)
  static const _keyAccessToken = 'access_token';
  static const _keyExpiresAt = 'expires_at';
  static const _keyUserId = 'user_id';
  static const _keyUserLogin = 'user_login';
  static const _keyUserName = 'user_name';
  static const _keyEmployeeId = 'employee_id';
  static const _keyEmployeeName = 'employee_name';
  static const _keyEmployeeAvatarB64 = 'employee_avatar_b64';
  static const _keyEmployeeJobTitle = 'employee_job_title';
  static const _keyEmployeeJobPosition = 'employee_job_position';
  static const _keyEmployeeDepartment = 'employee_department';
  static const _keyEmployeeManager = 'employee_manager';
  static const _keyEmployeeWorkEmail = 'employee_work_email';
  static const _keyEmployeeWorkPhone = 'employee_work_phone';
  static const _keyEmployeeCompanyName = 'employee_company_name';
  static const _keyEmployeeCompanyLogoB64 = 'employee_company_logo_b64';
  static const _keyEmployeeHrApprover = 'employee_hr_approver';
  static const _keyEmployeeTimeOffApprover = 'employee_time_off_approver';
  static const _keyEmployeeAttendanceApprover =
      'employee_attendance_approver';
  static const _keyEmployeeExpenseApprover = 'employee_expense_approver';

  String _saasUrl = '';
  String _companyCode = '';
  String _clientUrl = '';
  String _clientDb = '';
  bool _featureAttendance = true;
  bool _featureTimeOff = true;
  bool _featureFaceVerification = true;
  bool _featureGeolocation = true;
  bool _featurePayroll = false;
  bool _featureExpenses = false;
  bool _featureExpenseOcr = true;
  String _companyName = '';
  String _companyLogoB64 = '';
  bool _showConnectionDetails = false;

  String _accessToken = '';
  DateTime? _expiresAt;
  int _userId = 0;
  String _userLogin = '';
  String _userName = '';
  int _employeeId = 0;
  String _employeeName = '';
  String _employeeAvatarB64 = '';
  String _employeeJobTitle = '';
  String _employeeJobPosition = '';
  String _employeeDepartment = '';
  String _employeeManager = '';
  String _employeeWorkEmail = '';
  String _employeeWorkPhone = '';
  String _employeeCompanyName = '';
  String _employeeCompanyLogoB64 = '';
  String _employeeHrApprover = '';
  String _employeeTimeOffApprover = '';
  String _employeeAttendanceApprover = '';
  String _employeeExpenseApprover = '';

  // SaaS routing
  String get saasUrl => _saasUrl;
  String get companyCode => _companyCode;
  String get clientUrl => _clientUrl;
  String get clientDb => _clientDb;

  // SaaS subscription features. UI-only gating today — server-side
  // enforcement is a separate hardening pass.
  bool get featureAttendance => _featureAttendance;
  bool get featureTimeOff => _featureTimeOff;
  bool get featureFaceVerification => _featureFaceVerification;
  bool get featureGeolocation => _featureGeolocation;
  bool get featurePayroll => _featurePayroll;
  bool get featureExpenses => _featureExpenses;
  bool get featureExpenseOcr => _featureExpenseOcr;

  // Company branding (from resolve_company, pre-login)
  String get companyName => _companyName;
  String get companyLogoB64 => _companyLogoB64;
  bool get showConnectionDetails => _showConnectionDetails;

  // Auth session
  String get accessToken => _accessToken;
  /// Back-compat alias used by existing call sites.
  String get token => _accessToken;
  DateTime? get expiresAt => _expiresAt;
  int get userId => _userId;
  String get userLogin => _userLogin;
  String get userName => _userName;
  int get employeeId => _employeeId;
  String get employeeName => _employeeName;
  String get employeeAvatarB64 => _employeeAvatarB64;
  String get employeeJobTitle => _employeeJobTitle;
  String get employeeJobPosition => _employeeJobPosition;
  String get employeeDepartment => _employeeDepartment;
  String get employeeManager => _employeeManager;
  String get employeeWorkEmail => _employeeWorkEmail;
  String get employeeWorkPhone => _employeeWorkPhone;
  String get employeeCompanyName => _employeeCompanyName;
  String get employeeCompanyLogoB64 => _employeeCompanyLogoB64;
  String get employeeHrApprover => _employeeHrApprover;
  String get employeeTimeOffApprover => _employeeTimeOffApprover;
  String get employeeAttendanceApprover => _employeeAttendanceApprover;
  String get employeeExpenseApprover => _employeeExpenseApprover;

  bool get isLoggedIn =>
      _accessToken.isNotEmpty &&
      _clientUrl.isNotEmpty &&
      (_expiresAt == null || _expiresAt!.isAfter(DateTime.now()));

  bool get hasCompany => _clientUrl.isNotEmpty && _companyCode.isNotEmpty;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _saasUrl = prefs.getString(_keySaasUrl) ?? '';
    _companyCode = prefs.getString(_keyCompanyCode) ?? '';
    _clientUrl = prefs.getString(_keyClientUrl) ?? '';
    _clientDb = prefs.getString(_keyClientDb) ?? '';
    _featureAttendance = prefs.getBool(_keyFeatAttendance) ?? true;
    _featureTimeOff = prefs.getBool(_keyFeatTimeOff) ?? true;
    _featureFaceVerification =
        prefs.getBool(_keyFeatFaceVerification) ?? true;
    _featureGeolocation = prefs.getBool(_keyFeatGeolocation) ?? true;
    _featurePayroll = prefs.getBool(_keyFeatPayroll) ?? false;
    _featureExpenses = prefs.getBool(_keyFeatExpenses) ?? false;
    _featureExpenseOcr = prefs.getBool(_keyFeatExpenseOcr) ?? true;
    _companyName = prefs.getString(_keyCompanyName) ?? '';
    _companyLogoB64 = prefs.getString(_keyCompanyLogoB64) ?? '';
    _showConnectionDetails =
        prefs.getBool(_keyShowConnectionDetails) ?? false;
    _accessToken = await _readTokenWithMigration(prefs);
    final exp = prefs.getString(_keyExpiresAt);
    _expiresAt = exp != null && exp.isNotEmpty ? DateTime.tryParse(exp) : null;
    _userId = prefs.getInt(_keyUserId) ?? 0;
    _userLogin = prefs.getString(_keyUserLogin) ?? '';
    _userName = prefs.getString(_keyUserName) ?? '';
    _employeeId = prefs.getInt(_keyEmployeeId) ?? 0;
    _employeeName = prefs.getString(_keyEmployeeName) ?? '';
    _employeeAvatarB64 = prefs.getString(_keyEmployeeAvatarB64) ?? '';
    _employeeJobTitle = prefs.getString(_keyEmployeeJobTitle) ?? '';
    _employeeJobPosition = prefs.getString(_keyEmployeeJobPosition) ?? '';
    _employeeDepartment = prefs.getString(_keyEmployeeDepartment) ?? '';
    _employeeManager = prefs.getString(_keyEmployeeManager) ?? '';
    _employeeWorkEmail = prefs.getString(_keyEmployeeWorkEmail) ?? '';
    _employeeWorkPhone = prefs.getString(_keyEmployeeWorkPhone) ?? '';
    _employeeCompanyName = prefs.getString(_keyEmployeeCompanyName) ?? '';
    _employeeCompanyLogoB64 =
        prefs.getString(_keyEmployeeCompanyLogoB64) ?? '';
    _employeeHrApprover = prefs.getString(_keyEmployeeHrApprover) ?? '';
    _employeeTimeOffApprover =
        prefs.getString(_keyEmployeeTimeOffApprover) ?? '';
    _employeeAttendanceApprover =
        prefs.getString(_keyEmployeeAttendanceApprover) ?? '';
    _employeeExpenseApprover =
        prefs.getString(_keyEmployeeExpenseApprover) ?? '';
    notifyListeners();
  }

  /// Reads the bearer token, migrating a legacy SharedPreferences entry
  /// into secure storage on first run. A failed secure read returns ''
  /// (treated as logged-out) rather than crashing.
  Future<String> _readTokenWithMigration(SharedPreferences prefs) async {
    try {
      final secureToken = await _secure.read(key: _keyAccessToken);
      if (secureToken != null && secureToken.isNotEmpty) {
        return secureToken;
      }
      // Migrate a legacy plaintext token, if any, then drop it.
      final legacy = prefs.getString(_keyAccessToken);
      if (legacy != null && legacy.isNotEmpty) {
        await _secure.write(key: _keyAccessToken, value: legacy);
        await prefs.remove(_keyAccessToken);
        return legacy;
      }
      return '';
    } catch (_) {
      // Secure storage unavailable (e.g. device without secure enclave in
      // tests) — treat as logged-out rather than crashing.
      return '';
    }
  }

  Future<void> saveCompany({
    required String saasUrl,
    required String companyCode,
    required String clientUrl,
    String clientDb = '',
    Map<String, bool>? features,
    String companyName = '',
    String companyLogoB64 = '',
    bool showConnectionDetails = false,
  }) async {
    _saasUrl = saasUrl;
    _companyCode = companyCode;
    _clientUrl = clientUrl;
    _clientDb = clientDb;
    _companyName = companyName;
    _companyLogoB64 = companyLogoB64;
    _showConnectionDetails = showConnectionDetails;
    if (features != null) {
      // Default to current value when a key is missing — leaves
      // existing flags untouched if SaaS payload is partial.
      _featureAttendance =
          features['attendance'] ?? _featureAttendance;
      _featureTimeOff = features['time_off'] ?? _featureTimeOff;
      _featureFaceVerification =
          features['face_verification'] ?? _featureFaceVerification;
      _featureGeolocation =
          features['geolocation'] ?? _featureGeolocation;
      _featurePayroll = features['payroll'] ?? _featurePayroll;
      _featureExpenses = features['expenses'] ?? _featureExpenses;
      _featureExpenseOcr =
          features['expense_ocr'] ?? _featureExpenseOcr;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySaasUrl, saasUrl);
    await prefs.setString(_keyCompanyCode, companyCode);
    await prefs.setString(_keyClientUrl, clientUrl);
    await prefs.setString(_keyClientDb, clientDb);
    await prefs.setBool(_keyFeatAttendance, _featureAttendance);
    await prefs.setBool(_keyFeatTimeOff, _featureTimeOff);
    await prefs.setBool(
        _keyFeatFaceVerification, _featureFaceVerification);
    await prefs.setBool(_keyFeatGeolocation, _featureGeolocation);
    await prefs.setBool(_keyFeatPayroll, _featurePayroll);
    await prefs.setBool(_keyFeatExpenses, _featureExpenses);
    await prefs.setBool(_keyFeatExpenseOcr, _featureExpenseOcr);
    await prefs.setString(_keyCompanyName, _companyName);
    await prefs.setString(_keyCompanyLogoB64, _companyLogoB64);
    await prefs.setBool(_keyShowConnectionDetails, _showConnectionDetails);
    notifyListeners();
  }

  /// Re-resolve the company from the SaaS and refresh cached feature
  /// flags. Silent no-op when no company is configured or when the
  /// SaaS is unreachable — cached features stay, so a network blip
  /// can never lock a working session. Used by:
  /// - main.dart cold-start + lifecycle resume hooks
  /// - HomeShell on Leave / Expenses tab tap (snappier dev iteration)
  /// - the manual "Refresh Subscription" button on FeatureLockedPane.
  Future<void> refreshSubscription() async {
    if (_saasUrl.isEmpty || _companyCode.isEmpty) return;
    try {
      final info =
          await SaasService().resolveCompany(_saasUrl, _companyCode);
      await saveCompany(
        saasUrl: _saasUrl,
        companyCode: info.companyCode,
        clientUrl: info.odooUrl,
        clientDb: info.database,
        features: info.features,
        companyName: info.name,
        companyLogoB64: info.companyLogoB64,
        showConnectionDetails: info.showConnectionDetails,
      );
    } catch (_) {
      // Silent — admin / SaaS downtime should never lock a working
      // session.
    }
  }

  /// Persist everything returned by /login in one call.
  Future<void> saveSession({
    required String accessToken,
    DateTime? expiresAt,
    required int userId,
    required String userLogin,
    required String userName,
    required int employeeId,
    required String employeeName,
    String employeeAvatarB64 = '',
    String employeeJobTitle = '',
    String employeeJobPosition = '',
    String employeeDepartment = '',
    String employeeManager = '',
    String employeeWorkEmail = '',
    String employeeWorkPhone = '',
    String employeeCompanyName = '',
    String employeeCompanyLogoB64 = '',
    String employeeHrApprover = '',
    String employeeTimeOffApprover = '',
    String employeeAttendanceApprover = '',
    String employeeExpenseApprover = '',
  }) async {
    _accessToken = accessToken;
    _expiresAt = expiresAt;
    _userId = userId;
    _userLogin = userLogin;
    _userName = userName;
    _employeeId = employeeId;
    _employeeName = employeeName;
    _employeeAvatarB64 = employeeAvatarB64;
    _employeeJobTitle = employeeJobTitle;
    _employeeJobPosition = employeeJobPosition;
    _employeeDepartment = employeeDepartment;
    _employeeManager = employeeManager;
    _employeeWorkEmail = employeeWorkEmail;
    _employeeWorkPhone = employeeWorkPhone;
    _employeeCompanyName = employeeCompanyName;
    _employeeCompanyLogoB64 = employeeCompanyLogoB64;
    _employeeHrApprover = employeeHrApprover;
    _employeeTimeOffApprover = employeeTimeOffApprover;
    _employeeAttendanceApprover = employeeAttendanceApprover;
    _employeeExpenseApprover = employeeExpenseApprover;
    final prefs = await SharedPreferences.getInstance();
    await _secure.write(key: _keyAccessToken, value: accessToken);
    await prefs.remove(_keyAccessToken);
    await prefs.setString(_keyExpiresAt, expiresAt?.toIso8601String() ?? '');
    await prefs.setInt(_keyUserId, userId);
    await prefs.setString(_keyUserLogin, userLogin);
    await prefs.setString(_keyUserName, userName);
    await prefs.setInt(_keyEmployeeId, employeeId);
    await prefs.setString(_keyEmployeeName, employeeName);
    await prefs.setString(_keyEmployeeAvatarB64, employeeAvatarB64);
    await prefs.setString(_keyEmployeeJobTitle, employeeJobTitle);
    await prefs.setString(_keyEmployeeJobPosition, employeeJobPosition);
    await prefs.setString(_keyEmployeeDepartment, employeeDepartment);
    await prefs.setString(_keyEmployeeManager, employeeManager);
    await prefs.setString(_keyEmployeeWorkEmail, employeeWorkEmail);
    await prefs.setString(_keyEmployeeWorkPhone, employeeWorkPhone);
    await prefs.setString(_keyEmployeeCompanyName, employeeCompanyName);
    await prefs.setString(
        _keyEmployeeCompanyLogoB64, employeeCompanyLogoB64);
    await prefs.setString(_keyEmployeeHrApprover, employeeHrApprover);
    await prefs.setString(
        _keyEmployeeTimeOffApprover, employeeTimeOffApprover);
    await prefs.setString(
        _keyEmployeeAttendanceApprover, employeeAttendanceApprover);
    await prefs.setString(
        _keyEmployeeExpenseApprover, employeeExpenseApprover);
    notifyListeners();
  }

  /// Refresh employee + approver fields from a /me response without
  /// touching auth (token, expiresAt, userId, userLogin). Used by
  /// _refreshMeInBackground on app start + resume so HR-side edits
  /// (manager change, new approver, etc.) flow into the app without
  /// a logout cycle.
  Future<void> updateEmployeeFromMe({
    String? userName,
    int? employeeId,
    String? employeeName,
    String? employeeAvatarB64,
    String? employeeJobTitle,
    String? employeeJobPosition,
    String? employeeDepartment,
    String? employeeManager,
    String? employeeWorkEmail,
    String? employeeWorkPhone,
    String? employeeCompanyName,
    String? employeeCompanyLogoB64,
    String? employeeHrApprover,
    String? employeeTimeOffApprover,
    String? employeeAttendanceApprover,
    String? employeeExpenseApprover,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (userName != null) {
      _userName = userName;
      await prefs.setString(_keyUserName, userName);
    }
    if (employeeId != null) {
      _employeeId = employeeId;
      await prefs.setInt(_keyEmployeeId, employeeId);
    }
    if (employeeName != null) {
      _employeeName = employeeName;
      await prefs.setString(_keyEmployeeName, employeeName);
    }
    if (employeeAvatarB64 != null) {
      _employeeAvatarB64 = employeeAvatarB64;
      await prefs.setString(_keyEmployeeAvatarB64, employeeAvatarB64);
    }
    if (employeeJobTitle != null) {
      _employeeJobTitle = employeeJobTitle;
      await prefs.setString(_keyEmployeeJobTitle, employeeJobTitle);
    }
    if (employeeJobPosition != null) {
      _employeeJobPosition = employeeJobPosition;
      await prefs.setString(_keyEmployeeJobPosition, employeeJobPosition);
    }
    if (employeeDepartment != null) {
      _employeeDepartment = employeeDepartment;
      await prefs.setString(_keyEmployeeDepartment, employeeDepartment);
    }
    if (employeeManager != null) {
      _employeeManager = employeeManager;
      await prefs.setString(_keyEmployeeManager, employeeManager);
    }
    if (employeeWorkEmail != null) {
      _employeeWorkEmail = employeeWorkEmail;
      await prefs.setString(_keyEmployeeWorkEmail, employeeWorkEmail);
    }
    if (employeeWorkPhone != null) {
      _employeeWorkPhone = employeeWorkPhone;
      await prefs.setString(_keyEmployeeWorkPhone, employeeWorkPhone);
    }
    if (employeeCompanyName != null) {
      _employeeCompanyName = employeeCompanyName;
      await prefs.setString(_keyEmployeeCompanyName, employeeCompanyName);
    }
    if (employeeCompanyLogoB64 != null) {
      _employeeCompanyLogoB64 = employeeCompanyLogoB64;
      await prefs.setString(
          _keyEmployeeCompanyLogoB64, employeeCompanyLogoB64);
    }
    if (employeeHrApprover != null) {
      _employeeHrApprover = employeeHrApprover;
      await prefs.setString(_keyEmployeeHrApprover, employeeHrApprover);
    }
    if (employeeTimeOffApprover != null) {
      _employeeTimeOffApprover = employeeTimeOffApprover;
      await prefs.setString(
          _keyEmployeeTimeOffApprover, employeeTimeOffApprover);
    }
    if (employeeAttendanceApprover != null) {
      _employeeAttendanceApprover = employeeAttendanceApprover;
      await prefs.setString(
          _keyEmployeeAttendanceApprover, employeeAttendanceApprover);
    }
    if (employeeExpenseApprover != null) {
      _employeeExpenseApprover = employeeExpenseApprover;
      await prefs.setString(
          _keyEmployeeExpenseApprover, employeeExpenseApprover);
    }
    notifyListeners();
  }

  /// Clear only the auth session keys. SaaS routing stays so re-login
  /// doesn't require re-entering the company code.
  Future<void> clearSession() async {
    _accessToken = '';
    _expiresAt = null;
    _userId = 0;
    _userLogin = '';
    _userName = '';
    _employeeId = 0;
    _employeeName = '';
    _employeeAvatarB64 = '';
    _employeeJobTitle = '';
    _employeeJobPosition = '';
    _employeeDepartment = '';
    _employeeManager = '';
    _employeeWorkEmail = '';
    _employeeWorkPhone = '';
    _employeeCompanyName = '';
    _employeeCompanyLogoB64 = '';
    _employeeHrApprover = '';
    _employeeTimeOffApprover = '';
    _employeeAttendanceApprover = '';
    _employeeExpenseApprover = '';
    final prefs = await SharedPreferences.getInstance();
    await _secure.delete(key: _keyAccessToken);
    await prefs.remove(_keyAccessToken);
    await prefs.remove(_keyExpiresAt);
    await prefs.remove(_keyUserId);
    await prefs.remove(_keyUserLogin);
    await prefs.remove(_keyUserName);
    await prefs.remove(_keyEmployeeId);
    await prefs.remove(_keyEmployeeName);
    await prefs.remove(_keyEmployeeAvatarB64);
    await prefs.remove(_keyEmployeeJobTitle);
    await prefs.remove(_keyEmployeeJobPosition);
    await prefs.remove(_keyEmployeeDepartment);
    await prefs.remove(_keyEmployeeManager);
    await prefs.remove(_keyEmployeeWorkEmail);
    await prefs.remove(_keyEmployeeWorkPhone);
    await prefs.remove(_keyEmployeeCompanyName);
    await prefs.remove(_keyEmployeeCompanyLogoB64);
    await prefs.remove(_keyEmployeeHrApprover);
    await prefs.remove(_keyEmployeeTimeOffApprover);
    await prefs.remove(_keyEmployeeAttendanceApprover);
    await prefs.remove(_keyEmployeeExpenseApprover);
    notifyListeners();
  }

  /// Full reset (clears SaaS routing too). Used when the user wants to
  /// switch companies entirely.
  Future<void> logout() async {
    _saasUrl = '';
    _companyCode = '';
    _clientUrl = '';
    _clientDb = '';
    await clearSession();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keySaasUrl);
    await prefs.remove(_keyCompanyCode);
    await prefs.remove(_keyClientUrl);
    await prefs.remove(_keyClientDb);
    notifyListeners();
  }
}
