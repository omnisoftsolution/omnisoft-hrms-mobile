import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/error_messages.dart';
import '../../../core/theme.dart';
import '../../../models/auto_close_previous.dart';
import '../../../models/expense_record.dart';
import '../../../models/face_capture_result.dart';
import '../../../models/my_day.dart';
import '../../../services/attendance_action_controller.dart';
import '../../../services/face_recognition_service.dart';
import '../../../services/omni_mobile_api.dart';
import '../../../services/session_service.dart';
import '../../../widgets/error_state_view.dart';
import '../../../widgets/feature_locked_pane.dart';
import '../../../widgets/omni_app_bar.dart';
import '../../approvals/approvals_screen.dart';
import '../../expenses/expense_detail_screen.dart';
import '../../face_scan/face_capture_screen.dart';
import '../../face_scan/face_enrollment_screen.dart';
import '../../payroll/payslips_screen.dart';
import 'auto_closed_banner.dart';
import 'day_timeline.dart';
import 'for_you_list.dart';
import 'my_day_display.dart';
import 'status_tile.dart';
import 'week_strip.dart';

/// The Home tab for every employee (spec 2026-10-07): the status tile
/// (with the check-in button for phone check-in employees), the week
/// strip, the day's timeline (or an off card) and a short 'For you' list,
/// all from one endpoint plus the attendance status.
class MyDayScreen extends StatefulWidget {
  const MyDayScreen({
    super.key,
    this.onOpenLeave,
    this.onOpenExpense,
    this.apiBuilder,
    this.appBar,
    this.destinationBuilder,
    this.refreshSession,
    this.controllerBuilder,
    this.captureFace,
    this.enrol,
  });

  /// Opens leave history on one request (HomeShell.navigateToLeave, the
  /// route the leave notifications use).
  final void Function(int leaveId)? onOpenLeave;

  /// Opens the Expenses tab (HomeShell.navigateToExpense); used when the
  /// expense's own record could not be loaded for the detail screen.
  final void Function(int expenseId)? onOpenExpense;

  /// Test seam: builds the API client from the session.
  @visibleForTesting
  final OmniMobileApi Function(SessionService session)? apiBuilder;

  /// Test seam: replaces [OmniAppBar], which needs the notification and
  /// session services.
  @visibleForTesting
  final PreferredSizeWidget? appBar;

  /// Test seam: replaces the screen a For-you row pushes.
  @visibleForTesting
  final Widget Function(ForYouItem item, ExpenseRecord? expense)?
  destinationBuilder;

  /// Test seam: replaces SessionService.refreshMe.
  @visibleForTesting
  final Future<void> Function()? refreshSession;

  /// Test seam: builds the check-in controller (defaults to the real
  /// services and the FaceRecognitionService from the tree).
  @visibleForTesting
  final AttendanceActionController Function(SessionService session)?
  controllerBuilder;

  /// Test seam: replaces the full-screen face capture.
  @visibleForTesting
  final Future<FaceCaptureResult> Function()? captureFace;

  /// Test seam: replaces the full-screen face enrolment.
  @visibleForTesting
  final Future<void> Function()? enrol;

  @override
  State<MyDayScreen> createState() => MyDayScreenState();
}

class MyDayScreenState extends State<MyDayScreen> {
  /// The last successfully loaded day; kept in memory only.
  MyDay? _day;
  String? _firstLoadError;
  bool _refreshFailed = false;

  /// The fetch currently running; every overlapping [refresh] shares it.
  Future<void>? _inFlight;

  /// Guards [_onTap] against a second tap while one is being handled.
  bool _opening = false;

  late final AppLifecycleListener _lifecycle;

