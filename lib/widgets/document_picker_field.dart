import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../core/theme.dart';
import 'file_viewer.dart';

/// Allowed attachment file types for leave docs / supporting documents.
///
/// The whitelist is the mobile UX layer of a two-layer defense — the
/// connector enforces the same list server-side via magic-byte checks,
/// so this list ONLY controls what the user sees in the picker and
/// gets a clean snackbar for if a misbehaving OEM picker ignores the
/// filter. Direct API calls bypass this entirely; only the server-side
/// validator stops those.
const _kAllowedExtensions = ['pdf', 'jpg', 'jpeg', 'png', 'heic', 'heif'];

/// Cap matches the connector's `ir.attachment` size limit. Files
/// larger than this are rejected client-side with a clean message
/// rather than blowing up on upload.
const _kMaxSizeBytes = 10 * 1024 * 1024; // 10 MB

class PickedDocument {
  final String name;
  final String mimetype;
  final String dataB64;
  final int size;

  PickedDocument({
    required this.name,
    required this.mimetype,
    required this.dataB64,
    required this.size,
  });

  Map<String, dynamic> toApiJson() => {
        'name': name,
        'mimetype': mimetype,
        'data_b64': dataB64,
      };

  String get sizeLabel {
    if (size < 1024) return '${size}B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(0)}KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)}MB';
  }
}

class DocumentPickerField extends StatelessWidget {
  final PickedDocument? picked;
  final bool required;
  final ValueChanged<PickedDocument?> onChanged;

  const DocumentPickerField({
    super.key,
    required this.picked,
    required this.onChanged,
    this.required = false,
  });

  /// Camera primary path — for paper docs the user wants to snap
  /// right now (handwritten letters, clinic stamps, etc).
  Future<void> _pickFromCamera(BuildContext context) async {
    // Capture the messenger before any await so we can surface
    // errors after the async gap without touching `context` again.
    final messenger = ScaffoldMessenger.of(context);
    try {
      final xfile = await ImagePicker().pickImage(
        source: ImageSource.camera,
        imageQuality: 85, // ~200-500KB jpegs; same as expense receipts
      );
      if (xfile == null) return;
      final bytes = await xfile.readAsBytes();
      if (bytes.length > _kMaxSizeBytes) {
        _showSnack(messenger, 'Photo is too large. Max 10 MB.');
        return;
      }
      final ext = xfile.name.contains('.')
          ? xfile.name.split('.').last
          : 'jpg';
      onChanged(PickedDocument(
        name: xfile.name,
        mimetype: _guessMimetype(ext),
        dataB64: base64Encode(bytes),
        size: bytes.length,
      ));
    } catch (e) {
      _showSnack(messenger, 'Could not capture photo: $e');
    }
  }

  /// Files fallback — for medical PDFs, scanned certs already on
  /// disk, library photos (iOS Files → Photos), anything non-camera.
  /// Restricted to PDF / JPG / PNG / HEIC via the picker filter +
  /// a second extension check after pick (some OEM Android pickers
  /// ignore the `allowedExtensions` filter and return any file).
  Future<void> _pickFromFiles(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: _kAllowedExtensions,
        allowMultiple: false,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final f = result.files.single;
      if (f.bytes == null && f.path == null) return;

      // OEM-bypass guard: revalidate the extension. The picker filter
      // is advisory on some Android builds.
      final ext = (f.extension ?? '').toLowerCase();
      if (!_kAllowedExtensions.contains(ext)) {
        _showSnack(
          messenger,
          'Unsupported file type. Allowed: ${_kAllowedExtensions.join(", ").toUpperCase()}.',
        );
        return;
      }
      if (f.size > _kMaxSizeBytes) {
        _showSnack(messenger, 'File is too large. Max 10 MB.');
        return;
      }

      final bytes = f.bytes ?? await File(f.path!).readAsBytes();
      onChanged(PickedDocument(
        name: f.name,
        mimetype: _guessMimetype(ext),
        dataB64: base64Encode(bytes),
        size: bytes.length,
      ));
    } catch (e) {
      _showSnack(messenger, 'Could not pick file: $e');
    }
  }

  void _showSnack(ScaffoldMessengerState messenger, String message) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppTheme.error,
      ),
    );
  }

  String _guessMimetype(String? ext) {
    switch (ext?.toLowerCase()) {
      case 'pdf':
        return 'application/pdf';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'heic':
      case 'heif':
        return 'image/heic';
      default:
        return 'application/octet-stream';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (picked == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => _pickFromCamera(context),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                border: Border.all(
                  color: required ? AppTheme.error : AppTheme.outline,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.camera_alt_rounded,
                      size: 18,
                      color:
                          required ? AppTheme.error : AppTheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          required
                              ? 'Supporting document required'
                              : 'Capture supporting document',
                          style: TextStyle(
                            fontSize: 12,
                            color: required
                                ? AppTheme.error
                                : AppTheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text('Tap to take a photo',
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: AppTheme.outline),
                ],
              ),
            ),
          ),
          Center(
            child: TextButton(
              onPressed: () => _pickFromFiles(context),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 4),
                minimumSize: const Size(0, 0),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                'or pick from files',
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ],
      );
    }
    final p = picked!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        border: Border.all(color: AppTheme.primary),
        color: AppTheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.description_outlined, size: 20, color: AppTheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(p.sizeLabel,
                    style: TextStyle(
                        fontSize: 12, color: AppTheme.onSurfaceVariant)),
              ],
            ),
          ),
          IconButton(
            tooltip: 'View',
            icon: Icon(Icons.visibility_outlined, color: AppTheme.primary),
            onPressed: () async {
              final err = await openBase64File(
                  name: p.name, dataB64: p.dataB64);
              if (err != null && context.mounted) {
                showFileViewError(context, err);
              }
            },
          ),
          IconButton(
            tooltip: 'Replace',
            icon: Icon(Icons.refresh_rounded, color: AppTheme.primary),
            onPressed: () => _pickFromCamera(context),
          ),
          IconButton(
            tooltip: 'Remove',
            icon: Icon(Icons.close_rounded, color: AppTheme.error),
            onPressed: () => onChanged(null),
          ),
        ],
      ),
    );
  }
}
