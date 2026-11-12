// The website's theme system, ported:
//  * every built-in theme (MediaFlow, Platform, Full Style) with its colours
//    (theme_catalog.dart, generated from the website);
//  * the Custom theme (`settings.customTheme`);
//  * the global Light / Dark appearance layer (v106 / v132: on by default; it
//    keeps the theme's accent and uses standard light or dark surfaces);
//  * the Dynamic Cover Theme (v145 / v146 / v162 / v163 / v173): the whole
//    palette worked out from a cover, from the recommended title, On This Day,
//    chosen Library titles or image links, rotating on a timer.
// All of these are account settings, so the app and the website match.

import 'dart:math' as math;
import 'dart:ui' show Color;

import '../util/js.dart';

/// A built-in theme as the website defines it (CSS variables).
class ThemeDef {
  const ThemeDef(this.id, this.label, this.group,
      {required this.bg,
      required this.panel,
      required this.raised,
      required this.border,
      required this.text,
      required this.dim,
      required this.mute,
      required this.flow,
      this.glow});
  final String id, label, group;
  final int bg, panel, raised, border, text, dim, mute, flow;

  /// The first colour of the theme's page gradient, if it has one.
  final int? glow;

  Palette get palette => Palette(
        bg: Color(bg),
        panel: Color(panel),
        raised: Color(raised),
        border: Color(border),
        text: Color(text),
        dim: Color(dim),
        mute: Color(mute),
        flow: Color(flow),
      );
}

/// The colours the app draws with (the website's --bg … --flow).
class Palette {
  const Palette({
    required this.bg,
    required this.panel,
    required this.raised,
    required this.border,
    required this.text,
    required this.dim,
    required this.mute,
    required this.flow,
  });
  final Color bg, panel, raised, border, text, dim, mute, flow;

  bool get isLight => luminance(bg) > .42;

  Palette withFlow(Color f) => Palette(bg: bg, panel: panel, raised: raised, border: border, text: text, dim: dim, mute: mute, flow: f);

  String get key => [bg, panel, raised, border, text, dim, mute, flow].map(hexOf).join();

