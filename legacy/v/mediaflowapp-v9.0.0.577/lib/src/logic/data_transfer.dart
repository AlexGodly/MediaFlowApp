// Data & Cloud transfers, in the website's formats so files move freely between
// the website and the app:
//   Full Data Backup   (v148 + v171/v201 schema + v507 "every account field")
//   Settings Preset    (v196)
//   Collections export (v281 + v402/v470 tombstones)
// The Personal Order export lives in collections_logic.dart (v142).

import 'dart:convert';

import '../config.dart' show kAppVersionLabel;
import '../util/js.dart';
import 'collections_logic.dart' show normalizeCollection;
import 'default_settings.g.dart';

/// The website version the app matches (the last part of the app's version,
/// e.g. 575 in 8.1.1.575), stamped on exports like the website stamps its own.
/// It was a fixed 565, so files from the app looked older than they were.
final int kWebsiteRelease = int.tryParse(kAppVersionLabel.split('.').last) ?? 575;
const kBackupSchemaVersion = 29; // V201_BACKUP_SCHEMA_VERSION
const kBackupFormat = 'MediaFlow_Full_Backup';
const kPresetFormat = 'MediaFlow_Settings_Preset';

/// Never copied into a backup (MF507_TRANSIENT_STATE_FIELDS).
const _transient = {'savedAt', 'cloudSyncVersion'};

/// Backup wrapper fields that are not account data.
const _backupMeta = {
  'backupFormat', 'backupSchemaVersion', 'backupVersion', 'mediaFlowVersion', 'exportedAt', 'portableExtras',
  'backupManifest', 'progression', 'progressionBreakdown', 'savedAt', 'cloudSyncVersion', 'exportedBy',
};

Object? _clone(Object? v) => v == null ? null : jsonDecode(jsonEncode(v));

