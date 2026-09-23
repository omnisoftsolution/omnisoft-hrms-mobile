Map<String, dynamic> buildLoginBody({
  required String login,
  required String password,
  String? deviceId,
  String? deviceLabel,
  String? appVersion,
  String? emailCode,
}) =>
    {
      // Trim only: Odoo matches res.users.login case-sensitively, so a
      // mixed-case login must reach /login exactly as the user has it.
      'login': login.trim(),
      'password': password,
      'device_id': ?deviceId,
      if (deviceLabel != null && deviceLabel.isNotEmpty)
        'device_label': deviceLabel,
      'app_version': ?appVersion,
      if (emailCode != null && emailCode.isNotEmpty) 'email_code': emailCode,
    };

Map<String, dynamic> buildActivateBody({
  required String login,
  String? token,
  String? code,
  required String password,
  required String deviceId,
  String? deviceLabel,
  String? appVersion,
}) =>
    {
      'login': login.trim().toLowerCase(),
      if (token != null && token.isNotEmpty)
        'token': token
      else
        'code': ?code,
      'password': password,
      'device_id': deviceId,
      if (deviceLabel != null && deviceLabel.isNotEmpty)
        'device_label': deviceLabel,
      'app_version': ?appVersion,
    };

Map<String, dynamic> buildRefreshBody({
  required String refreshToken,
  required String deviceId,
}) =>
    {
      'refresh_token': refreshToken,
      'device_id': deviceId,
    };
