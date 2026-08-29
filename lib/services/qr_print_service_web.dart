// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

/// Web implementation: open the printer-friendly QR document in a new tab via a
/// Blob URL. The document's inline script triggers the browser's native print
/// dialog and also includes a visible fallback Print button.
Future<bool> printQrHtml(String content) async {
  try {
    final blob = html.Blob([content], 'text/html');
    final url = html.Url.createObjectUrlFromBlob(blob);
    html.window.open(url, '_blank');

    // Release the object URL once the new tab has had time to load it.
    Future.delayed(const Duration(minutes: 1), () {
      html.Url.revokeObjectUrl(url);
    });

    return true;
  } catch (_) {
    return false;
  }
}
