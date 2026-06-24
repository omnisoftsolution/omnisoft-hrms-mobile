import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/constants.dart';
import '../../core/datetime_utils.dart';
import '../../core/theme.dart';
import '../../models/attendance_status.dart';
import '../../models/auto_close_previous.dart';
import '../../models/face_capture_result.dart';
import '../../services/device_service.dart';
import '../../services/face_recognition_service.dart';
import '../../services/location_service.dart';
import '../../services/omni_mobile_api.dart';
import '../../services/session_service.dart';
import '../../widgets/big_check_button.dart';
import '../../widgets/error_state_view.dart';
import '../../widgets/feature_locked_pane.dart';
import '../../widgets/info_card.dart';
import '../../widgets/omni_app_bar.dart';
import '../../widgets/silent_face_capture.dart';
import '../face_scan/face_enrollment_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  AttendanceStatus? _status;
  /// Wallclock timestamp of the last successful status fetch. Used
  /// to project HOURS TODAY forward while the user is still checked
  /// in (server's value is fresh-as-of-fetch only).
  DateTime? _statusFetchedAt;
  bool _loading = true;
  String? _error;
  bool _acting = false;
  // Last outside-geofence error info — kept on screen until the next
  // successful check-in/out. null when not applicable.
  double? _lastDistance;
  double? _lastAllowedRadius;
  // Set when the connector's Phase 1 forgotten-check-out guard had
  // to auto-close a stale attendance during this check-in. Renders
  // a yellow banner card; cleared on dismiss or next successful
  // check-out.
  AutoClosePrevious? _autoClosedPrevious;
  final _locationService = LocationService();
  final _deviceService = DeviceService();

  // Live ticking for the Current Time card. Updates every 30s — we
  // only render HH:MM so per-second precision is wasted.
  Timer? _clockTimer;
  DateTime _now = DateTime.now();

  // Inline face-capture state. When true, BigCheckButton swaps for
  // InlineFaceCapture in-place — same dimensions, no layout shift.
  // _captureCompleter is how _onCheckAction awaits the capture result;
  // InlineFaceCapture's onResult callback completes the future and
  // flips this flag back to false.
  bool _faceCapturing = false;
  Completer<FaceCaptureResult>? _captureCompleter;

  // GPS distance polling for the GPS Status card. Updates every 60s.
  Timer? _gpsTimer;
  double? _currentDistanceMeters; // null = unknown / outside coverage
  bool _gpsCoarseFailed = false;

  OmniMobileApi _api(SessionService s) => OmniMobileApi(
        baseUrl: s.clientUrl,
        db: s.clientDb,
        token: s.token,
      );

  /// Set state to render `InlineFaceCapture` in place of the
  /// `BigCheckButton`, then wait for the inline widget to complete the
  /// shared completer with its capture result.
  Future<FaceCaptureResult> _runInlineFaceCapture() {
    final completer = Completer<FaceCaptureResult>();
    setState(() {
      _captureCompleter = completer;
      _faceCapturing = true;
    });
    return completer.future;
  }

  /// Bridge: InlineFaceCapture finished — flip the swap back to
  /// BigCheckButton AND resolve the awaiting future so _onCheckAction
  /// proceeds (to verifyFace + attendance POST).
  void _handleInlineFaceResult(FaceCaptureResult result) {
    final completer = _captureCompleter;
    _captureCompleter = null;
    if (mounted) {
      setState(() => _faceCapturing = false);
    }
    if (completer != null && !completer.isCompleted) {
      completer.complete(result);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      refresh();
      _refreshGpsCard();
    });
    // 1-second tick so the HOURS TODAY counter ticks live in HH:MM:SS.
    // The "Current Time" card displays minute precision so it doesn't
    // flicker; only the hours-today stat actually visibly changes.
    _clockTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) {
        if (mounted) setState(() => _now = DateTime.now());
      },
    );
    _gpsTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => _refreshGpsCard(),
    );
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _gpsTimer?.cancel();
    super.dispose();
  }

  Future<void> refresh() async {
    final session = context.read<SessionService>();
    // SaaS-gated: when Attendance is off, the build() body shows
    // FeatureLockedPane instead of the attendance content. No point
    // calling the connector — early-return and clear loading so a
    // pull-to-refresh doesn't spin forever.
    if (!session.featureAttendance) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final status = await _api(session).getAttendanceStatus();
      if (mounted) {
        setState(() {
          _status = status;
          _statusFetchedAt = DateTime.now();
        });
      }
      // Recompute distance once status arrives — the geofence may have
      // changed since the last poll.
      _refreshGpsCard();
    } catch (e) {
      if (mounted) setState(() => _error = _humanizeApiError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Light-touch GPS refresh that just powers the GPS Status card.
  /// Doesn't surface errors to the user — failure just means the card
  /// shows "—". Early-return when the SaaS geolocation flag is off
  /// so we never request location permission for a feature the
  /// company has disabled.
  Future<void> _refreshGpsCard() async {
    if (!mounted) return;
    final session = context.read<SessionService>();
    if (!session.featureGeolocation) return;
    final s = _status;
    if (s == null || !s.hasGeofence) return;
    try {
      final loc = await _locationService.getCurrent();
      if (!mounted) return;
      if (!loc.isReady) {
        setState(() {
          _currentDistanceMeters = null;
          _gpsCoarseFailed = true;
        });
        return;
      }
      final d = _haversineMeters(
        loc.latitude!,
        loc.longitude!,
        s.officeLatitude!,
        s.officeLongitude!,
      );
      setState(() {
        _currentDistanceMeters = d;
        _gpsCoarseFailed = false;
        // If the live fix now shows the user inside the radius, drop any
        // stale "Outside office geofence" banner from an earlier reject.
        // Without this the red card lingers even after the user moves
        // back in range or the admin widens the radius — contradicting
        // the (live) GPS Status card right above it.
        if (_lastDistance != null &&
            d <= (s.officeRadiusMeters ?? 200)) {
          _lastDistance = null;
          _lastAllowedRadius = null;
        }
      });
    } catch (_) {
      // ignore — leave the card showing whatever it had before
    }
  }

  static double _haversineMeters(
      double lat1, double lng1, double lat2, double lng2) {
    const r = 6371000.0;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLng = (lng2 - lng1) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return r * c;
  }

  Future<void> _onCheckAction() async {
    if (_acting) return;

    // Defensive: build()'s FeatureLockedPane should hide the action
    // button entirely when Attendance is off, but the flag can flip
    // mid-session (admin toggles in SaaS, mobile refreshes its
    // subscription). Guard so a stale rebuild can't submit.
    final session = context.read<SessionService>();
    if (!session.featureAttendance) return;

    // Step 0 — face setup short-circuit. When the big button is in
    // `enroll` state, tapping it doesn't start a check-in — it routes
    // to the one-time face setup. The button state in build() already
    // reflects this; this is just the action dispatch.
    //
    // `== false` (not `!= true`) so the null/loading state is treated
    // as "not yet known, assume enrolled" — keeps this in sync with
    // _buttonState() below and matches the optimistic CHECK IN that
    // the button shows during the brief enrollment-fetch window on
    // cold start. If the user is in fact not enrolled when they tap
    // during that window, verifyFace() catches it and returns
    // FaceVerifyResult.notEnrolled() with a clear message.
    final faceSvc = context.read<FaceRecognitionService>();
    final needsEnrollment = session.featureFaceVerification &&
        !DevConstants.simulateFaceRecognition &&
        faceSvc.isEnrolled == false;
    if (needsEnrollment) {
      // Push via root navigator — the HomeShell uses per-tab
      // navigators, so a local push would leave the bottom nav bar
      // bleeding through the full-screen camera modal underneath.
      await Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute(builder: (_) => const FaceEnrollmentScreen()),
      );
      if (!mounted) return;
      // Re-read enrolled status — the user may have completed setup,
      // backed out, or done neither. The build() rebuild that follows
      // will reflect whatever the new state is.
      await faceSvc.refreshEnrolledStatus(session);
      if (mounted) setState(() {});
      return;
    }

    setState(() => _acting = true);

    // Step 1 — GPS (only when the SaaS geolocation flag is on). When
    // off, lat/lng stay null and the connector skips the geofence
    // check. No permission prompt is triggered either.
    double? latitude;
    double? longitude;
    if (session.featureGeolocation) {
      final loc = await _locationService.getCurrent();
      if (!mounted) return;
      if (!loc.isReady) {
        setState(() => _acting = false);
        _showError(loc.friendlyMessage);
        return;
      }
      latitude = loc.latitude;
      longitude = loc.longitude;

      // Step 1b — Pre-capture geofence gate. If we can tell from this
      // FRESH fix that the user is outside the office radius, reject now
      // — before spending the user's time on a face capture the server
      // would only reject afterwards. Uses the just-fetched location
      // (not the up-to-60s-stale _currentDistanceMeters poll value) so
      // it matches what the server will compute. The server still
      // enforces the geofence on submit; this is purely a fast-fail.
      // Skipped under dev-location and when no geofence is configured,
      // mirroring _buttonState()'s exemptions so the button label and
      // tap-time behaviour stay in agreement.
      final s = _status;
      if (!DevConstants.useDevLocation &&
          s != null &&
          s.hasGeofence &&
          s.officeLatitude != null &&
          s.officeLongitude != null) {
        final radius = s.officeRadiusMeters ?? 200;
        final distance = _haversineMeters(
          latitude!,
          longitude!,
          s.officeLatitude!,
          s.officeLongitude!,
        );
        if (distance > radius) {
          setState(() {
            _acting = false;
            _currentDistanceMeters = distance;
            _lastDistance = distance;
            _lastAllowedRadius = radius.toDouble();
          });
          _showError('You are outside the allowed office location.');
          return;
        }
      }
    }

    // Step 2 — Face capture + on-device verification against the
    // employee's enrolled face. Gated on the SaaS face_verification
    // flag: when the company has face verification disabled, the
    // mobile skips capture entirely and submits face_verified=false.
    // The connector mirrors this — see main.py check_in/check_out,
    // which no longer enforces face_verified.
    bool faceVerified = false;
    if (session.featureFaceVerification) {
      // Silent (B-prime) capture: swap the BigCheckButton in-place
      // for InlineFaceCapture. Mini preview lives at the top half of
      // the home screen where the camera lens actually is, so the
      // user's gaze and the camera angle align. The inline widget
      // self-closes after 3 failed attempts or its hard timeout —
      // we surface the message via snackbar and return to the button
      // state. No auto-fallback to a second camera surface; user
      // taps CHECK IN again to retry.
      final faceResult = await _runInlineFaceCapture();
      if (!mounted) return;
      if (!faceResult.success) {
        setState(() => _acting = false);
        if (faceResult.errorMessage != null) {
          _showError(faceResult.errorMessage!);
        }
        return;
      }

      final verify = await faceSvc.verifyFace(faceResult.imagePath!);
      if (!mounted) return;
      if (!verify.ok) {
        setState(() => _acting = false);
        _showError(verify.errorMessage ??
            'Face not recognized. Please try again.');
        return;
      }
      faceVerified = faceResult.faceVerified;
    }

    // Step 3 — submit attendance
    try {
      final api = _api(session);
      final deviceId = await _deviceService.getDeviceId();
      final wasCheckedIn = _status?.checkedIn == true;

      AutoClosePrevious? autoClosed;
      if (wasCheckedIn) {
        await api.checkOut(
          latitude: latitude,
          longitude: longitude,
          faceVerified: faceVerified,
          deviceId: deviceId,
          devLocation: DevConstants.useDevLocation,
        );
      } else {
        final resp = await api.checkIn(
          latitude: latitude,
          longitude: longitude,
          faceVerified: faceVerified,
          deviceId: deviceId,
          devLocation: DevConstants.useDevLocation,
        );
        // Connector's Phase 1 auto-close echoes back when it had to
        // infer a check-out for a forgotten attendance. Surface as a
        // banner so the user knows what HR will see.
        final acp = resp['auto_closed_previous'];
        if (acp is Map<String, dynamic>) {
          autoClosed = AutoClosePrevious.fromJson(acp);
        }
      }

      await refresh();
      if (mounted) {
        setState(() {
          _lastDistance = null;
          _lastAllowedRadius = null;
          // Clear the banner on a fresh check-out; populate on
          // a check-in that triggered the auto-close.
          if (wasCheckedIn) _autoClosedPrevious = null;
          if (autoClosed != null) _autoClosedPrevious = autoClosed;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(wasCheckedIn
                ? 'Checked out successfully!'
                : 'Checked in successfully!'),
            backgroundColor: AppTheme.primary,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        if (e is ApiException && e.errorCode == 'outside_geofence') {
          setState(() {
            _lastDistance = e.distanceFromOffice;
            _lastAllowedRadius = e.allowedRadius;
          });
        }
        _showError(_humanizeApiError(e));
      }
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppTheme.error),
    );
  }

  String _humanizeApiError(Object e) {
    final raw = e.toString();
    if (raw.contains('office_geofence_not_configured')) {
      return 'No office location is set for your employee. Ask HR to configure the work address.';
    }
    if (raw.contains('outside_geofence')) {
      return 'You are outside the allowed office location.';
    }
    if (raw.contains('face_not_verified')) {
      return 'Face verification failed. Please try again.';
    }
    if (raw.contains('mobile_not_enabled')) {
      return 'Mobile attendance is not enabled for your employee profile.';
    }
    if (raw.contains('already_checked_in')) {
      return 'You are already checked in.';
    }
    if (raw.contains('not_checked_in')) {
      return 'You are not currently checked in.';
    }
    if (raw.contains('invalid_session') || raw.contains('invalid_token')) {
      return 'Your session expired. Please login again.';
    }
    if (raw.contains('timeout')) {
      return 'Server is taking too long to respond. Please try again.';
    }
    if (raw.contains('network_error')) {
      return 'No internet connection. Check your network and try again.';
    }
    if (raw.contains('server_error')) {
      return 'Something went wrong on our end. Please try again in a moment.';
    }
    if (raw.contains('invalid_attendance')) {
      return 'Your previous check-in was too long ago. Please contact HR '
          'or open the attendance record in the web app to close it.';
    }
    // Last-resort fallback. NEVER echo the raw exception text — it can
    // contain the request URI (and the database name). Only surface a
    // raw code if it's a short, safe-looking server error token
    // (snake_case, no spaces/URLs); otherwise show a generic message.
    final stripped = raw.replaceFirst(RegExp(r'^Exception: '), '').trim();
    final looksLikeCode =
        RegExp(r'^[a-z0-9_]{1,40}$').hasMatch(stripped);
    if (looksLikeCode) return stripped;
    return 'Something went wrong. Please try again.';
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionService>();
    return Scaffold(
      appBar: const OmniAppBar(title: 'Attendance'),
      body: !session.featureAttendance
          ? const FeatureLockedPane(
              featureName: 'Attendance',
              subtitle: 'Your subscription does not include '
                  'attendance tracking. Contact your administrator '
                  'to upgrade.',
            )
          : RefreshIndicator(
              onRefresh: refresh,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                children: [
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 80),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_error != null)
                    _buildError()
                  else
                    _buildContent(session),
                ],
              ),
            ),
    );
  }

  Widget _buildError() {
    return ErrorStateView(message: _error!, onRetry: refresh);
  }

  Widget _buildContent(SessionService session) {
    final s = _status!;
    final firstName = (session.employeeName.isNotEmpty
            ? session.employeeName
            : (session.userName.isNotEmpty
                ? session.userName
                : session.userLogin))
        .split(RegExp(r'\s+'))
        .first;
    final dateLabel =
        DateFormat('EEEE, MMM d').format(_now).toUpperCase();
    final timeLabel = DateFormat('h:mm a').format(_now);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Greeting
        Text(
          dateLabel,
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 2.5,
            color: AppTheme.secondary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Hello, $firstName',
          style: GoogleFonts.inter(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
            color: AppTheme.onSurface,
          ),
        ),
        const SizedBox(height: 16),
        // Time + validation row. IntrinsicHeight makes both cards
        // render at the max of their natural heights — necessary
        // because _compactStatusCard (used for geo-off branches) has
        // a smaller subtitle font than InfoCard's bold value, so
        // without stretching the right card sits ~7px shorter. With
        // CrossAxisAlignment.stretch each card's outer Container
        // honors the row's height and the bottom edges align.
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: InfoCard(
                  icon: Icons.access_time_rounded,
                  label: 'Current Time',
                  value: timeLabel,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: _validationCard(s, session)),
            ],
          ),
        ),
        if (_autoClosedPrevious != null) ...[
          const SizedBox(height: 16),
          _autoClosedBanner(),
        ],
        const SizedBox(height: 28),
        // Big action button OR inline face-capture preview. Same outer
        // footprint (248dp) so the rest of the page layout doesn't
        // shift when we swap.
        Center(
          child: _faceCapturing
              ? InlineFaceCapture(onResult: _handleInlineFaceResult)
              : BigCheckButton(
                  checkedIn: s.checkedIn,
                  state: _buttonState(s, session),
                  onPressed: _acting ? null : _onCheckAction,
                  faceEnabled: session.featureFaceVerification,
                  geoEnabled: session.featureGeolocation,
                ),
        ),
        if (_buttonState(s, session) == CheckButtonState.enroll) ...[
          const SizedBox(height: 12),
          Center(
            child: Text(
              'One-time setup. Takes about 10 seconds.',
              style: TextStyle(
                fontSize: 13,
                color: AppTheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
        const SizedBox(height: 24),
        // Status card
        _statusCard(s),
        if (DevConstants.useDevLocation ||
            DevConstants.simulateFaceRecognition) ...[
          const SizedBox(height: 12),
          _devBanner(),
        ],
        if (_lastDistance != null && _lastAllowedRadius != null) ...[
          const SizedBox(height: 12),
          _geofenceInfoCard(),
        ],
      ],
    );
  }

  /// Right-hand status card next to Current Time. Branches on SaaS
  /// feature flags so the wording matches the actual policy — never
  /// "Locating…" forever when geolocation is off, never red/orange
  /// warnings for a feature the company intentionally disabled.
  Widget _validationCard(AttendanceStatus s, SessionService session) {
    if (session.featureGeolocation) {
      return _gpsCard(s);
    }
    if (session.featureFaceVerification) {
      return _compactStatusCard(
        icon: Icons.shield_outlined,
        label: 'Location',
        value: 'Disabled',
        subtitle: 'By company policy',
      );
    }
    return _compactStatusCard(
      icon: Icons.rule_rounded,
      label: 'Validation',
      value: 'Basic',
      subtitle: 'No face/GPS required',
    );
  }

  /// Same outer chrome as `InfoCard` so the card frame matches Current
  /// Time exactly, but the icon shares a row with the bold value. That
  /// saves one row of vertical space, leaving room for the muted
  /// subtitle without making the card taller than Current Time.
  Widget _compactStatusCard({
    required IconData icon,
    required String label,
    required String value,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppTheme.glassShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 22, color: AppTheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.onSurface,
                    height: 1.1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppTheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: AppTheme.onSurfaceVariant,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _gpsCard(AttendanceStatus s) {
    if (DevConstants.useDevLocation) {
      return InfoCard(
        icon: Icons.developer_mode,
        iconColor: Colors.orange,
        label: 'GPS Status',
        value: 'DEV',
        suffix: 'Bypass',
        suffixColor: Colors.orange,
      );
    }
    if (!s.hasGeofence) {
      return InfoCard(
        icon: Icons.gps_off_rounded,
        iconColor: AppTheme.outline,
        label: 'GPS Status',
        value: 'No office',
      );
    }
    if (_gpsCoarseFailed && _currentDistanceMeters == null) {
      return InfoCard(
        icon: Icons.gps_off_rounded,
        iconColor: AppTheme.error,
        label: 'GPS Status',
        value: 'Unavailable',
      );
    }
    if (_currentDistanceMeters == null) {
      return InfoCard(
        icon: Icons.gps_not_fixed_rounded,
        iconColor: AppTheme.outline,
        label: 'GPS Status',
        value: 'Locating…',
      );
    }
    final inside = _currentDistanceMeters! <= (s.officeRadiusMeters ?? 200);
    final distLabel = _formatDistance(_currentDistanceMeters!);
    return InfoCard(
      icon: Icons.near_me_rounded,
      iconColor: inside ? const Color(0xFF22C55E) : AppTheme.error,
      label: 'GPS Status',
      value: inside ? 'Office' : 'Outside',
      suffix: distLabel,
      suffixColor: inside ? const Color(0xFF22C55E) : AppTheme.error,
    );
  }

  String _formatDistance(double m) {
    if (m < 1000) return '${m.round()}m';
    return '${(m / 1000).toStringAsFixed(1)}km';
  }

  Widget _statusCard(AttendanceStatus s) {
    final accent =
        s.checkedIn ? AppTheme.primary : AppTheme.onSurfaceVariant;
    final since = s.currentCheckInTime != null
        ? 'Since ${DateTimeUtils.formatLocalTime(s.currentCheckInTime!)}'
        : null;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
      decoration: BoxDecoration(
        color: AppTheme.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          // Header row: icon ← title + subtitle. Horizontal so the
          // status takes one band of vertical space instead of three.
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent,
                ),
                child: Icon(
                  s.checkedIn
                      ? Icons.check_rounded
                      : Icons.access_time_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.checkedIn ? 'Checked In' : 'Not Checked In',
                      style: GoogleFonts.inter(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: accent,
                        letterSpacing: -0.3,
                      ),
                    ),
                    if (since != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        since,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: AppTheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Divider(
              height: 1,
              color: AppTheme.outline.withValues(alpha: 0.15)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _statColumn(
                  value: _hoursTodayLabel(s),
                  label: 'HOURS TODAY',
                  tabular: true,
                ),
              ),
              Expanded(
                child: _statColumn(
                  value: s.lastCheckInTime != null
                      ? DateTimeUtils.formatLocalTime(s.lastCheckInTime!)
                      : '—',
                  label: 'LAST CHECK-IN',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statColumn({
    required String value,
    required String label,
    bool tabular = false,
  }) {
    return Column(
      children: [
        Text(
          value,
          style: GoogleFonts.inter(
            fontSize: 19,
            fontWeight: FontWeight.w800,
            color: AppTheme.onSurface,
            letterSpacing: -0.3,
            // Tabular figures keep digit widths constant so the
            // HH:MM:SS counter doesn't horizontally jitter as the
            // seconds digit changes from a "1" to a "0".
            fontFeatures: tabular
                ? const [FontFeature.tabularFigures()]
                : null,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.5,
            color: AppTheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  /// Decide which CheckButtonState to show based on geolocation
  /// feasibility. Out-of-range only matters when the SaaS
  /// subscription requires geo AND we have a real GPS measure to
  /// compare; otherwise we stay optimistically READY and let the
  /// server reject if needed.
  CheckButtonState _buttonState(AttendanceStatus s, SessionService session) {
    if (_acting) return CheckButtonState.scanning;
    // Face setup takes precedence: if the user hasn't enrolled, the
    // big button's primary action shifts to "ENROLL FACE" regardless
    // of geofence — they can't check in without enrollment anyway,
    // so showing READY/NOT READY would be misleading.
    //
    // `== false` (not `!= true`) so the null state — which the
    // service holds until refreshEnrolledStatus() completes its
    // async server fetch — is treated optimistically as "enrolled
    // until proven otherwise." Without this, the button rendered
    // ENROLL FACE on the first frame of every cold start (the
    // postFrame callback that triggers the refresh hasn't fired
    // yet) and then visibly snapped to CHECK IN seconds later.
    // The action handler at line 197 uses the matching check so
    // tap-time logic agrees with what the button shows.
    final faceSvc = context.read<FaceRecognitionService>();
    final needsEnrollment = session.featureFaceVerification &&
        !DevConstants.simulateFaceRecognition &&
        faceSvc.isEnrolled == false;
    if (needsEnrollment) return CheckButtonState.enroll;
    if (!session.featureGeolocation) return CheckButtonState.ready;
    if (DevConstants.useDevLocation) return CheckButtonState.ready;
    if (!s.hasGeofence) return CheckButtonState.ready;
    if (_currentDistanceMeters == null) return CheckButtonState.ready;
    if (_currentDistanceMeters! > (s.officeRadiusMeters ?? 200)) {
      return CheckButtonState.disabled;
    }
    return CheckButtonState.ready;
  }

  /// HH:MM:SS for the HOURS TODAY stat. Server's hours_today is
  /// fresh-as-of-fetch; we project forward only while still checked
  /// in, so the counter keeps ticking between server polls.
  String _hoursTodayLabel(AttendanceStatus s) {
    var seconds = (s.hoursToday * 3600).round();
    if (s.checkedIn && _statusFetchedAt != null) {
      seconds +=
          DateTime.now().difference(_statusFetchedAt!).inSeconds;
    }
    if (seconds < 0) seconds = 0;
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final sec = seconds % 60;
    String pad(int v) => v.toString().padLeft(2, '0');
    return '${pad(h)}:${pad(m)}:${pad(sec)}';
  }

  Widget _devBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.developer_mode, size: 14, color: Colors.orange),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              [
                if (DevConstants.useDevLocation) 'DEV location',
                if (DevConstants.simulateFaceRecognition)
                  'face recognition simulated',
              ].join(' · '),
              style: GoogleFonts.inter(
                fontSize: 12,
                color: Colors.orange,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _autoClosedBanner() {
    final acp = _autoClosedPrevious!;
    final yellow = const Color(0xFFB45309); // amber-800
    final bg = const Color(0xFFFEF3C7); // amber-100
    final original = DateTimeUtils.formatLocalDateTime(acp.originalCheckIn);
    final inferred = DateTimeUtils.formatLocalDateTime(acp.inferredCheckOut);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: yellow.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 18, color: yellow),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Previous check-in auto-closed',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: yellow,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'We detected a check-in from $original that was never '
                  'closed. We recorded a '
                  '${acp.hoursAssumed.toStringAsFixed(0)}-hour shift '
                  'ending at $inferred. Contact HR if this is incorrect.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            color: yellow,
            tooltip: 'Dismiss',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: () =>
                setState(() => _autoClosedPrevious = null),
          ),
        ],
      ),
    );
  }

  Widget _geofenceInfoCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.location_off, size: 18, color: AppTheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Outside office geofence',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.error),
                ),
                const SizedBox(height: 4),
                Text(
                  'Distance: ${_lastDistance!.toStringAsFixed(0)} m  ·  '
                  'Allowed: ${_lastAllowedRadius!.toStringAsFixed(0)} m',
                  style: TextStyle(
                      fontSize: 12, color: AppTheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Bell button moved into OmniAppBar (lib/widgets/omni_app_bar.dart)
// so every main tab can reuse it.
