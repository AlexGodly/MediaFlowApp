// Helpers that reproduce the JavaScript semantics the MediaFlow website relies on,
// so values computed here match what the website computes for the same data.

import 'dart:math' as math;

/// `Number(v) || 0` — invalid, missing, NaN and infinite values become 0.
double jsNum(Object? v) {
  final n = jsNumOrNull(v);
  return n ?? 0;
}

/// `Number(v)` when finite, otherwise null. Like JS, null/'' count as 0
/// and booleans as 0/1.
double? jsNumOrNull(Object? v) {
  double? out;
  if (v == null) {
    out = 0;
  } else if (v is num) {
    out = v.toDouble();
  } else if (v is bool) {
    out = v ? 1 : 0;
  } else if (v is String) {
    final t = v.trim();
    out = t.isEmpty ? 0 : double.tryParse(t);
  }
  if (out == null || out.isNaN || out.isInfinite) return null;
  return out;
}

/// Like `Number.isFinite(Number(v))` for a value read from a JSON key that may
/// be absent: an absent key behaves like JS `undefined` (not finite).
double? jsNumFromKey(Map<String, dynamic>? map, String key) {
  if (map == null || !map.containsKey(key)) return null;
  return jsNumOrNull(map[key]);
}

/// `Math.round` (halves round up, toward +infinity).
double jsRound(double v) => (v + 0.5).floorToDouble();

/// JSON output: whole numbers are written as ints, like JavaScript does.
num jsOut(double v) {
  if (v.isFinite && v == v.truncateToDouble() && v.abs() < 9007199254740992) {
    return v.toInt();
  }
  return v;
}

/// `Math.log2`.
double jsLog2(double v) => math.log(v) / math.ln2;

String jsStr(Object? v) => v == null ? '' : v.toString();

bool jsTruthy(Object? v) {
  if (v == null || v == false) return false;
  if (v is num) return v != 0 && !v.isNaN;
  if (v is String) return v.isNotEmpty;
  return true;
}

/// MediaFlow's `cleanTitle`: strips CDATA wrappers and trims.
String cleanTitle(Object? value) {
  var s = value == null ? '' : value.toString();
  s = s.replaceAllMapped(RegExp(r'<!\[CDATA\[([\s\S]*?)\]\]>', caseSensitive: false), (m) => m[1] ?? '');
  s = s.replaceFirst(RegExp(r'^\s*<!\[CDATA\[\s*', caseSensitive: false), '');
  s = s.replaceFirst(RegExp(r'\s*\]\]>\s*$'), '');
  return s.trim();
}

/// `new Date(ms).toISOString().slice(0,10)` — the website's "today" is a UTC date.
String isoDateUtc(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

final RegExp _isoDay = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

bool isIsoDay(Object? s) => s is String && _isoDay.hasMatch(s);

/// `v135ParseDateInput`: local-time noon of a YYYY-MM-DD day, or null.
int? localNoonMs(String raw) {
  final m = _isoDay.firstMatch(raw.trim());
  if (m == null) return null;
  final y = int.parse(m[1]!), mo = int.parse(m[2]!), d = int.parse(m[3]!);
  final dt = DateTime(y, mo, d, 12);
  if (dt.year != y || dt.month != mo || dt.day != d) return null;
  return dt.millisecondsSinceEpoch;
}

/// `v149ShiftDateKey`: shift a UTC day key by whole days.
String shiftDayKey(String key, int delta) {
  final m = _isoDay.firstMatch(key);
  if (m == null) return '';
  final d = DateTime.utc(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!), 12)
      .add(Duration(days: delta));
  return isoDateUtc(d.millisecondsSinceEpoch);
}

/// The website's `uid()`: `id_<base36 time>_<6 random base36 chars>`.
String mediaFlowUid([int? nowMs, math.Random? random]) {
  final r = random ?? _random;
  const chars = '0123456789abcdefghijklmnopqrstuvwxyz';
  final suffix = List.generate(6, (_) => chars[r.nextInt(36)]).join();
  return 'id_${(nowMs ?? DateTime.now().millisecondsSinceEpoch).toRadixString(36)}_$suffix';
}

final math.Random _random = math.Random.secure();

Map<String, dynamic>? asMap(Object? v) => v is Map<String, dynamic> ? v : (v is Map ? v.cast<String, dynamic>() : null);

List<dynamic> asList(Object? v) => v is List ? v : const [];
