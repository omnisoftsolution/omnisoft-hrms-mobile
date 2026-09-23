Map<String, dynamic> buildLoginBody({
  required String login,
  required String password,
  String? deviceId,
  String? deviceLabel,
  String? appVersion,
  String? emailCode,
}) =>
    {
      'login': login.trim().toLowerCase(),
      'password': password,
      if (deviceId != null) 'device_id': deviceId,
      if (deviceLabel != null && deviceLabel.isNotEmpty)
        'device_label': deviceLabel,
      if (appVersion != null) 'app_version': appVersion,
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
      else if (code != null)
        'code': code,
      'password': password,
      'device_id': deviceId,
      if (deviceLabel != null && deviceLabel.isNotEmpty)
        'device_label': deviceLabel,
      if (appVersion != null) 'app_version': appVersion,
    };

Map<String, dynamic> buildRefreshBody({
  required String refreshToken,
  required String deviceId,
}) =>
    {
      'refresh_token': refreshToken,
      'device_id': deviceId,
    };
