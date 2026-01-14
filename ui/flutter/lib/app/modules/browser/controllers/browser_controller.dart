import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../api/model/create_task.dart';
import '../../../../api/model/request.dart';
import '../../../routes/app_pages.dart';

class BrowserController extends GetxController {
  final urlText = TextEditingController();
  final progress = 0.0.obs;
  final canBack = false.obs;
  final canForward = false.obs;
  final pageTitle = ''.obs;

  // Tabs (ADM-like)
  final tabsCount = 0.obs;
  final activeTabIndex = 0.obs;

  // UI state (ADM-like options)
  final desktopMode = false.obs;
  final blockImages = false.obs;
  final enableJs = true.obs;
  // Allow opening plain HTTP links (insecure). Does NOT bypass invalid HTTPS certificates.
  final allowHttp = true.obs;

  final List<_BrowserTab> _tabs = <_BrowserTab>[];

  final _cookies = WebViewCookieManager();

  static const String homeUrl = 'https://www.google.com/';

  static const Set<String> _downloadExts = {
    'zip',
    'apk',
    'pdf',
    'mp4',
    'mkv',
    'mp3',
    'm4a',
    'wav',
    'flac',
    'jpg',
    'jpeg',
    'png',
    'gif',
    'webp',
    '7z',
    'rar',
    'tar',
    'gz',
    'tgz',
    'iso',
    'exe',
    'msi',
    'dmg',
    'm3u8',
    'torrent',
  };

  @override
  void onInit() {
    super.onInit();

    final initial = (Get.arguments is String && (Get.arguments as String).isNotEmpty)
        ? (Get.arguments as String)
        : homeUrl;

    urlText.text = initial;
    _openNewTab(initialUrl: initial, switchToNew: true);
  }

  @override
  void onClose() {
    urlText.dispose();
    super.onClose();
  }

  Future<void> _updateNavState() async {
    try {
      final c = currentWeb;
      canBack.value = await c.canGoBack();
      canForward.value = await c.canGoForward();
    } catch (_) {
      // ignore
    }
  }

  WebViewController get currentWeb => _tabs[activeTabIndex.value].web;

  int get currentTabId => _tabs[activeTabIndex.value].id;

  void goToInput() {
    final input = urlText.text.trim();
    if (input.isEmpty) return;
    final url = _normalizeUrl(input);
    currentWeb.loadRequest(Uri.parse(url));
  }

  void goHome() {
    urlText.text = homeUrl;
    currentWeb.loadRequest(Uri.parse(homeUrl));
  }

  Future<void> toggleDesktopMode() async {
    desktopMode.toggle();
    for (final t in _tabs) {
      await t.web.setUserAgent(_userAgent());
    }
    await reload();
  }

  Future<void> toggleJavaScript() async {
    enableJs.toggle();
    for (final t in _tabs) {
      await t.web.setJavaScriptMode(enableJs.value ? JavaScriptMode.unrestricted : JavaScriptMode.disabled);
    }
    await reload();
  }

  Future<void> toggleImages() async {
    blockImages.toggle();
    // Inject CSS to hide images (best-effort, like lightweight adblock)
    await _applyContentRules();
    await reload();
  }

  void toggleAllowHttp() {
    allowHttp.toggle();
  }

  /// Open current address as HTTP (insecure). Useful for sites that don't support TLS.
  void openAsHttp() {
    final u = urlText.text.trim();
    if (u.isEmpty) return;
    try {
      final uri = Uri.parse(u);
      if (uri.hasScheme && uri.scheme == 'http') return;
      final host = uri.host.isNotEmpty ? uri.host : uri.path;
      if (host.isEmpty) return;
      final httpUrl = 'http://$host${uri.hasAuthority ? uri.path : ''}${uri.hasQuery ? '?${uri.query}' : ''}';
      urlText.text = httpUrl;
      currentWeb.loadRequest(Uri.parse(httpUrl));
    } catch (_) {
      // If parse fails, best-effort prefix.
      final httpUrl = u.startsWith('http') ? u : 'http://$u';
      urlText.text = httpUrl;
      currentWeb.loadRequest(Uri.parse(httpUrl));
    }
  }

  Future<void> clearBrowserData() async {
    try {
      for (final t in _tabs) {
        await t.web.clearCache();
      }
      await _cookies.clearCookies();
    } catch (_) {
      // ignore
    }
  }

