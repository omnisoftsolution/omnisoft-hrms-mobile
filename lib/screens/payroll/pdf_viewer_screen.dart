import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/theme.dart';
import '../../core/error_messages.dart';
import '../../widgets/file_viewer.dart';

/// Inline PDF viewer used by PayslipsScreen. Decodes a base64 PDF
/// payload to a temp file once in initState, then renders via
/// flutter_pdfview (Android's native PdfRenderer / iOS's PDFKit).
///
/// Keeps an "Open externally" escape hatch in the overflow menu so
/// power users can still hand off to Files / OneDrive / Drive when
/// they want to save or share.
class PdfViewerScreen extends StatefulWidget {
  /// Base64-encoded PDF bytes (the `data_b64` field from
  /// `getPayslipPdf`).
  final String dataB64;

  /// File name suggested by the server. Used for the AppBar title
  /// (with `.pdf` stripped) and for the temp-file name.
  final String filename;

  const PdfViewerScreen({
    super.key,
    required this.dataB64,
    required this.filename,
  });

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  String? _filePath;
  String? _error;
  int? _totalPages;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _writeTempFile();
  }

  Future<void> _writeTempFile() async {
    try {
      final bytes = base64Decode(widget.dataB64);
      // App cache dir (NOT temp): private to the app on all Android
      // target SDKs. temp dir is world-readable on older targets.
      final dir = await getApplicationCacheDirectory();
      // Sanitize as openBase64File does — keeps the filename
      // filesystem-safe across Android and iOS.
      final safeName = widget.filename
          .replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final file = File('${dir.path}/$safeName');
      await file.writeAsBytes(bytes, flush: true);
      if (!mounted) {
        // Lifecycle race — widget unmounted between decode and write
        // completion. Clean up so we don't orphan the file.
        await file.delete().catchError((_) => file);
        return;
      }
      setState(() => _filePath = file.path);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyError(e));
    }
  }

  @override
  void dispose() {
    // Best-effort delete of the cached PDF — we don't want payslip
    // PDFs accumulating in the app cache dir between sessions. If
    // the OS GC'd it first or the user never reached _filePath set,
    // the catchError swallows the missing-file error.
    final p = _filePath;
    if (p != null) {
      File(p).delete().catchError((_) => File(p));
    }
    super.dispose();
  }

  Future<void> _openExternally() async {
    final err = await openBase64File(
      name: widget.filename,
      dataB64: widget.dataB64,
    );
    if (err != null && mounted) {
      showFileViewError(context, err);
    }
  }

  String get _title {
    final n = widget.filename;
    final lower = n.toLowerCase();
    if (lower.endsWith('.pdf')) {
      return n.substring(0, n.length - 4);
    }
    return n;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Plain AppBar (NOT OmniAppBar) — the embedded viewer doesn't
      // want the brand chrome / bell / avatar. Back arrow is auto-
      // implied because this is a pushed route.
      appBar: AppBar(
        title: Text(
          _title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'More',
            onSelected: (v) {
              if (v == 'external') _openExternally();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'external',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.open_in_new_rounded),
                  title: Text('Open externally'),
                ),
              ),
            ],
          ),
        ],
        bottom: _totalPages != null && _totalPages! > 1
            ? PreferredSize(
                preferredSize: const Size.fromHeight(24),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    'Page ${_currentPage + 1} of $_totalPages',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.onSurfaceVariant,
                    ),
                  ),
                ),
              )
            : null,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, color: AppTheme.error, size: 48),
              const SizedBox(height: 12),
              Text(
                'Could not load PDF.\n$_error',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.error),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                icon: const Icon(Icons.open_in_new_rounded),
                label: const Text('Open externally'),
                onPressed: _openExternally,
              ),
            ],
          ),
        ),
      );
    }
    if (_filePath == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return PDFView(
      filePath: _filePath,
      enableSwipe: true,
      swipeHorizontal: false,
      autoSpacing: true,
      pageFling: true,
      pageSnap: true,
      fitPolicy: FitPolicy.BOTH,
      onRender: (pages) {
        if (mounted) setState(() => _totalPages = pages);
      },
      onPageChanged: (page, _) {
        if (mounted) setState(() => _currentPage = page ?? 0);
      },
      onError: (err) {
        if (mounted) setState(() => _error = err.toString());
      },
    );
  }
}
