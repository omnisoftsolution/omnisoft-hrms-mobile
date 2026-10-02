import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../core/error_messages.dart';
import '../../services/session_service.dart';
import '../../widgets/brand_logo.dart';
import '../../widgets/labeled_field.dart';
import '../../widgets/primary_button.dart';
import '../activation/activation_screen.dart';
import '../activation/invite_scan_screen.dart';
import '../login/login_screen.dart';

class CompanyCodeScreen extends StatefulWidget {
  const CompanyCodeScreen({super.key, this.scanInvite, this.hasCamera});

  @visibleForTesting
  final Future<ScanOutcome?> Function(BuildContext)? scanInvite;

  @visibleForTesting
  final Future<bool> Function()? hasCamera;

  @override
  State<CompanyCodeScreen> createState() => _CompanyCodeScreenState();
}

class _CompanyCodeScreenState extends State<CompanyCodeScreen> {
  final _codeController =
      TextEditingController(text: DevConstants.defaultCompanyCode);
  final _saasUrlController =
      TextEditingController(text: DevConstants.defaultSaasUrl);
  bool _loading = false;
  String? _error;
  bool _canScan = false;

  @override
  void initState() {
    super.initState();
    (widget.hasCamera ?? cameraAvailable)().then((v) {
      if (mounted && v) setState(() => _canScan = true);
    });
  }

  Future<void> _scanInvite() async {
    final outcome = await (widget.scanInvite ?? openInviteScanner)(context);
    if (!mounted || outcome == null) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => switch (outcome) {
        ScannedInvite(:final args) => ActivationScreen(
            companyCode: args.companyCode,
            token: args.token,
            login: args.login),
        EnterCodeInstead() => const ActivationScreen(),
      },
    ));
  }

  Future<void> _resolve() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await context.read<SessionService>().resolveCompany(
            _codeController.text.trim(),
            saasUrl: _saasUrlController.text.trim(),
          );

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding:
                  const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                    minHeight: constraints.maxHeight - 64),
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 32),
                      Center(
                        child: Column(
                          children: [
                            const BrandLogo.large(),
                            const SizedBox(height: 24),
                            Text(
                              AppConstants.appName,
                              style: Theme.of(context)
                                  .textTheme
                                  .displaySmall
                                  ?.copyWith(color: AppTheme.onSurface),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'CONNECT TO YOUR COMPANY',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 4,
                                color: AppTheme.primaryContainer,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 40),
                      LabeledField(
                        label: 'SaaS Server URL',
                        controller: _saasUrlController,
                        prefixIcon: Icons.cloud_outlined,
                        keyboardType: TextInputType.url,
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 20),
                      LabeledField(
                        label: 'Company Code',
                        controller: _codeController,
                        hintText: 'Provided by your HR administrator',
                        prefixIcon: Icons.vpn_key_outlined,
                        textCapitalization: TextCapitalization.characters,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _resolve(),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppTheme.error.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: AppTheme.error.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.error_outline,
                                  color: AppTheme.error, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _error!,
                                  style: TextStyle(
                                      color: AppTheme.error, fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 28),
                      PrimaryButton(
                        label: 'CONNECT',
                        loading: _loading,
                        onPressed: _loading ? null : _resolve,
                      ),
                      if (_canScan) ...[
                        const SizedBox(height: 16),
                        SizedBox(
                          height: 52,
                          child: FilledButton.tonalIcon(
                            key: const Key('company_scan'),
                            onPressed: _loading ? null : _scanInvite,
                            icon: const Icon(Icons.qr_code_scanner_rounded),
                            label: const Text('Scan invite QR'),
                          ),
                        ),
                      ],
                      const Spacer(),
                      const SizedBox(height: 24),
                      Center(
                        child: Text(
                          'POWERED BY OMNISOFT TECHNOLOGIES',
                          maxLines: 1,
                          overflow: TextOverflow.visible,
                          style: GoogleFonts.inter(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 2,
                            color: AppTheme.outline.withValues(alpha: 0.7),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