String _stamp(DateTime d) {
  String z(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${z(d.month)}-${z(d.day)}_${z(d.hour)}-${z(d.minute)}-${z(d.second)}';
}

String backupFileName(DateTime d) => 'MediaFlow_Backup_${_stamp(d)}.json';
String presetFileName(DateTime d) => 'MediaFlow_Settings_${_stamp(d)}.json';
String collectionsFileName(DateTime d) => 'MediaFlow_Collections_${d.toIso8601String().substring(0, 10)}.json';

/// The automatic-backup file name (`backupFilename`, multiple-file mode).
String autoBackupFileName(DateTime d) {
  String z(int n) => n.toString().padLeft(2, '0');
  return 'mediaflow-backup-${d.year}-${z(d.month)}-${z(d.day)}-${z(d.hour)}${z(d.minute)}${z(d.second)}.json';
}

// ---- Full Data Backup ------------------------------------------------------------------

/// `v148BuildFullBackup` as the website builds it today: every account field,
/// the full-backup header and manifest. [appVersion] says who exported it.
Map<String, dynamic> buildFullBackup(Map<String, dynamic> state, DateTime now, {String appVersion = ''}) {
  final out = <String, dynamic>{};
  final fields = <String>[];
  for (final e in state.entries) {
    if (_transient.contains(e.key) || e.value == null) continue;
    out[e.key] = _clone(e.value);
    fields.add(e.key);
  }
  List<dynamic> list(String k) => asList(out[k]);
  final ledger = asMap(out['xpLedger']);
  final order = asMap(out['orderPlan']);
  out.addAll({
    'backupFormat': kBackupFormat,
    'backupSchemaVersion': kBackupSchemaVersion,
    'backupVersion': kWebsiteRelease,
    'mediaFlowVersion': kWebsiteRelease,
    'exportedAt': now.toUtc().toIso8601String(),
    if (appVersion.isNotEmpty) 'exportedBy': 'MediaFlow app $appVersion',
    'backupManifest': {
      'schemaVersion': kBackupSchemaVersion,
      'completeAccountState': true,
      'counts': {
        'categories': list('categories').length,
        'libraryTitles': list('library').length,
        'historyLogs': list('sessions').length,
        'libraryHistory': list('activityLog').length,
        'completionTimeline': list('completionTimeline').length,
        'personalOrderTitles': asList(order?['titleIds']).length,
        'ratingQueue': 0,
        'xpRatingRewards': (asMap(ledger?['ratings']) ?? const {}).length,
      },
      'v507': {
        'release': kWebsiteRelease,
        'accountFields': fields,
        'libraryTitles': list('library').length,
        'consumptionHistory': list('sessions').length,
        'libraryHistory': list('activityLog').length,
        'collections': list('collections').length,
        'personalOrder': asList(order?['titleIds']).length,
        'xpLedgerEvents': (asMap(ledger?['v348EventMeta']) ?? const {}).length,
        'fullCloudSnapshotParity': true,
        'schemaCompatible': true,
      },
      'note': 'Complete MediaFlow backup made by the MediaFlow app. Authentication credentials are not included.',
    },
  });
  return out;
}

/// `v148ValidateBackup` + the v402 shape checks. Null when it is valid.
String? validateBackup(Object? data) {
  final d = asMap(data);
  if (d == null || data is List) return 'The selected file is not a MediaFlow backup object.';
  final hasCore = d['categories'] is List && d['library'] is List && d['sessions'] is List && asMap(d['settings']) != null;
  if (!hasCore) {
    return jsStr(d['backupFormat']) == kBackupFormat
        ? 'This MediaFlow full backup is incomplete or corrupted.'
        : 'This JSON does not contain the required MediaFlow categories, Library, History and Settings data.';
  }
  final bad = <String>[];
  for (final k in const ['categories', 'library', 'sessions', 'activityLog', 'completionTimeline', 'collections', 'collectionTombstones']) {
    if (d[k] != null && d[k] is! List) bad.add(k);
  }
  for (final k in const ['settings', 'xpLedger', 'orderPlan', 'oldSystem', 'portableExtras']) {
    if (d[k] != null && asMap(d[k]) == null) bad.add(k);
  }
  if (bad.isNotEmpty) return 'The backup contains invalid account data in: ${bad.join(', ')}.';
  return null;
}

/// What a backup holds, for the confirm dialog.
({int titles, int logs, int collections, String version}) backupSummary(Map<String, dynamic> d) => (
      titles: asList(d['library']).length,
      logs: asList(d['sessions']).length,
      collections: asList(d['collections']).length,
      version: jsStr(d['mediaFlowVersion'] ?? d['backupVersion']),
    );

/// Restores a validated backup into [copy] (the website's full replace: every
/// account field in the file replaces the account's; fields the file does not
/// have are kept). Profile name / picture are replaced exactly, like v148.
void applyFullBackup(Map<String, dynamic> copy, Map<String, dynamic> data) {
  for (final e in data.entries) {
    if (_backupMeta.contains(e.key)) continue;
    copy[e.key] = _clone(e.value);
  }
  if (data.containsKey('profilePicture')) copy['profilePicture'] = jsStr(data['profilePicture']).trim();
  if (data.containsKey('profileName')) copy['profileName'] = jsStr(data['profileName']).trim();
}

// ---- Settings Preset -------------------------------------------------------------------

/// `v196BuildSettingsPreset` (configuration only).
Map<String, dynamic> buildSettingsPreset(Map<String, dynamic> state, DateTime now) {
  final settings = _clone(asMap(state['settings']) ?? defaultSettings()) as Map<String, dynamic>;
  return {
    'presetFormat': kPresetFormat,
    'presetSchemaVersion': 1,
    'mediaFlowVersion': kWebsiteRelease,
    'exportedAt': now.toUtc().toIso8601String(),
    'settings': settings,
    'categories': _clone(asList(state['categories'])),
    'categoryOrder': [
      for (final x in asList(state['categoryOrder']).isNotEmpty ? asList(state['categoryOrder']) : [for (final c in asList(state['categories'])) asMap(c)?['id']])
        if (x != null) jsStr(x),
    ],
    'presetManifest': {
      'settingsOnly': true,
      'canonicalSettingsObject': 'S.settings',
      'includes': {'allSettingsFields': true, 'categoryConfiguration': true, 'categoryOrder': true},
      'excludes': {'library': true, 'consumptionHistory': true, 'libraryHistory': true, 'xpLedgers': true, 'profile': true},
      'v507': {'release': kWebsiteRelease, 'configurationOnly': true, 'settingsKeys': settings.length, 'libraryDataExcluded': true},
      'note': 'Settings Presets contain configuration only. They do not contain Library titles, History, XP/progression, profile data or authentication credentials.',
    },
  };
}

/// `v196ValidateSettingsPreset`. Null when valid.
String? validateSettingsPreset(Object? data) {
  final d = asMap(data);
  if (d == null || data is List) return 'This file is not a MediaFlow Settings Preset.';
  if (jsStr(d['presetFormat']) != kPresetFormat) return 'This JSON is not a MediaFlow Settings Preset.';
  if (asMap(d['settings']) == null) return 'This Settings Preset does not contain a valid settings object.';
  if ((jsNumOrNull(d['presetSchemaVersion']) ?? 0.0) < 1) return 'This Settings Preset uses an unsupported schema.';
  return null;
}

Map<String, dynamic> defaultSettings() => (jsonDecode(kDefaultSettingsJson) as Map).cast<String, dynamic>();

/// `v196NormalizeImportedSettings` + `v196MergePresetCategories`.
void applySettingsPreset(Map<String, dynamic> copy, Map<String, dynamic> data) {
  final def = defaultSettings();
  final incoming = _clone(asMap(data['settings'])) as Map<String, dynamic>;
  Map<String, dynamic> merge(Object? a, Object? b) => {...?asMap(a), ...?asMap(b)};
  final next = {...def, ...incoming};
  next['backup'] = merge(def['backup'], incoming['backup']);
  final lev = merge(def['leveling'], incoming['leveling']);
  lev['unitXP'] = merge(asMap(def['leveling'])?['unitXP'], asMap(incoming['leveling'])?['unitXP']);
  lev['rotationMultiplier'] = merge(asMap(def['leveling'])?['rotationMultiplier'], asMap(incoming['leveling'])?['rotationMultiplier']);
  next['leveling'] = lev;

  final presetCats = asList(data['categories']);
  if (presetCats.isNotEmpty) {
    final current = {for (final c in asList(copy['categories'])) if (asMap(c) != null) jsStr(asMap(c)!['id']): asMap(c)!};
    final merged = <Map<String, dynamic>>[];
    for (final raw in presetCats) {
      final m = asMap(raw);
      final id = jsStr(m?['id']).trim();
      if (m == null || id.isEmpty) continue;
      merged.add({...?current.remove(id), ...(_clone(m) as Map<String, dynamic>), 'id': id});
    }
    merged.addAll(current.values); // never delete categories the preset did not know
    if (merged.isNotEmpty) copy['categories'] = merged;
  }
  final order = [for (final x in asList(data['categoryOrder'] ?? asMap(data['settings'])?['categoryOrder'])) jsStr(x)];
  final cats = [for (final c in asList(copy['categories'])) jsStr(asMap(c)?['id'])];
  if (order.isNotEmpty) {
    final byId = {for (final c in asList(copy['categories'])) jsStr(asMap(c)?['id']): c};
    final sorted = [for (final id in order) if (byId[id] != null) byId.remove(id)!, ...byId.values];
    copy['categories'] = sorted;
  }
  final finalOrder = [for (final c in asList(copy['categories'])) jsStr(asMap(c)?['id'])];
  copy['categoryOrder'] = finalOrder.isEmpty ? cats : finalOrder;
  next['categoryOrder'] = [...copy['categoryOrder'] as List];
  copy['settings'] = next;
}

// ---- Collections -----------------------------------------------------------------------

/// `v281CollectionsExportPayload` with the v402/v470/v507 additions.
Map<String, dynamic> buildCollectionsExport(Map<String, dynamic> state, DateTime now) => {
      'mediaflowCollectionsExportVersion': 2,
      'appVersion': kWebsiteRelease,
      'mediaFlowVersion': kWebsiteRelease,
      'exportedAt': now.toUtc().toIso8601String(),
      'collections': _clone(asList(state['collections'])),
      'collectionSettings': _clone(asMap(asMap(state['settings'])?['v274Collections']) ?? const {}),
      'collectionTombstones': _clone([
        for (final t in asList(state['collectionTombstones']))
          if (asMap(t) != null && jsStr(asMap(t)!['id']).isNotEmpty) t,
      ]),
    };

/// Parses a Collections file: the rows, the deletion markers and whether it has settings.
({List<Map<String, dynamic>> rows, List<Map<String, dynamic>> deleted, bool hasSettings, String? error}) readCollectionsFile(
    Object? parsed) {
  final rows = parsed is List ? parsed : (asMap(parsed)?['collections'] is List ? asList(asMap(parsed)!['collections']) : null);
  if (rows == null) return (rows: const [], deleted: const [], hasSettings: false, error: 'That file does not contain MediaFlow Collections.');
  final deleted = [
    for (final x in asList(asMap(parsed)?['collectionTombstones']))
      if (asMap(x) != null && jsStr(asMap(x)!['id']).isNotEmpty && (jsNumOrNull(asMap(x)!['deletedAt']) ?? 0.0) > 0) asMap(x)!,
  ];
  final maps = [for (final r in rows) if (asMap(r) != null) asMap(r)!];
  if (maps.isEmpty && deleted.isEmpty) return (rows: const [], deleted: const [], hasSettings: false, error: 'No valid collections were found.');
  return (rows: maps, deleted: deleted, hasSettings: asMap(asMap(parsed)?['collectionSettings']) != null, error: null);
}

/// `v281ImportCollections`' merge: newer copies win, deletion markers remove only
/// older collections. Returns (imported, removed, skipped).
({int imported, int removed, int skipped}) importCollections(
    Map<String, dynamic> copy, Object? parsed, int now, String Function() uid) {
  final file = readCollectionsFile(parsed);
  if (file.error != null) return (imported: 0, removed: 0, skipped: 0);
  final seen = <String>{};
  final incoming = <Map<String, dynamic>>[];
  for (final r in file.rows) {
    final c = normalizeCollection(Map<String, dynamic>.of(r), now, uid);
    if (seen.add(jsStr(c['id']))) incoming.add(c);
  }
  final byId = <String, Map<String, dynamic>>{
    for (final c in asList(copy['collections'])) if (asMap(c) != null) jsStr(asMap(c)!['id']): asMap(c)!,
  };
  final tomb = <String, Map<String, dynamic>>{
    for (final t in asList(copy['collectionTombstones']))
      if (asMap(t) != null && jsStr(asMap(t)!['id']).isNotEmpty)
        jsStr(asMap(t)!['id']): {'id': jsStr(asMap(t)!['id']), 'deletedAt': jsOut(jsNumOrNull(asMap(t)!['deletedAt']) ?? 0.0)},
  };
  final sourceById = {for (final r in file.rows) if (jsStr(r['id']).isNotEmpty) jsStr(r['id']): r};
  var accepted = 0;
  for (final c in incoming) {
    final id = jsStr(c['id']);
    final prev = byId[id];
    final originalTime = jsNumOrNull(sourceById[id]?['updatedAt']) ?? 0.0;
    final deletion = jsNumOrNull(tomb[id]?['deletedAt']) ?? 0.0;
    if (originalTime > 0 && deletion >= originalTime) continue;
    if (prev != null && (originalTime <= 0 || originalTime < (jsNumOrNull(prev['updatedAt']) ?? 0.0))) continue;
    c['updatedAt'] = originalTime > 0 ? jsOut(originalTime) : now;
    byId[id] = c;
    accepted++;
    if (jsNum(c['updatedAt']) > deletion) tomb.remove(id);
  }
  var removed = 0;
  for (final entry in file.deleted) {
    final id = jsStr(entry['id']);
    final time = jsNumOrNull(entry['deletedAt']) ?? 0.0;
    if (time <= (jsNumOrNull(tomb[id]?['deletedAt']) ?? 0.0)) continue;
    final existing = byId[id];
    if (existing != null && time <= (jsNumOrNull(existing['updatedAt']) ?? 0.0)) continue;
    tomb[id] = {'id': id, 'deletedAt': jsOut(time)};
    if (existing != null) {
      byId.remove(id);
      removed++;
    }
  }
  copy['collections'] = byId.values.toList();
  copy['collectionTombstones'] = tomb.values.toList();
  if (file.hasSettings) {
    final settings = Map<String, dynamic>.of(asMap(copy['settings']) ?? const {});
    settings['v274Collections'] = {
      ...?asMap(settings['v274Collections']),
      ...(_clone(asMap(asMap(parsed)!['collectionSettings'])) as Map<String, dynamic>),
    };
    copy['settings'] = settings;
  }
  return (imported: accepted, removed: removed, skipped: incoming.length - accepted);
}
