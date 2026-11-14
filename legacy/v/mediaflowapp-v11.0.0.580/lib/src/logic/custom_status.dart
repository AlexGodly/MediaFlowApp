// Custom Status (PreMiD-style custom Rich Presence) and "Show on Discord".
//
// Saved in the account (app-only setting `mediaflowAppCustomStatus`), so every
// device shows and edits the same thing:
//   {draft: {…status…},
//    active: {…status…, appliedAt} | null,        // Apply Status / Clear
//    profiles: [{id, name, status: {…}, schedule: {…}}],
//    modifiedAt}
// A status:
//   type      playing | listening | watching | competing
//   name      the activity name (replaces "MediaFlow"); empty = MediaFlow
//   display   name | state | details   (what the short status line shows)
//   details, detailsUrl, state, stateUrl
//   largeImage, largeText, largeUrl, smallImage, smallText, smallUrl
//   timeMode  none | absolute | relative
//   start, end            (ms, absolute)
//   relStart, relEnd      (minutes before / after Apply, relative)
//   partyCurrent, partyMax
//   buttons   [{label, url}] (at most 2, https only)
// A schedule: {enabled, kind: daily | once, days: [1..7] (Mon..Sun, empty =
// every day), date: 'YYYY-MM-DD' (once), from: 'HH:mm', to: 'HH:mm'} — the
// window may pass midnight. A manually applied status wins over schedules.
//
// "Show on Discord" (a Library title shown as if you're on it) lives with the
// Discord look (`mediaflowAppDiscord.pinned`): {titleId, until (ms; 0 = until
// stopped), session ('' or the app launch it belongs to), type}.

import '../util/js.dart';

const kCustomStatusKey = 'mediaflowAppCustomStatus';
const kCustomTypes = ['playing', 'listening', 'watching', 'competing'];

/// A fresh empty status (the editor's Reset).
Map<String, dynamic> blankStatus() => {
      'type': 'playing',
      'name': '',
      'display': 'name',
      'details': '',
      'detailsUrl': '',
      'state': '',
      'stateUrl': '',
      'largeImage': '',
      'largeText': '',
      'largeUrl': '',
      'smallImage': '',
      'smallText': '',
      'smallUrl': '',
      'timeMode': 'none',
      'start': 0,
      'end': 0,
      'relStart': 0,
      'relEnd': 0,
      'partyCurrent': 0,
      'partyMax': 0,
      'buttons': <Map<String, dynamic>>[],
    };

/// A status with every field present and valid (unknown fields kept).
Map<String, dynamic> normalizeStatus(Object? raw) {
  final m = asMap(raw) ?? const <String, dynamic>{};
  final out = <String, dynamic>{...blankStatus(), ...m};
  String text(String k, [int max = 128]) {
    final s = jsStr(out[k]).trim();
    return s.length > max ? s.substring(0, max) : s;
  }

  String url(String k) => _httpsUrl(out[k]);

  int number(String k, {int max = 1 << 31}) {
    final n = jsNum(out[k]);
    return n.isFinite && n > 0 ? (n > max ? max : n.floor()) : 0;
  }

  out['type'] = kCustomTypes.contains(out['type']) ? out['type'] : 'playing';
  out['display'] = const ['name', 'state', 'details'].contains(out['display']) ? out['display'] : 'name';
  out['timeMode'] = const ['none', 'absolute', 'relative'].contains(out['timeMode']) ? out['timeMode'] : 'none';
  for (final k in const ['name', 'details', 'state', 'largeText', 'smallText']) {
    out[k] = text(k);
  }
  for (final k in const ['detailsUrl', 'stateUrl', 'largeUrl', 'smallUrl']) {
    out[k] = url(k);
  }
  // Images: an https link (or an asset name of a custom application).
  for (final k in const ['largeImage', 'smallImage']) {
    final s = jsStr(out[k]).trim();
    out[k] = s.length > 512 ? '' : s;
  }
  out['start'] = number('start', max: 1 << 52);
  out['end'] = number('end', max: 1 << 52);
  out['relStart'] = number('relStart', max: 525600);
  out['relEnd'] = number('relEnd', max: 525600);
  out['partyCurrent'] = number('partyCurrent', max: 1000000);
  out['partyMax'] = number('partyMax', max: 1000000);
  out['buttons'] = [
    for (final b in asList(out['buttons']).map(asMap).whereType<Map<String, dynamic>>())
      if (jsStr(b['label']).trim().isNotEmpty && _httpsUrl(b['url']).isNotEmpty)
        {'label': jsStr(b['label']).trim().length > 32 ? jsStr(b['label']).trim().substring(0, 32) : jsStr(b['label']).trim(), 'url': _httpsUrl(b['url'])},
  ].take(2).toList();
  return out;
}

