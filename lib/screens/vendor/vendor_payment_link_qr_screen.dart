import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../constants/app_colors.dart';
import '../../models/payment_link.dart';
import '../../providers/currency_provider.dart';
import '../../services/qr_print_service.dart';

/// Dedicated QR page for a single payment link.
///
/// Mirrors the plugin's `DPL_Dashboard::render_qr()` view: label, amount, a
/// scannable QR code, a copyable direct checkout link, and full sharing
/// (native share sheet, WhatsApp and Email).
class VendorPaymentLinkQrScreen extends StatelessWidget {
  const VendorPaymentLinkQrScreen({super.key, required this.link});

  final PaymentLink link;

  @override
  Widget build(BuildContext context) {
    final symbol = context.watch<CurrencyProvider>().currencySymbol;
    final amountLabel = _amountLabel(symbol);

    return Scaffold(
      backgroundColor: AppColors.creamColor,
      appBar: AppBar(
        backgroundColor: AppColors.whiteColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.inkColor),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('QR Payment Page',
            style: TextStyle(
                color: AppColors.inkColor,
                fontWeight: FontWeight.w600,
                fontFamily: 'Fraunces')),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.whiteColor,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.inkSoftColor.withOpacity(0.08)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                Text(link.label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: AppColors.inkColor,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'Fraunces')),
                const SizedBox(height: 6),
                Text(amountLabel,
                    style: const TextStyle(
                        color: AppColors.goldColor,
                        fontSize: 15,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border:
                        Border.all(color: AppColors.inkSoftColor.withOpacity(0.15)),
                  ),
                  child: QrImageView(
                    data: link.payUrl,
                    version: QrVersions.auto,
                    size: 240,
                    backgroundColor: Colors.white,
                    errorCorrectionLevel: QrErrorCorrectLevel.M,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Scan this QR code with your phone camera to pay',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.inkSoftColor, fontSize: 13),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: () => _printQr(context),
                  icon: const Icon(Icons.print, size: 20),
                  label: const Text('Print QR Code'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.inkColor,
                    foregroundColor: AppColors.whiteColor,
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 24),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Direct checkout link',
                      style: TextStyle(
                          color: AppColors.inkSoftColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: 8),
                _DirectLinkField(url: link.payUrl),
                const SizedBox(height: 24),
                _ShareActions(
                  link: link,
                  onShare: () => _shareNative(context, link),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _amountLabel(String symbol) {
    final formatted = link.amountFormatted;
    if (formatted != null && formatted.isNotEmpty) return formatted;
    if (link.amount > 0) return '$symbol${link.amount.toStringAsFixed(2)}';
    return 'Customer chooses amount';
  }

  /// Generate a printer-friendly version of the QR page and open the platform
  /// print dialog. On web this opens a clean, scannable QR document in a new
  /// tab; on other platforms it falls back to a helpful message.
  Future<void> _printQr(BuildContext context) async {
    final symbol = context.read<CurrencyProvider>().currencySymbol;
    final amountLabel = _amountLabel(symbol);

    final qrBytes = await _generateQrPng();
    if (qrBytes == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Could not prepare the QR code for printing.')),
        );
      }
      return;
    }

    final printed = await printQrHtml(_buildPrintHtml(amountLabel, qrBytes));
    if (!printed && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Printing is available in the web app. Use Share to send this QR instead.'),
        ),
      );
    }
  }

