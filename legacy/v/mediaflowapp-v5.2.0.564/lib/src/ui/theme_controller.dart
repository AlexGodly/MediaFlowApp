// Applies the account's theme settings (the website's theme system) to the
// app: the chosen theme or Custom theme, the global Light / Dark appearance,
// and the Dynamic Cover Theme with its sources and rotation.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../data/account_controller.dart';
import '../data/app_prefs.dart';
import '../data/cover_cache.dart';
import '../logic/extras.dart' show onThisDay;
import '../util/js.dart';
import 'theme.dart';
import 'theme_catalog.dart';
import 'theme_palette.dart';

/// A cover the Dynamic Cover Theme can use.
class CoverSource {
  CoverSource(this.key, this.label, this.url);
  final String key, label, url;
}

class ThemeController extends ChangeNotifier {
  ThemeController._();
  static final ThemeController instance = ThemeController._();

  Palette palette = kWebsiteThemes.first.palette;

  /// What the Dynamic Cover Theme is showing (Settings shows it).
  String status = 'Selected theme';

  /// The cover shown as a soft blurred backdrop while the Dynamic Cover Theme
  /// uses it (website v160 `--v160-cover-image`); null otherwise.
  File? coverVisual;
  final Map<String, File> _files = {};

  AccountController? _account;
  String _inputs = '';
  Timer? _rotation;
  int _rotationIndex = 0;
  int _seq = 0;
  final Map<String, Future<Color?>> _accents = {};

  /// The palette last used on this device, so the app opens in it.
  void restore() {
    final saved = AppPrefs.instance.get<String>('themePalette', '');
    final parts = saved.split(',');
    if (parts.length == 8) {
      final c = [for (final p in parts) parseCssColor(p)];
      if (c.every((x) => x != null)) {
        _apply(Palette(bg: c[0]!, panel: c[1]!, raised: c[2]!, border: c[3]!, text: c[4]!, dim: c[5]!, mute: c[6]!, flow: c[7]!), notify: false);
        return;
      }
    }
    _apply(staticPalette(const {}, kWebsiteThemes), notify: false);
  }

  void attach(AccountController account) {
    if (identical(_account, account)) return;
    _account?.removeListener(_changed);
    _account = account;
    _inputs = '';
    account.addListener(_changed);
    _changed();
  }

  void detach(AccountController account) {
    if (!identical(_account, account)) return;
    account.removeListener(_changed);
    _account = null;
    _rotation?.cancel();
  }

  Map<String, dynamic>? get _settings => asMap(_account?.view?.state['settings']);

  /// Recomputes only when a theme setting (or a cover source) changed.
  void _changed() {
    final state = _account?.view?.state;
    if (state == null) return;
    final s = asMap(state['settings']) ?? const {};
    _migrateNativeTheme(s);
    final task = asMap(state['currentTask']);
    final inputs = [
      jsStr(s['theme']),
      jsStringifyLite(s['customTheme']),
      '${s['globalAppearanceEnabled']}',
      jsStr(s['appearanceMode']),
      '${s['dynamicCoverTheme']}',
      jsStr(s['v162ThemeCollection']),
      jsStringifyLite(s['v162LibraryTheme']),
      jsStringifyLite(s['v162ImageTheme']),
      jsStringifyLite(s['v173RecommendedTheme']),
      jsStringifyLite(s['v173OnThisDayTheme']),
      jsStringifyLite(s['v173SourcePickerTheme']),
      '${s['v163DynamicThemeIntervalSec']}',
      jsStr(task?['libraryId']),
      DateTime.now().toIso8601String().substring(0, 10),
      '${asList(state['library']).length}',
    ].join('|');
    if (inputs == _inputs) return;
    _inputs = inputs;
    _rotationIndex = 0;
    unawaited(_refresh());
  }

  bool _migrating = false;

  /// Website v564: themes show their own colours by default. Each account is
  /// moved over once (Global appearance off), and an unset Light / Dark is
  /// saved as the theme's own, as the website does when it first resolves it.
  void _migrateNativeTheme(Map<String, dynamic> s) {
    final account = _account;
    if (account == null || _migrating || s['v564NativeThemeDefault'] == true) return;
    _migrating = true;
    final native = nativeAppearance(staticPalette({...s, 'globalAppearanceEnabled': false}, kWebsiteThemes));
    final unset = jsStr(s['appearanceMode']) != 'light' && jsStr(s['appearanceMode']) != 'dark';
    unawaited(() async {
      try {
        await account.setSetting(['globalAppearanceEnabled'], false);
        if (unset) await account.setSetting(['appearanceMode'], native);
        await account.setSetting(['v564NativeThemeDefault'], true);
      } finally {
        _migrating = false;
      }
    }());
  }

