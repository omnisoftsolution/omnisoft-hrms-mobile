import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../core/error_messages.dart';
import '../../core/datetime_utils.dart';
import '../../core/money.dart';
import '../../models/expense_record.dart';
import '../../services/omni_mobile_api.dart';
import '../../services/session_service.dart';
import '../../widgets/feature_locked_pane.dart';
import '../../widgets/omni_app_bar.dart';
import 'expense_create_screen.dart';
import 'expense_detail_screen.dart';

/// Expenses tab — list of the user's submitted expenses with state
/// badges, plus a FAB to create a new one. Subscription gating
/// (FeatureLockedPane) is preserved from the previous stub.
class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});

  @override
  State<ExpensesScreen> createState() => ExpensesScreenState();
}

class ExpensesScreenState extends State<ExpensesScreen> {
  List<ExpenseRecord> _records = const [];
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refresh();
    });
  }

  /// Public alias for [_refresh] so HomeShell can trigger a reload
  /// after the user taps VIEW on an expense notification.
  Future<void> refresh() => _refresh();

  Future<void> _refresh() async {
    final session = context.read<SessionService>();
    if (!session.featureExpenses || !session.isLoggedIn) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = OmniMobileApi(
        baseUrl: session.clientUrl,
        db: session.clientDb,
        token: session.token,
      );
      final page = await api.getExpenseList();
      if (!mounted) return;
      setState(() {
        _records = page.records;
        _hasMore = page.hasMore;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Append the next page of older expenses, anchored on the oldest
  /// id currently in `_records`. Cursor-stable: a fresh submission
  /// between pages can't shift the cursor (its id is newer than the
  /// oldest in our list).
  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _records.isEmpty) return;
    final session = context.read<SessionService>();
    setState(() => _loadingMore = true);
    try {
      final api = OmniMobileApi(
        baseUrl: session.clientUrl,
        db: session.clientDb,
        token: session.token,
      );
      final page = await api.getExpenseList(beforeId: _records.last.id);
      if (!mounted) return;
      setState(() {
        _records = [..._records, ...page.records];
        _hasMore = page.hasMore;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load older: $e')),
      );
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _openCreate() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const ExpenseCreateScreen()),
    );
    if (created == true) {
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionService>();
    return Scaffold(
      appBar: const OmniAppBar(title: 'Expenses'),
      body: !session.featureExpenses
          ? const FeatureLockedPane(
              featureName: 'Expenses',
              subtitle: 'Your subscription does not include expense '
                  'tracking. Contact your administrator to upgrade.',
            )
          : _buildBody(),
      floatingActionButton: !session.featureExpenses
          ? null
          : FloatingActionButton.extended(
              onPressed: _openCreate,
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_rounded),
              label: const Text(
                'NEW EXPENSE',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
            ),
    );
  }

  Widget _buildBody() {
    if (_loading && _records.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _records.isEmpty) {
      return _errorPane(_error!);
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: _records.isEmpty
          ? _emptyState()
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              itemCount: _records.length + (_hasMore ? 1 : 0),
              itemBuilder: (_, i) {
                if (i == _records.length) return _loadOlderTile();
                return _expenseTile(_records[i]);
              },
            ),
    );
  }

  Widget _loadOlderTile() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: OutlinedButton.icon(
          icon: _loadingMore
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.history_rounded),
          label: Text(_loadingMore ? 'Loading…' : 'Load older'),
          onPressed: _loadingMore ? null : _loadMore,
        ),
      ),
    );
  }

  Widget _emptyState() {
    return ListView(
      // ListView (vs. Center) lets pull-to-refresh still work on empty.
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 80),
      children: [
        Container(
          width: 88,
          height: 88,
          margin: const EdgeInsets.only(bottom: 24),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppTheme.primaryContainer.withValues(alpha: 0.12),
            border: Border.all(
              color: AppTheme.primaryContainer.withValues(alpha: 0.35),
              width: 1.5,
            ),
          ),
          child: Icon(
            Icons.receipt_long_rounded,
            size: 36,
            color: AppTheme.primary,
          ),
        ),
        Text(
          'No expenses yet',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: AppTheme.onSurface,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Tap NEW EXPENSE to submit a receipt for reimbursement.',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            fontSize: 14,
            color: AppTheme.onSurfaceVariant,
            height: 1.45,
          ),
        ),
      ],
    );
  }

  Widget _expenseTile(ExpenseRecord r) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () async {
          // The detail screen pops `true` after a successful edit;
          // refresh the list so the new values / state are visible.
          final updated = await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (_) => ExpenseDetailScreen(record: r),
            ),
          );
          if (updated == true && mounted) {
            await _refresh();
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.primaryContainer.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.receipt_long_rounded,
                  color: AppTheme.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.name.isEmpty ? '(No description)' : r.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      // Primary: submission time. "Submitted today" /
                      // "Submitted 27 Apr" — answers "when did I
                      // submit this", which is the dominant question.
                      '${r.productName.isEmpty ? "—" : r.productName} · '
                      '${DateTimeUtils.formatSubmittedAgo(r.createDate)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.onSurfaceVariant,
                      ),
                    ),
                    if (r.date.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        // Secondary: the receipt's own date. Makes
                        // an OCR-misread year (or just an old receipt)
                        // visible right next to the submission date.
                        'Receipt ${DateTimeUtils.formatLocalDate(r.date)}',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.onSurfaceVariant
                              .withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Hard-cap the trailing column width so a freak legacy
              // amount (e.g. 1.3e+25 from pre-validation days) can't
              // crater the layout by starving the Expanded description
              // column of horizontal space.
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 140),
                child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    expenseListAmount(r),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _stateColor(r.state).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      r.stateLabel.toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                        color: _stateColor(r.state),
                      ),
                    ),
                  ),
                ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _stateColor(String state) {
    switch (state) {
      case 'draft':
        return AppTheme.onSurfaceVariant;
      case 'submitted':
        return AppTheme.secondary;
      case 'approved':
      case 'posted':
      case 'in_payment':
        return AppTheme.primary;
      case 'paid':
        return const Color(0xFF22C55E);
      case 'refused':
        return AppTheme.error;
      default:
        return AppTheme.onSurfaceVariant;
    }
  }

  Widget _errorPane(String msg) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: AppTheme.error, size: 48),
            const SizedBox(height: 12),
            Text(msg,
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.error)),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: _refresh,
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}