  Future<Uint8List?> _generateQrPng() async {
    final painter = QrPainter(
      data: link.payUrl,
      version: QrVersions.auto,
      errorCorrectionLevel: QrErrorCorrectLevel.M,
      gapless: true,
    );
    final data = await painter.toImageData(512.0);
    if (data == null) return null;
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  String _buildPrintHtml(String amountLabel, Uint8List qrBytes) {
    final base64 = base64Encode(qrBytes);
    final label = _escapeHtml(link.label);
    final amount = _escapeHtml(amountLabel);
    final url = _escapeHtml(link.payUrl);

    return '''
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>$label — QR Payment</title>
<style>
  :root { color-scheme: light; }
  * { box-sizing: border-box; }
  body {
    margin: 0; padding: 24px; color: #161B2B; background: #fff;
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
    -webkit-print-color-adjust: exact; print-color-adjust: exact;
  }
  .toolbar { text-align: right; margin-bottom: 16px; }
  .print-btn { background: #E67E14; color: #fff; border: none; border-radius: 8px;
    padding: 11px 20px; font-size: 14px; font-weight: 600; cursor: pointer; }
  .card { max-width: 420px; margin: 0 auto; border: 1px solid #eee; border-radius: 16px;
    padding: 32px 24px; text-align: center; }
  .label { font-size: 22px; font-weight: 700; margin: 0 0 6px; overflow-wrap: anywhere; }
  .amount { font-size: 16px; color: #E67E14; font-weight: 600; margin: 0 0 22px; }
  .qr-wrap { display: inline-block; border: 1px solid #eee; border-radius: 12px;
    padding: 12px; background: #fff; }
  .qr { display: block; width: 320px; height: 320px; max-width: 100%; }
  .hint { font-size: 13px; color: #5B5F70; margin: 14px 0 20px; }
  .link { font-size: 12px; color: #555; overflow-wrap: anywhere; }
  @media print {
    body { padding: 0; }
    .toolbar { display: none; }
    .card { border: none; max-width: none; }
    .qr-wrap { border: none; }
  }
</style>
</head>
<body>
  <div class="toolbar"><button class="print-btn" onclick="window.print()">Print</button></div>
  <div class="card">
    <h1 class="label">$label</h1>
    <p class="amount">$amount</p>
    <div class="qr-wrap"><img class="qr" src="data:image/png;base64,$base64" alt="QR code"></div>
    <p class="hint">Scan this QR code with your phone camera to pay</p>
    <p class="link">$url</p>
  </div>
  <script>
    window.addEventListener('load', function () {
      setTimeout(function () { window.print(); }, 250);
    });
  </script>
</body>
</html>
''';
  }

  String _escapeHtml(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
  }

  Future<void> _shareNative(BuildContext context, PaymentLink link) async {
    final box = context.findRenderObject() as RenderBox?;
    final origin =
        box != null ? box.localToGlobal(Offset.zero) & box.size : null;
    final message = link.label.isNotEmpty
        ? '${link.label} — ${link.payUrl}'
        : link.payUrl;
    await Share.share(
      message,
      subject: link.label,
      sharePositionOrigin: origin,
    );
  }
}

class _DirectLinkField extends StatelessWidget {
  const _DirectLinkField({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.creamColor,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.inkSoftColor.withOpacity(0.12)),
            ),
            child: Text(url,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.inkSoftColor, fontSize: 13)),
          ),
        ),
        const SizedBox(width: 10),
        ElevatedButton.icon(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: url));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Payment link copied')),
            );
          },
          icon: const Icon(Icons.copy, size: 16),
          label: const Text('Copy'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.goldColor,
            foregroundColor: AppColors.whiteColor,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          ),
        ),
      ],
    );
  }
}

class _ShareActions extends StatelessWidget {
  const _ShareActions({required this.link, required this.onShare});

  final PaymentLink link;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ElevatedButton.icon(
          onPressed: onShare,
          icon: const Icon(Icons.share, size: 18),
          label: const Text('Share'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.goldColor,
            foregroundColor: AppColors.whiteColor,
            padding: const EdgeInsets.symmetric(vertical: 13),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _openWhatsApp(context),
                icon: const Icon(Icons.chat_outlined, size: 18),
                label: const Text('WhatsApp'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.inkColor,
                  side: BorderSide(
                      color: AppColors.inkColor.withOpacity(0.4)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _openEmail(context),
                icon: const Icon(Icons.email_outlined, size: 18),
                label: const Text('Email'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.inkColor,
                  side: BorderSide(
                      color: AppColors.inkColor.withOpacity(0.4)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _openWhatsApp(BuildContext context) async {
    final uri = Uri.parse(
        'https://wa.me/?text=${Uri.encodeComponent(link.payUrl)}');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open WhatsApp')),
        );
      }
    }
  }

  Future<void> _openEmail(BuildContext context) async {
    final uri = Uri.parse(
        'mailto:?subject=${Uri.encodeComponent(link.label)}&body=${Uri.encodeComponent(link.payUrl)}');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open email')),
        );
      }
    }
  }
}