  Future<void> _refresh() async {
    final seq = ++_seq;
    _rotation?.cancel();
    final settings = _settings ?? const <String, dynamic>{};
    final base = staticPalette(settings, kWebsiteThemes);
    if (settings['dynamicCoverTheme'] != true) {
      status = 'Selected theme';
      _setVisual(null);
      _apply(base);
      return;
    }
    final mode = jsStr(settings['v162ThemeCollection']).isEmpty ? 'dynamic' : jsStr(settings['v162ThemeCollection']);
    final sources = coverSources(mode);
    if (sources.isEmpty) {
      status = 'Selected theme fallback (no cover available)';
      _setVisual(null);
      _apply(base);
      return;
    }
    final light = appearanceMode(settings, base) == 'light';
    // Try the sources in turn from the rotation position until one gives a colour.
    for (var n = 0; n < sources.length; n++) {
      final source = sources[(_rotationIndex + n) % sources.length];
      final accent = await _accent(source.url, darkBackground: !light);
      if (seq != _seq) return;
      if (accent == null) continue;
      _rotationIndex = (_rotationIndex + n) % sources.length;
      status = source.label;
      _setVisual(_files[source.url]);
      _apply(paletteFromAccent(accent, light: light));
      break;
    }
    if (seq != _seq) return;
    if (status.startsWith('Selected')) {
      _setVisual(null);
      _apply(base);
    }
    if (sources.length > 1) {
      final secs = clampInterval(_intervalFor(settings, mode));
      _rotation = Timer(Duration(seconds: secs), () {
        _rotationIndex = (_rotationIndex + 1) % sources.length;
        unawaited(_refresh());
      });
    }
  }

  Object? _intervalFor(Map<String, dynamic> s, String mode) => switch (mode) {
        'library' => asMap(s['v162LibraryTheme'])?['intervalSec'],
        'image' => asMap(s['v162ImageTheme'])?['intervalSec'],
        'recommended-only' => asMap(s['v173RecommendedTheme'])?['intervalSec'],
        'onthisday-only' => asMap(s['v173OnThisDayTheme'])?['intervalSec'],
        'source-picker' => asMap(s['v173SourcePickerTheme'])?['intervalSec'],
        _ => s['v163DynamicThemeIntervalSec'],
      };

  /// `v160RecommendedCoverSource`: the recommended exact title's cover.
  CoverSource? recommendedSource() {
    final state = _account?.view?.state;
    final id = jsStr(asMap(state?['currentTask'])?['libraryId']);
    if (state == null || id.isEmpty) return null;
    final item = asList(state['library']).map(asMap).firstWhere((i) => jsStr(i?['id']) == id, orElse: () => null);
    final url = _safeUrl(item?['coverUrl']);
    if (item == null || url.isEmpty) return null;
    return CoverSource('recommended', 'Recommended: ${cleanTitle(item['title'])}', url);
  }

  /// `v159OnThisDayThemeSources`: covers of titles from today in earlier years.
  List<CoverSource> onThisDaySources() {
    final state = _account?.view?.state;
    if (state == null) return const [];
    final out = <CoverSource>[];
    final seen = <String>{};
    for (final group in onThisDay(state, DateTime.now())) {
      for (final e in group.rows) {
        final url = _safeUrl(e.item?['coverUrl']);
        if (url.isEmpty || !seen.add(url)) continue;
        final id = jsStr(e.item?['id']);
        out.add(CoverSource(id.isNotEmpty ? 'otd:$id' : 'otd-url:$url', 'On This Day: ${e.title}', url));
      }
    }
    return out;
  }

  /// The covers a Dynamic Cover Theme collection uses, in order.
  List<CoverSource> coverSources(String mode) {
    final s = _settings ?? const <String, dynamic>{};
    final state = _account?.view?.state;
    switch (mode) {
      case 'library':
        final ids = asList(asMap(s['v162LibraryTheme'])?['titleIds']).map(jsStr).toList();
        final byId = {for (final i in asList(state?['library']).map(asMap).whereType<Map<String, dynamic>>()) jsStr(i['id']): i};
        return [
          for (final id in ids)
            if (byId[id] != null && _safeUrl(byId[id]!['coverUrl']).isNotEmpty)
              CoverSource('lib:$id', 'Library Cover: ${cleanTitle(byId[id]!['title'])}', _safeUrl(byId[id]!['coverUrl'])),
        ];
      case 'image':
        final urls = asList(asMap(s['v162ImageTheme'])?['urls']).map(_safeUrl).where((u) => u.isNotEmpty).toSet();
        var n = 0;
        return [for (final u in urls) CoverSource('img:$u', 'Image ${++n}', u)];
      case 'recommended-only':
        final r = recommendedSource();
        return r == null ? const [] : [r];
      case 'onthisday-only':
        return onThisDaySources();
      case 'source-picker':
        final keys = asList(asMap(s['v173SourcePickerTheme'])?['selectedKeys']).map(jsStr).toSet();
        final all = availablePickerSources();
        final picked = all.where((x) => (keys.isEmpty ? {'recommended'} : keys).contains(x.key)).toList();
        return picked;
      default:
        final r = recommendedSource();
        return [if (r != null) r, ...onThisDaySources()];
    }
  }