String _httpsUrl(Object? v) {
  final s = jsStr(v).trim();
  final u = Uri.tryParse(s);
  return u != null && u.scheme == 'https' && u.host.isNotEmpty && s.length <= 512 ? s : '';
}

/// Whether a status has anything to show.
bool statusHasContent(Map<String, dynamic> s) =>
    jsStr(s['name']).isNotEmpty || jsStr(s['details']).isNotEmpty || jsStr(s['state']).isNotEmpty || jsStr(s['largeImage']).isNotEmpty;

class CustomStatusStore {
  CustomStatusStore(this.raw);
  final Map<String, dynamic> raw;

  static CustomStatusStore of(Map<String, dynamic>? settings) =>
      CustomStatusStore(asMap(settings?[kCustomStatusKey]) ?? const <String, dynamic>{});

  Map<String, dynamic> get draft => normalizeStatus(raw['draft']);
  Map<String, dynamic>? get active {
    final a = asMap(raw['active']);
    return a == null ? null : {...normalizeStatus(a), 'appliedAt': jsNum(a['appliedAt']).toInt()};
  }

  List<Map<String, dynamic>> get profiles => [
        for (final p in asList(raw['profiles']).map(asMap).whereType<Map<String, dynamic>>())
          {
            ...p,
            'id': jsStr(p['id']),
            'name': jsStr(p['name']).isEmpty ? 'Profile' : jsStr(p['name']),
            'status': normalizeStatus(p['status']),
            'schedule': normalizeSchedule(p['schedule']),
          },
      ];

  /// v6: saved image links for the large / small image ({id, name, url, addedAt}).
  List<Map<String, dynamic>> get images => [
        for (final m in asList(raw['images']).map(asMap).whereType<Map<String, dynamic>>())
          if (_imageUrl(m['url']).isNotEmpty)
            {
              ...m,
              'id': jsStr(m['id']),
              'name': jsStr(m['name']).trim().isEmpty ? 'Image' : jsStr(m['name']).trim(),
              'url': _imageUrl(m['url']),
            },
      ];

  /// The library with [url] added (or renamed if it is already there).
  List<Map<String, dynamic>> withImage(String url, String name, String id, int now) {
    final u = _imageUrl(url);
    final list = images;
    if (u.isEmpty) return list;
    final i = list.indexWhere((m) => m['url'] == u);
    final clean = name.trim().isEmpty ? 'Image' : (name.trim().length > 80 ? name.trim().substring(0, 80) : name.trim());
    if (i >= 0) {
      list[i] = {...list[i], 'name': clean};
    } else {
      list.insert(0, {'id': id, 'name': clean, 'url': u, 'addedAt': now});
    }
    return list.take(200).toList();
  }

  Map<String, dynamic> withChanges(Map<String, dynamic> changes, int now) => {...raw, ...changes, 'modifiedAt': now};
}

/// An image link Discord can show (https only, or a custom application's
/// asset name).
String _imageUrl(Object? v) {
  final s = jsStr(v).trim();
  return s.isEmpty || s.length > 512 || !s.startsWith('https://') ? '' : s;
}

Map<String, dynamic> normalizeSchedule(Object? raw) {
  final m = asMap(raw) ?? const <String, dynamic>{};
  String hm(Object? v, String def) => RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(jsStr(v)) ? jsStr(v) : def;
  return {
    ...m,
    'enabled': m['enabled'] == true,
    'kind': m['kind'] == 'once' ? 'once' : 'daily',
    'days': [for (final d in asList(m['days'])) if (jsNum(d) >= 1 && jsNum(d) <= 7) jsNum(d).toInt()],
    'date': RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(jsStr(m['date'])) ? jsStr(m['date']) : '',
    'from': hm(m['from'], '20:00'),
    'to': hm(m['to'], '22:00'),
  };
}

