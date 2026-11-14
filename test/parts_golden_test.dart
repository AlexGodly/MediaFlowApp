// Titles logged by parts (website v577): a native Batch Log / Log any title
// must change the account exactly like the real website's Batch Log does with
// parts. Fixtures: tool/website_reference/generate_parts_goldens.cjs (the
// website itself, through its test harness).
//
// Run with TZ=UTC.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow/src/logic/log_engine.dart';
import 'package:mediaflow/src/logic/title_parts.dart';
import 'package:mediaflow/src/state/state_codec.dart';
import 'package:mediaflow/src/util/js.dart';

Map<String, dynamic> _load(String name) =>
    (jsonDecode(File('test/fixtures/$name').readAsStringSync()) as Map).cast<String, dynamic>();

/// Replaces values that legitimately differ between runs (random ids, the
/// exact millisecond of "now") and normalises numbers, so the rest can be
/// compared exactly.
Object? normalize(Object? value, int now, Set<String> oldSessionIds) {
  Object? walk(Object? v, List<String> path) {
    if (v is num) {
      if (v >= now && v < now + 120000) return 'NOW';
      return v.toDouble();
    }
    if (v is List) return [for (var i = 0; i < v.length; i++) walk(v[i], [...path, '$i'])];
    if (v is Map) {
      final out = <String, Object?>{};
      for (final e in v.entries) {
        out[e.key.toString()] = walk(e.value, [...path, e.key.toString()]);
      }
      return out;
    }
    return v;
  }

  final state = (jsonDecode(jsonEncode(value)) as Map).cast<String, dynamic>();
  for (final k in ['savedAt', 'portableExtras', '__mfAndroidCompanionDraftV1']) {
    state.remove(k);
  }
  for (final s in (state['sessions'] as List)) {
    final m = s as Map;
    if (!oldSessionIds.contains(m['id'])) m['id'] = 'NEW';
    if (m.containsKey('batchGroupId')) m['batchGroupId'] = 'GROUP';
  }
  final ledger = (state['xpLedger'] as Map?) ?? {};
  ledger.remove('v334ActiveTimeDays'); // website foreground-time tracking, not logging
  final events = (ledger['v348ActionEvents'] as Map?) ?? {};
  ledger['v348ActionEvents'] = (events.entries.map((e) => '${e.key.toString().split(':').first}=${e.value}').toList()..sort());
  final meta = (ledger['v348EventMeta'] as Map?) ?? {};
  ledger['v348EventMeta'] = (meta.values.map((v) => jsonEncode(walk(v, const []))).toList()..sort());
  return walk(state, const []);
}

/// Path-level differences: "website vs app".
void _diff(Object? want, Object? got, String path, List<String> out) {
  if (out.length > 60) return;
  if (want is Map && got is Map) {
    for (final k in {...want.keys, ...got.keys}) {
      if (!want.containsKey(k)) {
        out.add('$path.$k: app added ${jsonEncode(got[k])}');
      } else if (!got.containsKey(k)) {
        out.add('$path.$k: app is missing (website has ${jsonEncode(want[k])})');
      } else {
        _diff(want[k], got[k], '$path.$k', out);
      }
    }
    return;
  }
  if (want is List && got is List) {
    if (want.length != got.length) out.add('$path: website has ${want.length} items, app has ${got.length}');
    for (var i = 0; i < want.length && i < got.length; i++) {
      _diff(want[i], got[i], '$path[$i]', out);
    }
    return;
  }
  if (want != got) out.add('$path: website ${jsonEncode(want)} vs app ${jsonEncode(got)}');
}

void main() {
  for (final name in ['parts-batch', 'parts-capped']) {
    test('a by-parts log matches the website exactly: $name', () {
      final fx = _load('log-$name.json');
      final now = (fx['now'] as num).toInt();
      final before = deepCopyState((fx['before'] as Map).cast<String, dynamic>());
      final expected = (fx['after'] as Map).cast<String, dynamic>();
      final rows = (fx['rows'] as List).cast<Map>();
      final filled = (fx['filled'] as List).cast<Map>();
      final oldIds = {for (final s in (before['sessions'] as List)) (s as Map)['id'] as String};
      Map<String, dynamic> item(String id) =>
          (before['library'] as List).map((x) => (x as Map).cast<String, dynamic>()).firstWhere((x) => x['id'] == id);

      final entries = <LogEntry>[];
      for (final r in rows) {
        final id = r['libraryId'] as String;
        if (r['parts'] == null) {
          entries.add(LogEntry(libraryId: id, reached: (r['reached'] as num).toDouble()));
          continue;
        }
        // The app works out each part's move from its reached number.
        var moves = <PartMove>[];
        for (final p in (r['parts'] as List).cast<Map>()) {
          moves = setPart(item(id), moves, p['id'] as String, (p['reached'] as num).toDouble(), reached: true);
        }
        entries.add(LogEntry(libraryId: id, parts: moves));
      }
      // Same moves as the website's form.
      for (var i = 0; i < rows.length; i++) {
        if (rows[i]['parts'] == null) continue;
        expect([for (final m in entries[i].parts) m.toJson()], (filled[i]['mf577Parts'] as List), reason: 'row $i parts');
      }
      final req = LogRequest(
        entries: entries,
        createdAt: now,
        note: fx['note'] as String,
        sessionIds: [for (var i = 0; i < rows.length; i++) 'native_session_$i'],
        groupId: 'native_group',
        eventId: 'native_event',
      );
      expect(applyLog(before, req).applied, isTrue);
      final got = normalize(before, now, oldIds) as Map;
      final want = normalize(expected, now, oldIds) as Map;
      for (final m in [got, want]) {
        m.remove('activityLog');
      }
      final diffs = <String>[];
      _diff(want, got, 'state', diffs);
      expect(diffs, isEmpty, reason: 'Native by-parts log differs from the website ($name):\n${diffs.take(40).join('\n')}');
      expect(applyLog(before, req).alreadyApplied, isTrue);
    });
  }

  test('part helpers: minutes, category amount, toggles, history text', () {
    final item = <String, dynamic>{
      'id': 'x', 'mf577LogMode': 'parts', 'mf565Unit': 'sessions', 'mf565SecondsPerUnit': 1800,
      'seasons': [
        {'id': 'a', 'name': 'Competitive', 'progress': 41, 'mf577Kind': 'Mode', 'mf577Unit': 'matches', 'mf577SecondsPerUnit': 2400},
        {'id': 'b', 'name': 'Unrated', 'progress': 4, 'total': 10},
      ],
    };
    final cat = <String, dynamic>{'unit': 'episodes', 'minutesPerUnit': 42};
    final moves = [const PartMove('a', 3), const PartMove('b', 2)];
    expect(partsMinutes(item, cat, moves), 3 * 40 + 2 * 30);
    expect(partsCategoryAmount(item, cat, moves), closeTo(4.29, 1e-9));
    expect(togglePart(item, [const PartMove('a', 1)], 'a').length, 1, reason: 'never the last part');
    expect(setPart(item, const [], 'b', 50, reached: true).single.qty, 6, reason: 'capped at the part total');
    expect(partsHistoryText([
      {'id': 'a', 'name': 'Competitive', 'kind': 'Mode', 'unit': 'matches', 'qty': 3, 'from': 41, 'to': 44},
    ], (u, n) => n == 1 ? 'match' : u), 'Mode · Competitive · Match 41 → 44 (+3)');
    expect(jsNum(item['seasons'][0]['progress']), 41);
  });
}