  /// `v173PickerAvailableSources`.
  List<CoverSource> availablePickerSources() {
    final r = recommendedSource();
    return [if (r != null) r, ...onThisDaySources()];
  }

  static String _safeUrl(Object? v) {
    var s = jsStr(v).trim();
    if (s.startsWith('//')) s = 'https:$s';
    return RegExp(r'^https?://', caseSensitive: false).hasMatch(s) ? s : '';
  }

  /// `v145ExtractCoverAccent` on the cover's pixels (cached per cover).
  Future<Color?> _accent(String url, {required bool darkBackground}) =>
      _accents.putIfAbsent('$darkBackground|$url', () async {
        try {
          final file = await CoverCache.instance.file(url);
          if (file == null) return null;
          _files[url] = file;
          final bytes = await file.readAsBytes();
          final codec = await ui.instantiateImageCodec(Uint8List.fromList(bytes), targetWidth: 48, targetHeight: 64);
          final frame = await codec.getNextFrame();
          final data = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
          frame.image.dispose();
          if (data == null) return null;
          return accentFromPixels(data.buffer.asUint8List(), darkBackground: darkBackground);
        } catch (_) {
          return null;
        }
      });

  void _setVisual(File? f) {
    if (f?.path == coverVisual?.path) return;
    coverVisual = f;
    notifyListeners();
  }

  void _apply(Palette p, {bool notify = true}) {
    if (p == palette && notify) return;
    palette = p;
    MF.apply(p);
    unawaited(AppPrefs.instance.set('themePalette', [p.bg, p.panel, p.raised, p.border, p.text, p.dim, p.mute, p.flow].map(hexOf).join(',')));
    if (notify) notifyListeners();
  }
}

/// A short stable text for change detection.
String jsStringifyLite(Object? v) => v == null ? '' : v.toString();

/// Redraws the whole app when the theme changes (the colours are read while
/// building, so every widget is rebuilt — like the website re-rendering).
class ThemeRebuilder extends StatefulWidget {
  const ThemeRebuilder({super.key, required this.child});
  final Widget child;

  @override
  State<ThemeRebuilder> createState() => _ThemeRebuilderState();
}

class _ThemeRebuilderState extends State<ThemeRebuilder> {
  String _key = ThemeController.instance.palette.key;

  @override
  void initState() {
    super.initState();
    ThemeController.instance.addListener(_changed);
  }

  @override
  void dispose() {
    ThemeController.instance.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    final key = ThemeController.instance.palette.key;
    if (key == _key || !mounted) return;
    _key = key;
    void mark(Element e) {
      e.markNeedsBuild();
      e.visitChildren(mark);
    }

    (context as Element).visitChildren(mark);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Website v160: while the Dynamic Cover Theme uses a cover, the cover itself
/// sits behind the app as a faint, blurred backdrop (13 % opacity, 46 px blur,
/// under a fade to the background colour). Used behind the main sections.
class CoverBackdrop extends StatelessWidget {
  const CoverBackdrop({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeController.instance,
      builder: (context, _) {
        final file = ThemeController.instance.coverVisual;
        if (file == null) return child;
        final bg = MF.background;
        return Stack(fit: StackFit.expand, children: [
          ColoredBox(color: bg),
          IgnorePointer(
            child: Opacity(
              opacity: .13,
              child: Transform.scale(
                scale: 1.09,
                child: ImageFiltered(
                  imageFilter: ui.ImageFilter.blur(sigmaX: 46, sigmaY: 46, tileMode: TileMode.decal),
                  child: Image.file(file, fit: BoxFit.cover, alignment: const Alignment(0, -0.52), gaplessPlayback: true,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                ),
              ),
            ),
          ),
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [bg.withValues(alpha: .74), bg.withValues(alpha: .92)],
                ),
              ),
            ),
          ),
          Theme(
            data: Theme.of(context).copyWith(scaffoldBackgroundColor: Colors.transparent),
            child: child,
          ),
        ]);
      },
    );
  }
}