  Future<void> copyCurrentUrl() async {
    final u = urlText.text.trim();
    if (u.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: u));
    Get.snackbar('Copied', 'Link copied to clipboard');
  }

  String _userAgent() {
    // A03s = Android Chrome UA. Desktop mode swaps to desktop UA.
    if (desktopMode.value) {
      return 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';
    }
    return 'Mozilla/5.0 (Linux; Android 13; SM-A037F) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36';
  }

  Future<void> _applyContentRules() async {
    if (!blockImages.value) return;
    // Hide images via CSS injection
    const js = """
      (function(){
        try {
          var style = document.getElementById('__gopeed_img_block');
          if(!style){
            style = document.createElement('style');
            style.id='__gopeed_img_block';
            style.innerHTML='img,video,source,picture{display:none !important;}';
            document.head.appendChild(style);
          }
        } catch(e) {}
      })();
    """;
    try {
      await currentWeb.runJavaScript(js);
    } catch (_) {
      // ignore
    }
  }

  Future<void> back() async {
    final c = currentWeb;
    if (await c.canGoBack()) {
      await c.goBack();
      await _updateNavState();
    }
  }

  Future<void> forward() async {
    final c = currentWeb;
    if (await c.canGoForward()) {
      await c.goForward();
      await _updateNavState();
    }
  }

  Future<void> reload() async {
    await currentWeb.reload();
  }

  String _normalizeUrl(String input) {
    final s = input.trim();
    if (s.startsWith('http://') || s.startsWith('https://')) return s;
    // If user typed a domain or words, search via Google.
    if (s.contains(' ') || !s.contains('.')) {
      final q = Uri.encodeComponent(s);
      return 'https://www.google.com/search?q=$q';
    }
    // Default to HTTPS for safety. If user needs HTTP they can use the menu "Open as HTTP".
    return 'https://$s';
  }

  bool _looksLikeDownload(String url) {
    try {
      final uri = Uri.parse(url);
      final path = uri.path.toLowerCase();
      final last = path.split('/').last;
      final dot = last.lastIndexOf('.');
      if (dot > 0 && dot < last.length - 1) {
        final ext = last.substring(dot + 1);
        if (_downloadExts.contains(ext)) return true;
      }

      // Common download hints
      final u = url.toLowerCase();
      if (u.contains('download=1') || u.contains('attachment') || u.contains('dl=1')) {
        return true;
      }

      return false;
    } catch (_) {
      return false;
    }
  }

  void _openCreate(String url) {
    final task = CreateTask(req: Request(url: url));
    Get.rootDelegate.toNamed(Routes.CREATE, arguments: task);
  }

  // ---------------- Tabs ----------------
  void openTabSwitcher() {
    // UI handled in view. This is a helper for consistency.
  }

  void newTab() => _openNewTab(initialUrl: homeUrl, switchToNew: true);

  void switchToTab(int index) {
    if (index < 0 || index >= _tabs.length) return;
    activeTabIndex.value = index;
    final tab = _tabs[index];
    urlText.text = tab.url;
    pageTitle.value = tab.title;
    progress.value = tab.progress;
    _updateNavState();
  }

  void closeTab(int index) {
    if (_tabs.length <= 1) return; // keep at least one
    if (index < 0 || index >= _tabs.length) return;
    _tabs.removeAt(index);
    tabsCount.value = _tabs.length;
    if (activeTabIndex.value >= _tabs.length) {
      activeTabIndex.value = _tabs.length - 1;
    }
    switchToTab(activeTabIndex.value);
  }

  void _openNewTab({required String initialUrl, required bool switchToNew}) {
    final id = DateTime.now().microsecondsSinceEpoch;
    final tab = _BrowserTab(id: id, url: initialUrl, title: '');
    tab.web = _buildWebControllerForTab(tab);
    _tabs.add(tab);
    tabsCount.value = _tabs.length;
    if (switchToNew) {
      activeTabIndex.value = _tabs.length - 1;
    }
  }

  WebViewController _buildWebControllerForTab(_BrowserTab tab) {
    final c = WebViewController()
      ..setJavaScriptMode(enableJs.value ? JavaScriptMode.unrestricted : JavaScriptMode.disabled)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) {
            tab.progress = p / 100.0;
            if (tab.id == currentTabId) progress.value = tab.progress;
          },
          onUrlChange: (change) {
            final u = change.url;
            if (u != null) {
              tab.url = u;
              if (tab.id == currentTabId) urlText.text = u;
            }
          },
          onPageFinished: (_) async {
            try {
              final t = await c.getTitle();
              if (t != null) tab.title = t;
              if (tab.id == currentTabId) pageTitle.value = tab.title;
            } catch (_) {}
            if (tab.id == currentTabId) {
              await _updateNavState();
              await _applyContentRules();
            }
          },
          onNavigationRequest: (req) {
            final url = req.url;

            // Hand off non-web schemes to the OS (tel:, mailto:, intent:, market:, etc.)
            try {
              final uri = Uri.parse(url);
              final scheme = uri.scheme.toLowerCase();
              if (scheme.isNotEmpty && scheme != 'http' && scheme != 'https') {
                launchUrl(uri, mode: LaunchMode.externalApplication);
                return NavigationDecision.prevent;
              }
            } catch (_) {}

            if (_looksLikeDownload(url)) {
              _openCreate(url);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..setUserAgent(_userAgent());

    c.loadRequest(Uri.parse(_normalizeUrl(initialUrl)));
    return c;
  }
}

class _BrowserTab {
  _BrowserTab({required this.id, required this.url, required this.title});
  final int id;
  String url;
  String title;
  double progress = 0;
  late WebViewController web;
}