  /// Phone check-in only; null while the day is kiosk-only.
  AttendanceActionController? _controller;
  Timer? _gpsTimer;
  AutoClosePrevious? _autoClosed;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: () {
        refresh();
      },
    );
    refresh();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _gpsTimer?.cancel();
    _controller?.removeListener(_onControllerChange);
    _controller?.dispose();
    super.dispose();
  }

  void _onControllerChange() {
    if (mounted) setState(() {});
  }

  OmniMobileApi _api() {
    final session = context.read<SessionService>();
    return widget.apiBuilder?.call(session) ??
        OmniMobileApi(
          baseUrl: session.clientUrl,
          db: session.clientDb,
          token: session.token,
        );
  }

  /// Reload the day. Called on first build, pull-to-refresh, on return
  /// from a pushed screen, on app resume, and by HomeShell on a Home tab
  /// tap. No polling: a kiosk punch shows on the next refresh. Overlapping
  /// calls share the one request in flight.
  Future<void> refresh() => _inFlight ??= _load().whenComplete(() {
    _inFlight = null;
  });

  Future<void> _load() async {
    try {
      final day = await _api().fetchMyDay();
      if (!mounted) return;
      setState(() {
        _day = day;
        _firstLoadError = null;
        _refreshFailed = false;
      });
      final session = context.read<SessionService>();
      // HR cleared the flag: re-pull /me so the session agrees with the
      // day (the server already refuses phone punches the other way).
      if (!day.kioskOnly && session.attendanceKioskOnly) {
        unawaited(_refreshSession());
      }
      // The For-you card and the Leave tab badge must show one number.
      // Only once the session knows this user approves: before that the
      // next /me (resume, Leave tab) fills it in.
      final cardCount = day.forYou
          .where((item) => item.kind == 'leave_approvals')
          .fold<int>(0, (n, item) => n + item.count);
      if (session.leaveApprovalsEnabled &&
          cardCount != session.leaveApprovalsPendingCount) {
        unawaited(_refreshSession());
      }
      await _syncController(day);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (_day == null) {
          _firstLoadError = friendlyError(e);
        } else {
          _refreshFailed = true;
        }
      });
    }
  }

  /// Phone check-in days own a controller (status + GPS); kiosk-only days
  /// and tenants without Attendance drop it. Called after every successful
  /// day load.
  Future<void> _syncController(MyDay day) async {
    if (day.kioskOnly || !context.read<SessionService>().featureAttendance) {
      _gpsTimer?.cancel();
      _gpsTimer = null;
      _controller?.removeListener(_onControllerChange);
      _controller?.dispose();
      _controller = null;
      // _load's setState ran while the controller was still set.
      if (mounted) setState(() {});
      return;
    }
    var controller = _controller;
    if (controller == null) {
      final session = context.read<SessionService>();
      controller =
          widget.controllerBuilder?.call(session) ??
          AttendanceActionController(
            session: session,
            faceService: context.read<FaceRecognitionService>(),
          );
      controller.addListener(_onControllerChange);
      _controller = controller;
      _gpsTimer = Timer.periodic(
        const Duration(seconds: 60),
        (_) => _controller?.sampleLocation(),
      );
    }
    await controller.refreshStatus();
  }

  Future<void> _retry() {
    setState(() => _firstLoadError = null);
    return refresh();
  }

  Future<ExpenseRecord?> _findExpense(int id) async {
    try {
      final page = await _api().getExpenseList();
      return page.records.where((record) => record.id == id).firstOrNull;
    } catch (_) {
      return null;
    }
  }

  static Widget _destination(ForYouItem item, ExpenseRecord? expense) {
    switch (item.kind) {
      case 'leave_approvals':
        return const ApprovalsScreen();
      case 'my_expense':
        return ExpenseDetailScreen(record: expense!);
      default:
        return const PayslipsScreen();
    }
  }

  Future<void> _refreshSession() async {
    final session = context.read<SessionService>();
    final custom = widget.refreshSession;
    if (custom != null) {
      await custom();
    } else {
      await session.refreshMe();
    }
  }

  /// The tile's button for the current day and controller state (spec
  /// 2026-10-07 §4.2). Kiosk-only days have no controller, so no button.
  TileAction? _tileAction(MyDay day) {
    final c = _controller;
    if (c == null) return null;
    final state = c.buttonState;
    if (state == AttendanceButtonState.enroll) {
      return TileAction(
        label: 'Set up your face · 10 seconds',
        icon: TileActionIcon.faceSetup,
        onPressed: _act,
      );
    }
    // The same truth perform() punches on: `on_break` is a closed
    // attendance, so it offers Check in again, never Check out.
    final checkedIn = c.status?.checkedIn ?? (day.state == 'checked_in');
    if (checkedIn) {
      return TileAction(
        label: 'Check out',
        enabled: state != AttendanceButtonState.acting,
        onPressed: _act,
      );
    }
    // Leave, public holiday or no shift: nothing is expected, but phone
    // users may still work (outlined, so it does not read as a must).
    final offDay = switch (displayOf(day)) {
      MyDayDisplay.holiday ||
      MyDayDisplay.leave ||
      MyDayDisplay.noShift => true,
      _ => false,
    };
    final again = day.punches.isNotEmpty;
    return TileAction(
      label: again ? 'Check in again' : 'Check in',
      style: again || offDay
          ? TileActionStyle.outlined
          : TileActionStyle.filled,
      enabled: state == AttendanceButtonState.ready,
      onPressed: _act,
    );
  }

  /// The missing day's Now row for phone check-in.
  String? _phoneHint() {
    final c = _controller;
    if (c == null) return null;
    if (c.buttonState == AttendanceButtonState.enroll) {
      return 'Set up your face once, then check in';
    }
    if (c.isOutside) return 'Outside the office · move closer to check in';
    if (c.hasPlace) return 'At the office · check in now';
    return 'Check in now';
  }

  Future<FaceCaptureResult> _captureFace() async {
    final custom = widget.captureFace;
    if (custom != null) return custom();
    // Root navigator: the camera covers the bottom bar.
    final result = await Navigator.of(context, rootNavigator: true)
        .push<FaceCaptureResult>(
          MaterialPageRoute(builder: (_) => const FaceCaptureScreen()),
        );
    return result ?? FaceCaptureResult.cancelled();
  }

  Future<void> _enrol() async {
    final custom = widget.enrol;
    if (custom != null) return custom();
    await Navigator.of(
      context,
      rootNavigator: true,
    ).push(MaterialPageRoute(builder: (_) => const FaceEnrollmentScreen()));
  }

  Future<void> _act() async {
    final c = _controller;
    if (c == null) return;
    final AttendanceActionOutcome? result;
    try {
      result = await c.perform(captureFace: _captureFace, enrol: _enrol);
    } catch (e) {
      // A device lookup or a UI step threw outside perform()'s own catch.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendlyError(e)),
          backgroundColor: AppTheme.error,
        ),
      );
      return;
    }
    final outcome = result;
    if (!mounted || outcome == null) return;
    final messenger = ScaffoldMessenger.of(context);
    if (outcome.error != null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(outcome.error!),
          backgroundColor: AppTheme.error,
        ),
      );
      return;
    }
    if (outcome.enrolled) {
      setState(() {});
      return;
    }
    setState(() {
      if (!outcome.checkedIn) _autoClosed = null;
      if (outcome.autoClosed != null) _autoClosed = outcome.autoClosed;
    });
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          outcome.checkedIn
              ? 'Checked in successfully!'
              : 'Checked out successfully!',
        ),
        backgroundColor: AppTheme.primary,
      ),
    );
    await refresh();
  }

  Future<void> _onTap(ForYouItem item) async {
    if (!item.isKnown) return;
    // id 0 = the server omitted it: there is nothing to open.
    if (item.id == 0 &&
        (item.kind == 'my_leave' || item.kind == 'my_expense')) {
      return;
    }
    if (item.kind == 'my_leave') {
      widget.onOpenLeave?.call(item.id);
      return;
    }
    if (_opening) return;
    _opening = true;
    try {
      ExpenseRecord? expense;
      if (item.kind == 'my_expense') {
        expense = await _findExpense(item.id);
        if (!mounted) return;
        if (expense == null) {
          widget.onOpenExpense?.call(item.id);
          return;
        }
      }
      final build = widget.destinationBuilder ?? _destination;
      // The tab's own Navigator: the bottom bar stays visible.
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => build(item, expense)));
    } finally {
      _opening = false;
    }
    // The guard covers the lookup and the push only: the follow-up
    // refreshes can take up to the request timeout on a slow network, and
    // the (still visible) rows must stay tappable meanwhile.
    if (!mounted) return;
    if (item.kind == 'leave_approvals') {
      // A decision changes the approvals count kept in the session.
      await _refreshSession();
      if (!mounted) return;
    }
    await refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.appBar ?? const OmniAppBar(title: 'My day'),
      body: _body(context),
    );
  }

  Widget _body(BuildContext context) {
    final day = _day;
    if (day == null) {
      final error = _firstLoadError;
      if (error == null) {
        return const Center(child: CircularProgressIndicator());
      }
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ErrorStateView(message: error, onRetry: _retry),
        ),
      );
    }
    final text = Theme.of(context).textTheme;
    final sectionStyle = text.labelLarge?.copyWith(
      color: AppTheme.onSurfaceVariant,
      fontWeight: FontWeight.w700,
    );
    // Attendance off in the subscription: no tile, no timeline, no punch
    // (no controller either); the week and For you still apply.
    final attendanceOn = context.watch<SessionService>().featureAttendance;
    return Column(
      children: [
        if (_refreshFailed)
          Container(
            width: double.infinity,
            color: AppTheme.error.withValues(alpha: 0.08),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              friendlyError(myDayRefreshFailed),
              style: text.bodySmall?.copyWith(color: AppTheme.error),
            ),
          ),
        if (attendanceOn)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: StatusTile(
              day: day,
              action: _tileAction(day),
              place: _controller?.placeLabel ?? '',
              pinOn: _controller == null
                  ? null
                  : (_controller!.hasPlace && !_controller!.isOutside),
            ),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                16,
                16 + MediaQuery.of(context).viewPadding.bottom,
              ),
              children: [
                if (!attendanceOn) ...[
                  const FeatureLockedPane(
                    featureName: 'Attendance',
                    subtitle:
                        'Your subscription does not include '
                        'attendance tracking. Contact your administrator '
                        'to upgrade.',
                  ),
                  const SizedBox(height: 16),
                ],
                if (_autoClosed != null) ...[
                  AutoClosedBanner(
                    acp: _autoClosed!,
                    onDismiss: () => setState(() => _autoClosed = null),
                  ),
                  const SizedBox(height: 16),
                ],
                if (day.week.isNotEmpty) ...[
                  WeekStrip(day: day),
                  const SizedBox(height: 20),
                ],
                if (!attendanceOn)
                  const SizedBox.shrink()
                else if (day.off == null || day.punches.isNotEmpty) ...[
                  Text('Timeline', style: sectionStyle),
                  const SizedBox(height: 8),
                  DayTimeline(day: day, phoneHint: _phoneHint()),
                  const SizedBox(height: 16),
                ] else ...[
                  _offCard(context, day),
                  const SizedBox(height: 16),
                ],
                Text('For you', style: sectionStyle),
                const SizedBox(height: 8),
                ForYouList(
                  items: day.forYou,
                  onTap: _onTap,
                  missing: attendanceOn && day.missing && day.kioskOnly,
                  onMissingTap: () => showKioskSheet(context),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Holiday / leave / day-off facts in place of the timeline (spec §4.4).
  Widget _offCard(BuildContext context, MyDay day) {
    final text = Theme.of(context).textTheme;
    final off = day.off!;
    final next = day.nextShift;
    final String title;
    final String line1;
    switch (off.kind) {
      case 'public_holiday':
        title = off.name.isEmpty ? 'Public holiday' : off.name;
        line1 = day.kioskOnly
            ? 'Nothing is expected at the kiosk today'
            : 'Nothing is expected today';
      case 'leave':
        title = off.name.isEmpty ? 'On leave' : off.name;
        line1 = off.dateFrom.isEmpty
            ? 'Approved time off'
            : 'From ${shortDate(off.dateFrom)} to ${shortDate(off.dateTo)}';
      default:
        title = 'Enjoy your day';
        line1 = day.kioskOnly
            ? 'Nothing is expected at the kiosk today'
            : 'Nothing is expected today';
    }
    final line2 = next == null
        ? 'No shift in the next two weeks'
        : 'Next shift ${shortDate(next.date)} · ${next.label}';
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              line1,
              style: text.bodySmall?.copyWith(color: AppTheme.outline),
            ),
            Text(
              line2,
              style: text.bodySmall?.copyWith(color: AppTheme.outline),
            ),
          ],
        ),
      ),
    );
  }
}
