import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../constants/app_colors.dart';

/// "Product Video" block shown on the product page under the description.
///
/// [video] is the `product_video` object returned by vendor-api.php:
/// `{url, type, provider (youtube|vimeo|file), video_id, embed_url,
/// thumbnail, is_short}`.
///
/// To keep the page light, only a poster with a play button is shown at first;
/// the embedded player (WebView) is created when the shopper taps play.
class ProductVideoPlayer extends StatefulWidget {
  final Map<String, dynamic> video;

  const ProductVideoPlayer({super.key, required this.video});

  @override
  State<ProductVideoPlayer> createState() => _ProductVideoPlayerState();
}

class _ProductVideoPlayerState extends State<ProductVideoPlayer> {
  WebViewController? _controller;
  bool _playing = false;
  bool _loaded = false;
  bool _failed = false;

  String get _url => widget.video['url']?.toString() ?? '';
  String get _provider => widget.video['provider']?.toString() ?? 'file';
  String get _embedUrl => widget.video['embed_url']?.toString() ?? _url;
  String get _thumb => widget.video['thumbnail']?.toString() ?? '';
  bool get _isShort => widget.video['is_short'] == true;

  /// Shorts are portrait; everything else is landscape.
  double get _aspect => _isShort ? 9 / 16 : 16 / 9;

  static const String _chromeUA =
      'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36';

  String _html() {
    final body = _provider == 'file'
        ? '<video controls autoplay playsinline preload="metadata" '
            'style="width:100%;height:100%;background:#000;object-fit:contain">'
            '<source src="${_escape(_url)}" type="video/mp4"></video>'
        : '<iframe src="${_escape(_embedUrl)}${_embedUrl.contains('?') ? '&' : '?'}autoplay=1" '
            'allow="autoplay; encrypted-media; picture-in-picture; fullscreen" '
            'allowfullscreen frameborder="0" '
            'style="width:100%;height:100%;border:0"></iframe>';
    return '<!DOCTYPE html><html><head>'
        '<meta name="viewport" content="width=device-width,initial-scale=1">'
        '<style>html,body{margin:0;padding:0;height:100%;background:#000;overflow:hidden}'
        '</style></head><body>$body</body></html>';
  }

  String _escape(String v) => v
      .replaceAll('&', '&amp;')
      .replaceAll('"', '&quot;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  void _play() {
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setUserAgent(_chromeUA)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => _loaded = true);
          },
          onWebResourceError: (error) {
            // Ignore failures of small sub-resources; only the page itself
            // failing means the video cannot be shown.
            if (error.isForMainFrame == false) return;
            if (mounted) {
              setState(() {
                _failed = true;
                _loaded = true;
              });
            }
          },
        ),
      )
      // A real https base URL gives YouTube/Vimeo a valid referrer, which
      // avoids the "playback restricted" (error 153) message.
      ..loadHtmlString(_html(), baseUrl: 'https://zzmore.store/');
    setState(() {
      _controller = controller;
      _playing = true;
      _loaded = false;
      _failed = false;
    });
  }

  Future<void> _openExternally() async {
    final uri = Uri.tryParse(_url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    if (_url.isEmpty) return const SizedBox.shrink();

    final width = MediaQuery.of(context).size.width;
    // Portrait shorts are kept narrower so they do not fill the whole screen.
    final double maxWidth =
        _isShort ? (width * 0.62).clamp(200.0, 320.0).toDouble() : double.infinity;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Product video',
          style: GoogleFonts.fraunces(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppColors.inkColor,
          ),
        ),
        const SizedBox(height: 10),
        Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: _aspect,
                child: _playing ? _buildPlayer() : _buildPoster(),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPoster() {
    return GestureDetector(
      onTap: _play,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(color: AppColors.inkColor),
          if (_thumb.isNotEmpty)
            CachedNetworkImage(
              imageUrl: _thumb,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => const SizedBox.shrink(),
            ),
          Container(color: Colors.black.withOpacity(0.25)),
          Center(
            child: Container(
              width: 60,
              height: 60,
              decoration: const BoxDecoration(
                color: AppColors.goldColor,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.play_arrow_rounded,
                  color: Colors.white, size: 38),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayer() {
    final controller = _controller;
    if (controller == null) return const SizedBox.shrink();
    return Stack(
      fit: StackFit.expand,
      children: [
        WebViewWidget(controller: controller),
        if (!_loaded)
          const ColoredBox(
            color: Colors.black,
            child: Center(
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: AppColors.goldColor,
              ),
            ),
          ),
        if (_failed)
          ColoredBox(
            color: AppColors.inkColor,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Could not play the video here',
                    style: TextStyle(color: Colors.white),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: _openExternally,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.goldColor,
                      side: const BorderSide(color: AppColors.goldColor),
                    ),
                    child: const Text('Open video'),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
