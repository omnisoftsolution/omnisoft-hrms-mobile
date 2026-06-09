import 'dart:typed_data';
import 'package:pdfx/pdfx.dart';

/// Rasterizes PDF pages to images for OCR + thumbnail preview.
///
/// This is a BEST-EFFORT enhancement. The original PDF is always what
/// gets uploaded as the stored receipt — rasterization only powers the
/// in-app preview thumbnail and the page-images we send to OCR. Every
/// entry point here is designed to fail soft (return empty / null)
/// rather than throw, so a corrupt/encrypted/huge PDF can never block
/// attaching or submitting the expense.
///
/// Uses the OS PDF engine via pdfx (Android PdfRenderer / iOS
/// CoreGraphics) — no bundled pdfium, so no clash with flutter_pdfview.
class PdfRaster {
  /// Cap on pages we rasterize for OCR. Must match the connector's
  /// `_OCR_MAX_PAGES`. The whole PDF still uploads; this only bounds how
  /// many page-images we render and send to the VLM.
  static const int maxOcrPages = 10;

  /// Render width in pixels. ~1240px is ≈150 DPI for an A4 page — sharp
  /// enough for OCR text, small enough that a JPEG page stays well under
  /// the connector's 5 MB per-image cap.
  static const double _renderWidth = 1240;

  /// Returns the page count of [pdfBytes], or null if it can't be opened
  /// (not a PDF, encrypted, corrupt). Never throws.
  static Future<int?> pageCount(Uint8List pdfBytes) async {
    PdfDocument? doc;
    try {
      doc = await PdfDocument.openData(pdfBytes);
      return doc.pagesCount;
    } catch (_) {
      return null;
    } finally {
      await doc?.close();
    }
  }

  /// Renders the first page of [pdfBytes] to a JPEG, for the preview
  /// thumbnail. Returns null on any failure. Never throws.
  static Future<Uint8List?> renderFirstPage(Uint8List pdfBytes) async {
    final pages = await renderPages(pdfBytes, limit: 1);
    return pages.isEmpty ? null : pages.first;
  }

  /// Renders up to [limit] pages (default [maxOcrPages]) of [pdfBytes] to
  /// JPEG bytes, in page order, for OCR. Returns an empty list on any
  /// failure — callers treat empty as "couldn't rasterize, skip OCR".
  /// A single bad page is skipped rather than aborting the whole doc.
  /// Never throws.
  static Future<List<Uint8List>> renderPages(
    Uint8List pdfBytes, {
    int limit = maxOcrPages,
  }) async {
    final out = <Uint8List>[];
    PdfDocument? doc;
    try {
      doc = await PdfDocument.openData(pdfBytes);
      final count = doc.pagesCount;
      final n = count < limit ? count : limit;
      for (var i = 1; i <= n; i++) {
        PdfPage? page;
        try {
          page = await doc.getPage(i);
          final img = await page.render(
            width: _renderWidth,
            height: _renderWidth * (page.height / page.width),
            format: PdfPageImageFormat.jpeg,
            backgroundColor: '#FFFFFF',
          );
          final bytes = img?.bytes;
          if (bytes != null && bytes.isNotEmpty) out.add(bytes);
        } catch (_) {
          // Skip this page; keep whatever rendered so far.
        } finally {
          await page?.close();
        }
      }
    } catch (_) {
      // Whole-doc failure (not a PDF, encrypted, OOM) — return what we
      // have, which may be empty. Caller degrades to upload-only.
    } finally {
      await doc?.close();
    }
    return out;
  }
}