int _mins(String hm) => int.parse(hm.substring(0, 2)) * 60 + int.parse(hm.substring(3, 5));

/// When a schedule's window that contains [now] started, or null.
DateTime? scheduleWindowStart(Map<String, dynamic> schedule, DateTime now) {
  final s = normalizeSchedule(schedule);
  if (s['enabled'] != true) return null;
  final from = _mins(s['from'] as String), to = _mins(s['to'] as String);
  final wraps = to <= from; // e.g. 22:00 → 02:00
  bool dayOk(DateTime day) {
    if (s['kind'] == 'once') {
      final d = '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
      return d == s['date'];
    }
    final days = (s['days'] as List).cast<int>();
    return days.isEmpty || days.contains(day.weekday);
  }

  final today = DateTime(now.year, now.month, now.day);
  final m = now.hour * 60 + now.minute;
  // Window that started today.
  if (dayOk(today) && m >= from && (wraps || m < to)) return today.add(Duration(minutes: from));
  // Window that started yesterday and runs past midnight.
  final yesterday = today.subtract(const Duration(days: 1));
  if (wraps && dayOk(yesterday) && m < to) return yesterday.add(Duration(minutes: from));
  return null;
}

/// What Custom Status shows now: the applied status, else a scheduled
/// profile's, else null (the automatic status).
({Map<String, dynamic> status, int appliedAt, String source})? currentCustomStatus(Map<String, dynamic>? settings, DateTime now) {
  final store = CustomStatusStore.of(settings);
  final active = store.active;
  if (active != null && statusHasContent(active)) {
    // An end time in the past ends an absolute status.
    final end = active['timeMode'] == 'absolute' ? jsNum(active['end']).toInt() : 0;
    if (end == 0 || end > now.millisecondsSinceEpoch) {
      return (status: active, appliedAt: jsNum(active['appliedAt']).toInt(), source: 'manual');
    }
  }
  for (final p in store.profiles) {
    final start = scheduleWindowStart(p['schedule'] as Map<String, dynamic>, now);
    if (start != null && statusHasContent(p['status'] as Map<String, dynamic>)) {
      return (status: p['status'] as Map<String, dynamic>, appliedAt: start.millisecondsSinceEpoch, source: 'schedule:${p['name']}');
    }
  }
  return null;
}

/// The start and end Discord gets for a status applied at [appliedAt].
({int start, int end}) statusTimes(Map<String, dynamic> s, int appliedAt) {
  switch (s['timeMode']) {
    case 'absolute':
      return (start: jsNum(s['start']).toInt(), end: jsNum(s['end']).toInt());
    case 'relative':
      final rs = jsNum(s['relStart']).toInt(), re = jsNum(s['relEnd']).toInt();
      return (start: rs > 0 || re == 0 ? appliedAt - rs * 60000 : 0, end: re > 0 ? appliedAt + re * 60000 : 0);
    default:
      return (start: 0, end: 0);
  }
}

// ---- "Show on Discord" ----

/// A unique id for this run of the app ("until I close the app").
final String kAppSessionId = DateTime.now().microsecondsSinceEpoch.toRadixString(36);

/// The pinned title while it lasts, or null.
({String titleId, String type})? activePin(Map<String, dynamic>? discordConfig, int now) {
  final p = asMap(discordConfig?['pinned']);
  if (p == null || jsStr(p['titleId']).isEmpty) return null;
  final until = jsNum(p['until']).toInt();
  if (until > 0 && until <= now) return null;
  final session = jsStr(p['session']);
  if (session.isNotEmpty && session != kAppSessionId) return null;
  final type = jsStr(p['type']);
  return (titleId: jsStr(p['titleId']), type: const ['watching', 'listening', 'playing', 'reading'].contains(type) ? type : '');
}
