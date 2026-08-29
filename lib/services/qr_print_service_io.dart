/// Non-web implementation of the QR print service.
///
/// Browser printing is only available on the web target, so this always
/// reports failure and lets the caller show a graceful fallback message.
Future<bool> printQrHtml(String html) async {
  return false;
}
