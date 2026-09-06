import 'qr_print_service_io.dart'
    if (dart.library.html) 'qr_print_service_web.dart' as impl;

/// Opens the platform print dialog for a printer-friendly QR document.
///
/// On web this opens the generated document in a new tab and calls
/// `window.print()`. On non-web platforms it returns `false` so callers can
/// offer a fallback (for example the existing native Share action).
Future<bool> printQrHtml(String html) => impl.printQrHtml(html);