  @override
  bool operator ==(Object other) => other is Palette && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

int _c(double v) => (v * 255).round().clamp(0, 255);
int rgbInt(Color c) => (_c(c.r) << 16) | (_c(c.g) << 8) | _c(c.b);
String hexOf(Color c) => '#${rgbInt(c).toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// `#rrggbb` / `#rgb` / `rgb(…)` → colour, or null.
Color? parseCssColor(Object? value) {
  final v = jsStr(value).trim();
  var m = RegExp(r'^#([0-9a-f]{6})$', caseSensitive: false).firstMatch(v);
  if (m != null) return Color(0xFF000000 | int.parse(m[1]!, radix: 16));
  m = RegExp(r'^#([0-9a-f]{3})$', caseSensitive: false).firstMatch(v);
  if (m != null) return Color(0xFF000000 | int.parse(m[1]!.split('').map((c) => '$c$c').join(), radix: 16));
  m = RegExp(r'rgba?\(\s*(\d+(?:\.\d+)?)\s*,\s*(\d+(?:\.\d+)?)\s*,\s*(\d+(?:\.\d+)?)', caseSensitive: false).firstMatch(v);
  if (m != null) return Color.fromARGB(255, double.parse(m[1]!).round(), double.parse(m[2]!).round(), double.parse(m[3]!).round());
  return null;
}

/// `v145Luminance`.
double luminance(Color c) {
  double ch(double v) => v <= .03928 ? v / 12.92 : math.pow((v + .055) / 1.055, 2.4).toDouble();
  return .2126 * ch(c.r) + .7152 * ch(c.g) + .0722 * ch(c.b);
}

/// `color-mix(in srgb, a w%, b)`.
Color mixColors(Color a, Color b, double w) =>
    Color.fromARGB(255, _c(a.r * w + b.r * (1 - w)), _c(a.g * w + b.g * (1 - w)), _c(a.b * w + b.b * (1 - w)));

// ---- HSL (v145RgbToHsl / v145HslToRgb) ------------------------------------------------

({double h, double s, double l}) rgbToHsl(double r, double g, double b) {
  r /= 255;
  g /= 255;
  b /= 255;
  final mx = math.max(r, math.max(g, b)), mn = math.min(r, math.min(g, b));
  final l = (mx + mn) / 2, d = mx - mn;
  var h = 0.0, s = 0.0;
  if (d != 0) {
    s = l > .5 ? d / (2 - mx - mn) : d / (mx + mn);
    if (mx == r) {
      h = ((g - b) / d + (g < b ? 6 : 0)) / 6;
    } else if (mx == g) {
      h = ((b - r) / d + 2) / 6;
    } else {
      h = ((r - g) / d + 4) / 6;
    }
  }
  return (h: h * 360, s: s * 100, l: l * 100);
}

Color hslColor(double h, double s, double l) {
  h = ((h % 360) + 360) % 360 / 360;
  s = s.clamp(0, 100) / 100;
  l = l.clamp(0, 100) / 100;
  if (s == 0) {
    final v = (l * 255).round();
    return Color.fromARGB(255, v, v, v);
  }
  double hue(double p, double q, double t) {
    if (t < 0) t += 1;
    if (t > 1) t -= 1;
    if (t < 1 / 6) return p + (q - p) * 6 * t;
    if (t < 1 / 2) return q;
    if (t < 2 / 3) return p + (q - p) * (2 / 3 - t) * 6;
    return p;
  }

  final q = l < .5 ? l * (1 + s) : l + s - l * s, p = 2 * l - q;
  return Color.fromARGB(255, (hue(p, q, h + 1 / 3) * 255).round(), (hue(p, q, h) * 255).round(), (hue(p, q, h - 1 / 3) * 255).round());
}

/// `v145TuneAccent`: a usable accent from a cover's colour.
Color tuneAccent(double r, double g, double b, {required bool darkBackground}) {
  final hsl = rgbToHsl(r, g, b);
  final s = (hsl.s * 1.12).clamp(48, 88).toDouble();
  final l = darkBackground ? hsl.l.clamp(50, 65).toDouble() : hsl.l.clamp(34, 50).toDouble();
  return hslColor(hsl.h, s, l);
}

/// `v145ExtractCoverAccent`'s pixel pass on a 48×64 RGBA sample: the
/// strongest saturated colour bucket, else the average.
Color? accentFromPixels(List<int> rgba, {required bool darkBackground}) {
  final buckets = <String, List<double>>{}; // score, r, g, b, n
  double fr = 0, fg = 0, fb = 0;
  var fn = 0;
  for (var i = 0; i + 3 < rgba.length; i += 16) {
    final r = rgba[i], g = rgba[i + 1], b = rgba[i + 2], a = rgba[i + 3];
    if (a < 180) continue;
    final mx = math.max(r, math.max(g, b)), mn = math.min(r, math.min(g, b));
    final chroma = mx - mn, lum = (.2126 * r + .7152 * g + .0722 * b) / 255;
    if (lum > .08 && lum < .94) {
      fr += r;
      fg += g;
      fb += b;
      fn++;
    }
    final sat = mx == 0 ? 0.0 : chroma / mx;
    if (sat < .18 || lum < .10 || lum > .90) continue;
    String q(int v) => '${(v / 32).round() * 32}';
    final key = '${q(r)},${q(g)},${q(b)}';
    final weight = (.35 + sat) * (1 - (lum - .52).abs() * .65);
    final row = buckets[key] ??= [0, 0, 0, 0, 0];
    row[0] += weight;
    row[1] += r;
    row[2] += g;
    row[3] += b;
    row[4]++;
  }
  List<double>? best;
  for (final row in buckets.values) {
    if (best == null || row[0] > best[0]) best = row;
  }
  if (best != null && best[4] > 0) return tuneAccent(best[1] / best[4], best[2] / best[4], best[3] / best[4], darkBackground: darkBackground);
  if (fn > 0) return tuneAccent(fr / fn, fg / fn, fb / fn, darkBackground: darkBackground);
  return null;
}

/// `v146PaletteFromAccent`: a complete palette from one accent colour.
Palette paletteFromAccent(Color accent, {required bool light}) {
  final hsl = rgbToHsl(accent.r * 255, accent.g * 255, accent.b * 255);
  final h = hsl.h;
  final chroma = (hsl.s * 1.10 == 0 ? 58.0 : hsl.s * 1.10).clamp(42, 82).toDouble();
  if (light) {
    return Palette(
      bg: hslColor(h, math.min(28, chroma * .30), 97),
      panel: hslColor(h, math.min(22, chroma * .24), 99),
      raised: hslColor(h, math.min(34, chroma * .38), 93),
      border: hslColor(h, math.min(32, chroma * .34), 78),
      text: hslColor(h, math.min(28, chroma * .26), 14),
      dim: hslColor(h, math.min(30, chroma * .30), 34),
      mute: hslColor(h, math.min(26, chroma * .25), 50),
      flow: hslColor(h, math.max(58, chroma), 42),
    );
  }
  return Palette(
    bg: hslColor(h, math.min(34, chroma * .36), 7),
    panel: hslColor(h, math.min(38, chroma * .40), 11),
    raised: hslColor(h, math.min(42, chroma * .45), 16),
    border: hslColor(h, math.min(36, chroma * .36), 29),
    text: hslColor(h, math.min(18, chroma * .16), 95),
    dim: hslColor(h, math.min(22, chroma * .20), 73),
    mute: hslColor(h, math.min(24, chroma * .22), 53),
    flow: hslColor(h, math.max(58, chroma), 58),
  );
}

// ---- v159 / v162 cover themes (the whole palette from the cover) ---------------------

/// `v159ExtractCoverTheme`: up to four distinct cover colours and the cover's
/// own light/dark nature, from a 54×72 RGBA sample.
({List<Color> colors, bool light})? coverThemeFromPixels(List<int> rgba) {
  final buckets = <String, List<double>>{}; // r, g, b, n, score
  double lumSum = 0;
  var lumN = 0;
  for (var i = 0; i + 3 < rgba.length; i += 4) {
    final a = rgba[i + 3];
    if (a < 180) continue;
    final r = rgba[i], g = rgba[i + 1], b = rgba[i + 2];
    final mx = math.max(r, math.max(g, b)), mn = math.min(r, math.min(g, b));
    final sat = mx == 0 ? 0.0 : (mx - mn) / mx;
    final lum = .2126 * r + .7152 * g + .0722 * b;
    lumSum += lum;
    lumN++;
    int q(int v) => (v / 24).round() * 24;
    final key = '${q(r)},${q(g)},${q(b)}';
    final vivid = .35 + sat * 1.9;
    final middle = .55 + (1 - (lum / 255 - .50).abs()) * .45;
    final row = buckets[key] ??= [0, 0, 0, 0, 0];
    row[0] += r;
    row[1] += g;
    row[2] += b;
    row[3]++;
    row[4] += vivid * middle;
  }
  final ranked = buckets.values
      .where((x) => x[3] >= 2)
      .map((x) => (r: x[0] / x[3], g: x[1] / x[3], b: x[2] / x[3], score: x[4] * math.pow(x[3], .62)))
      .toList()
    ..sort((a, b) => b.score.compareTo(a.score));
  final picked = <({double r, double g, double b, num score})>[];
  for (final row in ranked) {
    final far = picked.every((x) => math.sqrt(math.pow(x.r - row.r, 2) + math.pow(x.g - row.g, 2) + math.pow(x.b - row.b, 2)) >= 76);
    if (far) {
      picked.add(row);
      if (picked.length >= 4) break;
    }
  }
  if (picked.isEmpty) return null;
  final colors = picked.map((x) => Color.fromARGB(255, x.r.round(), x.g.round(), x.b.round())).toList();
  while (colors.length < 3) {
    final seed = colors.first;
    final hsl = rgbToHsl(seed.r * 255, seed.g * 255, seed.b * 255);
    final shift = colors.length == 1 ? 52 : 188;
    colors.add(hslColor(hsl.h + shift, math.max(44, hsl.s * .86), 54));
  }
  final average = lumN > 0 ? lumSum / lumN / 255 : .35;
  return (colors: colors.take(4).toList(), light: average > .58);
}

/// `v159TuneThemeColor`.
Color _tuneThemeColor(Color c, {required bool light, required bool accent}) {
  final hsl = rgbToHsl(c.r * 255, c.g * 255, c.b * 255);
  if (accent) {
    final s = (hsl.s == 0 ? 66.0 : hsl.s * 1.14).clamp(58, 92).toDouble();
    final l = light ? hsl.l.clamp(34, 52).toDouble() : hsl.l.clamp(52, 68).toDouble();
    return hslColor(hsl.h, s, l);
  }
  final s = (hsl.s == 0 ? 48.0 : hsl.s).clamp(32, 78).toDouble();
  final l = light ? hsl.l.clamp(38, 62).toDouble() : hsl.l.clamp(42, 68).toDouble();
  return hslColor(hsl.h, s, l);
}

Color _hex(int v) => Color(0xFF000000 | v);

/// `v159CoverPalette`, softened like `v162SoftPalette` for the calmer cover
/// collections ([soft]: every mode except Dynamic).
Palette paletteFromCover(List<Color> colors, {required bool light, bool soft = false}) {
  final raw1 = colors.first, raw2 = colors.length > 1 ? colors[1] : raw1, raw3 = colors.length > 2 ? colors[2] : raw2;
  var primary = _tuneThemeColor(raw1, light: light, accent: true);
  final secondary = _tuneThemeColor(raw2, light: light, accent: false);
  Color bg, panel, raised, border;
  Color text, dim, mute;
  if (light) {
    bg = mixColors(raw1, _hex(0xF5F7FB), .10);
    panel = mixColors(raw2, _hex(0xFFFFFF), .07);
    raised = mixColors(raw3, _hex(0xEDF1F7), .12);
    border = mixColors(secondary, _hex(0xCBD3DF), .18);
    text = _hex(0x121722);
    dim = _hex(0x394354);
    mute = _hex(0x667184);
    if (soft) {
      bg = mixColors(bg, _hex(0xF4F6FA), .38);
      panel = mixColors(panel, _hex(0xFFFFFF), .32);
      raised = mixColors(raised, _hex(0xEDF1F6), .38);
      border = mixColors(border, _hex(0xCCD3DE), .48);
      primary = mixColors(primary, _hex(0x53606F), .76);
      text = _hex(0x151A22);
      dim = _hex(0x3E4857);
      mute = _hex(0x687486);
    }
  } else {
    bg = mixColors(raw1, _hex(0x060912), .21);
    panel = mixColors(raw2, _hex(0x0B1019), .17);
    raised = mixColors(raw3, _hex(0x141B29), .20);
    border = mixColors(secondary, _hex(0x2C3545), .22);
    text = _hex(0xF4F7FB);
    dim = _hex(0xC1CAD7);
    mute = _hex(0x8793A5);
    if (soft) {
      bg = mixColors(bg, _hex(0x080C13), .42);
      panel = mixColors(panel, _hex(0x0D121B), .40);
      raised = mixColors(raised, _hex(0x151C28), .44);
      border = mixColors(border, _hex(0x303947), .48);
      primary = mixColors(primary, _hex(0xAAB5C4), .78);
      text = _hex(0xF5F7FA);
      dim = _hex(0xC5CDD8);
      mute = _hex(0x8D98A8);
    }
  }
  return Palette(bg: bg, panel: panel, raised: raised, border: border, text: text, dim: dim, mute: mute, flow: primary);
}

// ---- the global Light / Dark appearance layer (v106 / v132) ---------------------------

const _lightSurfaces = Palette(
  bg: Color(0xFFF5F7FB),
  panel: Color(0xFFFFFFFF),
  raised: Color(0xFFF0F3F8),
  border: Color(0xFFCBD3DF),
  text: Color(0xFF171A21),
  dim: Color(0xFF4D586A),
  mute: Color(0xFF737F92),
  flow: Color(0xFFE8A94A),
);
const _darkSurfaces = Palette(
  bg: Color(0xFF0B0E14),
  panel: Color(0xFF141922),
  raised: Color(0xFF1C2330),
  border: Color(0xFF343D4D),
  text: Color(0xFFF2F4F8),
  dim: Color(0xFFB6BECB),
  mute: Color(0xFF7F8999),
  flow: Color(0xFFE8A94A),
);

/// The theme's own light/dark nature (`v106DetectThemeAppearance`).
String nativeAppearance(Palette p) => p.isLight ? 'light' : 'dark';

/// `settings.customTheme`, with the website's defaults.
Palette customPalette(Map<String, dynamic>? c) {
  Color pick(String k, int def) => parseCssColor(c?[k]) ?? Color(def);
  final text = pick('text', 0xFFF4F6FB), muted = pick('muted', 0xFF8D98AD);
  return Palette(
    bg: pick('bg', 0xFF0E111A),
    panel: pick('panel', 0xFF161B2A),
    raised: pick('raised', 0xFF1C2334),
    border: pick('border', 0xFF2B3448),
    text: text,
    dim: muted,
    mute: mixColors(muted, pick('bg', 0xFF0E111A), .7),
    flow: pick('accent', 0xFFE8A94A),
  );
}

/// The theme the settings choose (before any Dynamic Cover Theme).
Palette staticPalette(Map<String, dynamic>? settings, List<ThemeDef> themes) {
  final id = jsStr(settings?['theme']).isEmpty ? 'dark' : jsStr(settings?['theme']);
  final base = id == 'custom'
      ? customPalette(asMap(settings?['customTheme']))
      : (themes.where((t) => t.id == id).firstOrNull ?? themes.first).palette;
  // Website v564: off unless switched on (DEFAULT_SETTINGS.globalAppearanceEnabled = false).
  if (settings?['globalAppearanceEnabled'] != true) return base;
  final layer = appearanceMode(settings, base) == 'light' ? _lightSurfaces : _darkSurfaces;
  return layer.withFlow(base.flow);
}

/// `v106AppearanceMode`: the saved Light/Dark choice, else the theme's own.
String appearanceMode(Map<String, dynamic>? settings, Palette base) {
  final mode = jsStr(settings?['appearanceMode']).toLowerCase();
  return mode == 'light' || mode == 'dark' ? mode : nativeAppearance(base);
}

/// Dynamic Cover Theme collections (`v162ThemeCollection`).
const kCoverThemeModes = [
  ('dynamic', 'Dynamic (recommended title, then On This Day)'),
  ('recommended-only', 'Recommended title only'),
  ('onthisday-only', 'On This Day only'),
  ('source-picker', 'Choose sources'),
  ('library', 'Library covers'),
  ('image', 'Image links'),
];

int clampInterval(Object? v) => (jsNum(v).round() == 0 ? 30 : jsNum(v).round()).clamp(5, 3600).toInt();
