// The native logging engine must change the account exactly like the real
// MediaFlow website's Batch Log does. Fixtures are produced by running the
// website itself (tool/website_reference/generate_log_goldens.py).
//
// Run with TZ=UTC (the fixtures were recorded in UTC; start dates use local noon).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow/src/logic/log_engine.dart';
import 'package:mediaflow/src/state/state_codec.dart';

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
  test('fixtures are compared in UTC', () {
    expect(DateTime.now().timeZoneOffset, Duration.zero,
        reason: 'Run the logging golden tests with TZ=UTC (fixtures were recorded in UTC).');
  });

  for (final name in ['mixed-batch', 'seasons', 'streak']) {
    test('a native log matches the website exactly: $name', () {
      final fx = _load('log-$name.json');
      final now = (fx['now'] as num).toInt();
      final before = deepCopyState((fx['before'] as Map).cast<String, dynamic>());
      final expected = (fx['after'] as Map).cast<String, dynamic>();
      final rows = (fx['rows'] as List).cast<Map>();
      final oldIds = {for (final s in (before['sessions'] as List)) (s as Map)['id'] as String};

      final req = LogRequest(
        entries: [
          for (final r in rows)
            LogEntry(
              libraryId: r['libraryId'] as String,
              reached: (r['reached'] as num).toDouble(),
              minutes: r['minutes'] == null ? null : (r['minutes'] as num).toDouble(),
            ),
        ],
        createdAt: now,
        note: fx['note'] as String,
        sessionIds: [for (var i = 0; i < rows.length; i++) 'native_session_$i'],
        groupId: 'native_group',
        eventId: 'native_event',
      );
      final outcome = applyLog(before, req);
      expect(outcome.applied, isTrue);

      final got = normalize(before, now, oldIds) as Map;
      final want = normalize(expected, now, oldIds) as Map;
      final diffs = <String>[];
      _diff(want, got, 'state', diffs);
      expect(diffs, isEmpty, reason: 'Native log differs from the website ($name):\n${diffs.take(40).join('\n')}');

      // Applying the same log again must not duplicate anything.
      final again = applyLog(before, req);
      expect(again.applied, isFalse);
      expect(again.alreadyApplied, isTrue);
    });
  }

  test('a log with no amount changes nothing', () {
    final fx = _load('log-mixed-batch.json');
    final state = deepCopyState((fx['before'] as Map).cast<String, dynamic>());
    final copy = jsonEncode(state);
    final req = LogRequest.create([const LogEntry(libraryId: 'lib_alpha', reached: 3)], now: (fx['now'] as num).toInt());
    expect(applyLog(state, req).applied, isFalse);
    expect(jsonEncode(state), copy);
  });
}
