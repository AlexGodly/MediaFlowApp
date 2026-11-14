// External Media IDs in the title editor (website v377): the provider list,
// validation, and how an edit is saved — a changed ID is written to
// `externalIds` and remembered in `v377ManualExternalIds` (null = cleared on
// purpose) so imports and recovery keep the person's choice.

import '../util/js.dart';
import 'external_id_providers.g.dart';

export 'external_id_providers.g.dart';

/// `v377IdValid`.
bool externalIdValid(String key, String value) {
  if (value.isEmpty) return true;
  if (value.length > (key == 'royalroad_rss' ? 512 : 120)) return false;
  if (key == 'royalroad_rss') {
    final u = Uri.tryParse(value);
    return u != null && u.scheme == 'https' && u.host.length > 3;
  }
  bool re(String p, {bool ci = false}) => RegExp(p, caseSensitive: !ci).hasMatch(value);
  final compact = value.replaceAll(RegExp(r'[-\s]'), '');
  if (key == 'doi' || key == 'crossref') return re(r'^10\.\d{4,9}/\S{1,100}$', ci: true);
  if (key == 'wikidata') return re(r'^Q[1-9]\d*$', ci: true);
  if (key == 'mangadex') return re(r'^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$', ci: true);
  if (key == 'isbn10') return RegExp(r'^\d{9}[\dXx]$').hasMatch(compact);
  if (key == 'isbn13' || key == 'ean') return RegExp(r'^\d{13}$').hasMatch(compact);
  if (const ['mal', 'anilist', 'tmdb', 'kitsu', 'simkl'].contains(key)) return re(r'^[1-9]\d*$');
  if (key == 'imdb') return re(r'^tt\d{7,12}$', ci: true);
  if (key == 'isbn') return re(r'^(?:[\dXx-]{10,20})$');
  return re(r'^[\w.:-]+$');
}

/// The rows the editor shows: every known provider plus any other saved key.
List<(String, String, String)> externalIdRows(Map<String, dynamic>? ids) {
  final known = {for (final p in kExternalIdProviders) p.$1};
  return [
    ...kExternalIdProviders,
    for (final k in (ids ?? const {}).keys)
      if (!known.contains(k) && RegExp(r'^[a-z][a-z0-9_]{0,32}$', caseSensitive: false).hasMatch(k)) (k, k.toUpperCase(), 'External identifier'),
  ];
}

/// The v377 part of `App.saveLibraryModal`. [inputs] maps each shown key to
/// its text. Returns an error for an invalid ID (nothing is saved then).
String? applyExternalIdEdits(Map<String, dynamic> item, Map<String, dynamic> before, Map<String, String> inputs, int now) {
  final oldIds = Map<String, dynamic>.of(asMap(before['externalIds']) ?? const {});
  final manual = Map<String, dynamic>.of(asMap(before['v377ManualExternalIds']) ?? const {});
  final next = Map<String, dynamic>.of(oldIds);
  for (final e in inputs.entries) {
    final value = e.value.trim();
    if (!externalIdValid(e.key, value)) return 'Invalid ${e.key.toUpperCase()} ID. Please correct it before saving.';
    if (jsStr(oldIds[e.key]).trim() != value) {
      if (value.isNotEmpty) {
        next[e.key] = value;
      } else {
        next.remove(e.key);
      }
      manual[e.key] = value.isEmpty ? null : value;
    }
  }
  item['externalIds'] = next;
  if (manual.containsKey('mal')) {
    item.remove('malId');
    item.remove('mal_id');
  }
  if (manual.isNotEmpty) item['v377ManualExternalIds'] = manual;
  final m = jsNum(item['modifiedAt']).toInt();
  item['modifiedAt'] = m > now ? m : now;
  return null;
}
