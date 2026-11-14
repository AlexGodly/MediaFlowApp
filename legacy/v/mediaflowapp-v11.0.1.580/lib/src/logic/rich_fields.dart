// The title editor's "rich metadata" fields (website v178 on v176): year,
// format, duration, release date, season, age rating, community score,
// source, demographic, studios, producers, genres, themes and synopsis.
// A field the person changes is marked in `richMetadataManual` so imports and
// recovery never overwrite it. test/rich_fields_golden_test.dart.

import 'dart:convert';
import 'dart:math' as math;

import '../util/js.dart';

const kRichFields = [
  'year', 'mediaFormat', 'durationMinutes', 'releaseDate', 'seasonLabel', 'ageRating', 'communityScore',
  'mediaSource', 'demographic', 'studios', 'producers', 'genres', 'themes', 'synopsis',
];

const kRichListFields = ['studios', 'producers', 'genres', 'themes'];
const kRichNumberFields = ['year', 'durationMinutes', 'communityScore'];

const kRichLabels = {
  'year': 'Year',
  'mediaFormat': 'Format',
  'durationMinutes': 'Duration (minutes)',
  'releaseDate': 'Release date',
  'seasonLabel': 'Season',
  'ageRating': 'Age rating',
  'communityScore': 'Community score (0–10)',
  'mediaSource': 'Source material',
  'demographic': 'Demographic',
  'studios': 'Studios',
  'producers': 'Producers',
  'genres': 'Genres',
  'themes': 'Themes',
  'synopsis': 'Synopsis',
};

/// `v176SafeText`.
String safeText(Object? value, [int max = 5000]) {
  if (value == null) return '';
  var s = '$value'
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'<[^>]+>'), ' ')
      .replaceAll(RegExp('&nbsp;', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (s.length > max) s = s.substring(0, max).trim();
  return s;
}

/// `v176DateValue` (the ISO day inside the text, or a parseable date).
String dateValue(Object? value) {
  var v = value;
  if (v is Map) v = v['from'] ?? v['start'] ?? v['date'] ?? v['value'] ?? '';
  final raw = jsStr(v).trim();
  if (raw.isEmpty) return '';
  final iso = RegExp(r'(\d{4}-\d{2}-\d{2})').firstMatch(raw);
  if (iso != null) return iso[1]!;
  final d = DateTime.tryParse(raw);
  return d == null ? '' : d.toUtc().toIso8601String().substring(0, 10);
}

/// `v178CsvList`.
List<String> csvList(Object? value) {
  final out = <String>[];
  for (final x in jsStr(value).split(',')) {
    final v = safeText(x, 120);
    if (v.isNotEmpty && !out.contains(v)) out.add(v);
  }
  return out.length > 40 ? out.sublist(0, 40) : out;
}

/// `v178ManualMap`.
Map<String, dynamic> richManualMap(Map<String, dynamic>? item) {
  final src = item?['richMetadataManual'];
  if (src is! Map) return {};
  return {for (final k in kRichFields) if (src[k] == true) k: true};
}

/// The text the editor shows for a field.
String richFieldText(Map<String, dynamic> item, String key) {
  final v = item[key];
  if (kRichListFields.contains(key)) return asList(v).where(jsTruthy).map(jsStr).join(', ');
  if (kRichNumberFields.contains(key)) {
    final n = jsNumOrNull(v);
    return v == null || n == null || n <= 0 ? '' : (n == n.roundToDouble() ? '${n.toInt()}' : '$n');
  }
  return jsStr(v);
}

/// `v178CaptureEditorValues`: [inputs] holds the text of each field.
Map<String, dynamic> captureRich(Map<String, String> inputs) {
  Object? numberOrNull(String key, [num? max]) {
    final raw = (inputs[key] ?? '').trim();
    if (raw.isEmpty) return null;
    var value = jsNumOrNull(raw);
    if (value == null || !value.isFinite) return null;
    if (max != null) value = math.min(max.toDouble(), value);
    return jsOut(math.max(0.0, value));
  }

  return {
    'year': numberOrNull('year', 9999),
    'mediaFormat': safeText(inputs['mediaFormat'], 80),
    'durationMinutes': numberOrNull('durationMinutes'),
    'releaseDate': dateValue(inputs['releaseDate']),
    'seasonLabel': safeText(inputs['seasonLabel'], 80),
    'ageRating': safeText(inputs['ageRating'], 80),
    'communityScore': numberOrNull('communityScore', 10),
    'mediaSource': safeText(inputs['mediaSource'], 120),
    'demographic': safeText(inputs['demographic'], 120),
    'studios': csvList(inputs['studios']),
    'producers': csvList(inputs['producers']),
    'genres': csvList(inputs['genres']),
    'themes': csvList(inputs['themes']),
    'synopsis': safeText(inputs['synopsis'], 6000),
  };
}

String _comparable(String key, Object? value) {
  if (kRichListFields.contains(key)) return jsonEncode(value is List ? value : const []);
  if (kRichNumberFields.contains(key)) {
    final n = jsNumOrNull(value);
    return value != null && n != null && n.isFinite && n > 0 ? fmtNum(n) : '';
  }
  return value == null ? '' : jsStr(value);
}

String fmtNum(num n) => n == n.roundToDouble() && n.abs() < 1e21 ? '${n.toInt()}' : '$n';

/// `v178ApplyManualEditorValues`: writes the captured fields onto [item]
/// (in place) and marks the changed ones manual. Returns whether any changed.
bool applyRichEditorValues(Map<String, dynamic> item, Map<String, dynamic> before, Map<String, dynamic> captured, int now) {
  final manual = richManualMap(before);
  var changed = false;
  for (final key in kRichFields) {
    final oldValue = before[key], newValue = captured[key];
    if (_comparable(key, oldValue) != _comparable(key, newValue)) {
      manual[key] = true;
      changed = true;
    }
    if (kRichListFields.contains(key)) {
      item[key] = newValue is List ? newValue : <String>[];
      continue;
    }
    if (kRichNumberFields.contains(key)) {
      final n = jsNumOrNull(newValue);
      item[key] = newValue != null && n != null && n.isFinite && n > 0 ? jsOut(n) : null;
      continue;
    }
    item[key] = jsTruthy(newValue) ? jsStr(newValue) : '';
  }
  item['richMetadataManual'] = manual;
  if (changed) item['modifiedAt'] = now;
  return changed;
}
