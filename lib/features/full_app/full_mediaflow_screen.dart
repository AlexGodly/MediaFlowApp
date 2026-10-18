import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview_forge/flutter_inappwebview_forge.dart';

/// The production MediaFlow website is the sole authority for business rules,
/// account changes, History/XP, Logging, and Supabase synchronization.
///
/// The full app uses that *actual* source, not a parallel native write path.
class MediaFlowWebConfig {
  const MediaFlowWebConfig._();

  static const String productionUrl =
      'https://alexgodly.github.io/MediaFlow/';

  static const String configuredUrl = String.fromEnvironment(
    'MEDIAFLOW_SITE_URL',
    defaultValue: productionUrl,
  );

  /// Fail closed on a mistyped or replaced production origin. Never send
  /// MediaFlow credentials to an untrusted custom URL from a build flag.
  static Uri get startUri {
    final candidate = Uri.tryParse(configuredUrl);
    if (candidate == null ||
        candidate.scheme != 'https' ||
        candidate.host != 'alexgodly.github.io' ||
        !candidate.path.startsWith('/MediaFlow/') ||
        candidate.userInfo.isNotEmpty ||
        candidate.hasQuery ||
        candidate.hasFragment ||
        candidate.port != 443) {
      return Uri.parse(productionUrl);
    }
    return candidate;
  }
}

/// Full-fidelity, responsive interactive prototype and first usable app.
/// The website owns its own login, local storage, PWA and cloud state.
/// Native reconstruction is retained as an explicitly separate preview.
class FullMediaFlowScreen extends StatefulWidget {
  const FullMediaFlowScreen({super.key});

  @override
  State<FullMediaFlowScreen> createState() => _FullMediaFlowScreenState();
}

class _FullMediaFlowScreenState extends State<FullMediaFlowScreen> {
  InAppWebViewController? _controller;
  bool _loading = true;
  bool _mainFrameFailed = false;
  double _progress = 0;

  Future<void> _handleBack(bool didPop, Object? result) async {
    if (didPop) return;
    final controller = _controller;
    if (controller != null && await controller.canGoBack()) {
      await controller.goBack();
      return;
    }
    await SystemNavigator.pop();
  }

  Future<void> _retry() async {
    setState(() {
      _mainFrameFailed = false;
      _loading = true;
      _progress = 0;
    });
    final controller = _controller;
    if (controller == null) return;
    await controller.loadUrl(
      urlRequest: URLRequest(url: WebUri.uri(MediaFlowWebConfig.startUri)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: _handleBack,
      child: Scaffold(
        backgroundColor: const Color(0xFF0E111A),
        body: Stack(
          fit: StackFit.expand,
          children: [
            // No artificial navigation rail or substitute Logging UI:
            // this is the exact current MediaFlow product at every width.
            InAppWebView(
              initialUrlRequest: URLRequest(
                url: WebUri.uri(MediaFlowWebConfig.startUri),
              ),
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                domStorageEnabled: true,
                supportZoom: false,
                allowsInlineMediaPlayback: true,
                mediaPlaybackRequiresUserGesture: false,
              ),
              onWebViewCreated: (controller) {
                _controller = controller;
              },
              onLoadStart: (controller, url) {
                if (!mounted) return;
                setState(() {
                  _mainFrameFailed = false;
                  _loading = true;
                });
              },
              onProgressChanged: (controller, progress) {
                if (!mounted) return;
                setState(() {
                  _progress = progress / 100;
                });
              },
              onLoadStop: (controller, url) {
                if (!mounted) return;
                setState(() {
                  _loading = false;
                  _progress = 1;
                });
              },
              onReceivedError: (controller, request, error) {
                if (!mounted || request.isForMainFrame != true) return;
                setState(() {
                  _mainFrameFailed = true;
                  _loading = false;
                });
              },
            ),
            if (_loading && !_mainFrameFailed)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: LinearProgressIndicator(
                  minHeight: 2,
                  value: _progress > 0 ? _progress : null,
                ),
              ),
            if (_mainFrameFailed)
              ColoredBox(
                color: const Color(0xFF0E111A),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.wifi_off_rounded,
                            size: 52,
                            color: Color(0xFFB1C2D8),
                          ),
                          const SizedBox(height: 18),
                          const Text(
                            'MediaFlow is unavailable',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Could not open the full MediaFlow website. '
                            'Check your connection and retry. No local '
                            'drafts or cloud data have been cleared.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Color(0xFFB1C2D8)),
                          ),
                          const SizedBox(height: 22),
                          FilledButton.icon(
                            onPressed: _retry,
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('Retry MediaFlow'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
