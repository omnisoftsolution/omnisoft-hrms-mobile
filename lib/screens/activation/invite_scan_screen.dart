import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../services/deep_link_service.dart';
import '../../widgets/error_state_view.dart';

/// What the invite scanner hands back to the screen that opened it.
sealed class ScanOutcome {
  const ScanOutcome();
}

class ScannedInvite extends ScanOutcome {
  final ActivationArgs args;
  const ScannedInvite(this.args);
}

class EnterCodeInstead extends ScanOutcome {
  const EnterCodeInstead();
}

/// Builds the live camera view. Tests pass a stand-in.
typedef InviteScannerBuilder = Widget Function(
  BuildContext context, {
  required void Function(String raw) onCode,
  required VoidCallback onPermissionDenied,
});

/// Opens the scanner; resolves to what it found, or null on back.
Future<ScanOutcome?> openInviteScanner(BuildContext context) =>
    Navigator.of(context).push<ScanOutcome>(
        MaterialPageRoute(builder: (_) => const InviteScanScreen()));

/// Whether this device has any camera (false on any plugin error).
Future<bool> cameraAvailable() async {
  try {
    return (await availableCameras()).isNotEmpty;
  } catch (_) {
    return false;
  }
}

/// What the camera area shows when the scanner fails. Permission denied keeps
/// the black box (the screen swaps to its own explanation); any other error
/// says so instead of leaving a blank screen.
@visibleForTesting
Widget cameraErrorView(
    MobileScannerErrorCode code, VoidCallback onPermissionDenied) {
  if (code == MobileScannerErrorCode.permissionDenied) {
    WidgetsBinding.instance.addPostFrameCallback((_) => onPermissionDenied());
    return const ColoredBox(color: Colors.black);
  }
  return const ColoredBox(
    color: Colors.black,
    child: Center(
      child: ErrorStateView(
          message: 'The camera could not start. Enter the code instead.'),
    ),
  );
}

/// Full-screen QR scanner for HR's invite. Accepts both invite link forms
/// (see [classifyScan]); anything else shows a short note and keeps
/// scanning.
class InviteScanScreen extends StatefulWidget {
  const InviteScanScreen({super.key, this.scannerBuilder, this.openSettings});

  @visibleForTesting
  final InviteScannerBuilder? scannerBuilder;

  @visibleForTesting
  final Future<void> Function()? openSettings;

  @override
  State<InviteScanScreen> createState() => _InviteScanScreenState();
}

class _InviteScanScreenState extends State<InviteScanScreen>
    with WidgetsBindingObserver {
  final _controller = MobileScannerController(
      formats: const [BarcodeFormat.qrCode], autoStart: true);
  bool _done = false;
  bool _denied = false;
  bool _sentToSettings = false;
  bool _showNotInvite = false;
  String? _lastRejected;
  int _generation = 0;
  Timer? _hide;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hide?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _denied && _sentToSettings) {
      setState(() {
        _denied = false;
        _sentToSettings = false;
        _generation++;
      });
    }
  }

  void _onCode(String raw) {
    if (_done || !mounted) return;
    final r = classifyScan(raw);
    if (r is InviteScan) {
      _done = true;
      HapticFeedback.lightImpact();
      Navigator.of(context).pop(ScannedInvite(r.args));
      return;
    }
    if (raw == _lastRejected) return;
    _lastRejected = raw;
    _hide?.cancel();
    setState(() => _showNotInvite = true);
    _hide = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showNotInvite = false);
    });
  }

  void _onDenied() {
    if (mounted && !_denied) setState(() => _denied = true);
  }

  Future<void> _openSettings() async {
    _sentToSettings = true;
    await (widget.openSettings ?? Geolocator.openAppSettings)();
  }

  void _enterCode() {
    if (_done) return;
    _done = true;
    Navigator.of(context).pop(const EnterCodeInstead());
  }

  Widget _defaultScanner(BuildContext context,
      {required void Function(String raw) onCode,
      required VoidCallback onPermissionDenied}) {
    return MobileScanner(
      controller: _controller,
      onDetect: (capture) {
        for (final b in capture.barcodes) {
          final v = b.rawValue;
          if (v != null) onCode(v);
        }
      },
      errorBuilder: (context, error) =>
          cameraErrorView(error.errorCode, onPermissionDenied),
    );
  }

  @override
  Widget build(BuildContext context) {
    final build = widget.scannerBuilder ?? _defaultScanner;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Scan invite QR'),
        actions: [
          if (!_denied && widget.scannerBuilder == null)
            IconButton(
              tooltip: 'Torch',
              icon: const Icon(Icons.flashlight_on_outlined),
              onPressed: () => _controller.toggleTorch(),
            ),
        ],
      ),
      body: _denied
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ErrorStateView(
                      message: 'Camera access is off. Turn it on in '
                          'Settings, or enter the code instead.',
                      onRetry: _openSettings,
                      retryLabel: 'Open Settings',
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                        onPressed: _enterCode,
                        child: const Text('Enter code')),
                  ],
                ),
              ),
            )
          : Stack(
              fit: StackFit.expand,
              children: [
                KeyedSubtree(
                  key: ValueKey(_generation),
                  child: build(context,
                      onCode: _onCode, onPermissionDenied: _onDenied),
                ),
                Center(
                  child: Container(
                    width: 240,
                    height: 240,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white, width: 3),
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                ),
                Positioned(
                  left: 24,
                  right: 24,
                  bottom: 40,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_showNotInvite)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.black87,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            'This is not an Omni HR invite QR.',
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: _enterCode,
                        style: TextButton.styleFrom(
                            foregroundColor: Colors.white),
                        child: const Text('Enter code instead'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
