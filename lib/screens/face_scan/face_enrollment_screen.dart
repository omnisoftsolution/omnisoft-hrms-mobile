import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants.dart';
import '../../core/error_messages.dart';
import '../../core/theme.dart';
import '../../models/face_capture_result.dart';
import '../../services/face_recognition_service.dart';
import '../../services/session_service.dart';
import 'face_capture_screen.dart';

/// Re-enrollment / first enrollment flow.
///
/// Opens the camera, lets the user capture + confirm, then uploads
/// the resulting JPEG to Odoo via FaceRecognitionService.enrollFace.
class FaceEnrollmentScreen extends StatefulWidget {
  const FaceEnrollmentScreen({super.key});

  @override
  State<FaceEnrollmentScreen> createState() => _FaceEnrollmentScreenState();
}

/// Text for a failed enrollment: the local face-quality and liveness checks
/// keep their own friendly messages; everything from the server goes
/// through [friendlyError] (never a raw code).
String enrollmentErrorText(Object e) {
  if (e is FaceQualityException || e is FaceLivenessException) {
    return e.toString();
  }
  return friendlyError(e);
}

class _FaceEnrollmentScreenState extends State<FaceEnrollmentScreen> {
  bool _uploading = false;
  String? _error;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    final captureResult = await Navigator.of(context).push<FaceCaptureResult>(
      MaterialPageRoute(builder: (_) => const FaceCaptureScreen()),
    );
    if (!mounted) return;
    if (captureResult == null || !captureResult.success) {
      Navigator.of(context).pop(false);
      return;
    }

    setState(() {
      _uploading = true;
      _error = null;
    });
    try {
      final session = context.read<SessionService>();
      final svc = context.read<FaceRecognitionService>();
      await svc.enrollFace(session, captureResult.imagePath!);
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _done = true;
      });
      await Future.delayed(const Duration(milliseconds: 800));
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _error = enrollmentErrorText(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Enroll Face')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (DevConstants.simulateFaceRecognition) ...[
                _devBanner(),
                const SizedBox(height: 24),
              ],
              if (_error != null) ...[
                Icon(Icons.error_outline, size: 64, color: AppTheme.error),
                const SizedBox(height: 16),
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: _start,
                      child: const Text('Try Again'),
                    ),
                  ],
                ),
              ] else if (_done) ...[
                Icon(Icons.check_circle,
                    size: 64, color: AppTheme.primary),
                const SizedBox(height: 16),
                const Text('Face enrolled successfully',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
              ] else if (_uploading) ...[
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                const Text('Uploading enrollment…'),
              ] else
                const CircularProgressIndicator(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _devBanner() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.developer_mode, color: Colors.orange, size: 20),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'DEV MODE: face recognition simulated',
              style: TextStyle(
                  color: Colors.orange,
                  fontSize: 12,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
