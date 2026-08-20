/// Outcome of a one-shot Wi-Fi info read for the attendance network
/// gate. Mirrors LocationResult: a status enum plus normalized values,
/// so callers never see platform sentinels or quote-wrapping.
enum WifiInfoStatus { ready, notConnected, unreadable }

class WifiInfoResult {
  final WifiInfoStatus status;

  /// Normalized SSID (quotes stripped) — null unless [isReady].
  final String? ssid;

  /// Normalized lowercase zero-padded BSSID; may be null even when
  /// ready (recent iOS cannot report one).
  final String? bssid;

  final String? errorMessage;

  const WifiInfoResult._(this.status, {this.ssid, this.bssid, this.errorMessage});

  const WifiInfoResult.ready({required String ssid, String? bssid})
      : this._(WifiInfoStatus.ready, ssid: ssid, bssid: bssid);

  const WifiInfoResult.notConnected()
      : this._(WifiInfoStatus.notConnected);

  const WifiInfoResult.unreadable(String message)
      : this._(WifiInfoStatus.unreadable, errorMessage: message);

  bool get isReady => status == WifiInfoStatus.ready;
}
