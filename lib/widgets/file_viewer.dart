import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import '../core/omni_colors.dart';

/// Decode a base64 payload to a temp file and open it with the system viewer.
/// Returns null on success, or an error message string.
Future<String?> openBase64File({
  required String name,
  required String dataB64,
}) async {
  try {
    final bytes = base64Decode(dataB64);
    final dir = await getTemporaryDirectory();
    final safeName = name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final file = File('${dir.path}/$safeName');
    await file.writeAsBytes(bytes, flush: true);
    final result = await OpenFilex.open(file.path);
    if (result.type != ResultType.done) {
      return result.message;
    }
    return null;
  } catch (e) {
    return e.toString();
  }
}

/// Show an error snackbar from a widget context.
void showFileViewError(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('Could not open file: $msg'),
      backgroundColor: context.omni.errorFill,
    ),
  );
}
