import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../services/saas_service.dart';
import '../../services/session_service.dart';
import '../../widgets/brand_logo.dart';
import '../../widgets/labeled_field.dart';
import '../../widgets/primary_button.dart';
import '../login/login_screen.dart';

class CompanyCodeScreen extends StatefulWidget {
  const CompanyCodeScreen({super.key});

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

  Future<void> _resolve() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final saas = SaasService();
      final info = await saas.resolveCompany(
        _saasUrlController.text.trim(),
        _codeController.text.trim(),
      );
      if (!mounted) return;

      final session = context.read<SessionService>();
      await session.saveCompany(
        saasUrl: _saasUrlController.text.trim(),
        companyCode: info.companyCode,
        clientUrl: info.odooUrl,
        clientDb: info.database,
        features: info.features,
        companyName: info.name,
        companyLogoB64: info.companyLogoB64,
        showConnectionDetails: info.showConnectionDetails,
      );

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    } catch (e) {
      setState(() => _error = e.toString());
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
