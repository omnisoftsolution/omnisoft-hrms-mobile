import 'package:flutter/material.dart';

/// Home's body layout, split out of HomeScreen so it can be tested
/// without the device plugins HomeScreen needs.
///
/// The [approvalsCard] sits first whatever the attendance state is:
/// above the [lockedPane] when the Attendance feature is off, and first
/// in the scrollable column (before the loading / error / content
/// [children]) when it is on. The card hides itself for non-approvers.
class HomeBody extends StatelessWidget {
  const HomeBody({
    super.key,
    required this.attendanceEnabled,
    required this.approvalsCard,
    required this.lockedPane,
    required this.onRefresh,
    required this.children,
  });

  final bool attendanceEnabled;
  final Widget approvalsCard;
  final Widget lockedPane;
  final Future<void> Function() onRefresh;

  /// Loading spinner, error view or attendance content.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (!attendanceEnabled) {
      // Scrollable so the locked pane (a non-scrolling Column) can never
      // overflow under the card, large text or its error banner; it stays
      // centred when there is room. Pull-to-refresh works here too.
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: approvalsCard,
              ),
            ),
            SliverFillRemaining(hasScrollBody: false, child: lockedPane),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [approvalsCard, ...children],
      ),
    );
  }
}
