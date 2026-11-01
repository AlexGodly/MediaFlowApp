// Times the app's heavy steps on a synthetic account about as large as the
// biggest real one (~38 MB of JSON). Not part of the normal test run:
//   flutter test tool/bench/large_account_bench_test.dart
// Prints a table; asserts only that the results are sane.

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow/src/data/account_ops.dart';
import 'package:mediaflow/src/data/edit_op.dart';
import 'package:mediaflow/src/data/sync_engine.dart';
import 'package:mediaflow/src/logic/extras.dart';
import 'package:mediaflow/src/logic/history_logic.dart';
import 'package:mediaflow/src/logic/library_logic.dart';
import 'package:mediaflow/src/logic/rec_submit.dart';
import 'package:mediaflow/src/logic/stats.dart';
import 'package:mediaflow/src/logic/xp_preview.dart';
import 'package:mediaflow/src/state/lazy_copy.dart';
import 'package:mediaflow/src/state/models.dart';
import 'package:mediaflow/src/state/state_codec.dart';
import 'package:mediaflow/src/util/js.dart';

const _sessions = 22000;
const _titles = 2500;
const _activity = 800;

Map<String, dynamic> _bigAccount(Map<String, dynamic> base) {
  final state = deepCopyState(base);
  final cats = (state['categories'] as List).map((c) => (c as Map)['id'] as String).toList();
  final itemTemplate = (state['library'] as List).first as Map;
  final sessionTemplate = (state['sessions'] as List).first as Map;
  const day = 86400000;
  final end = 1793433600000;
  final library = <dynamic>[...(state['library'] as List)];
  for (var i = 0; i < _titles; i++) {
    final it = jsonClone(itemTemplate) as Map<String, dynamic>;
    it['id'] = 'lib_bench_$i';
    it['title'] = 'Bench Title $i — a reasonably long name';
    it['categoryId'] = cats[i % cats.length];
    it['progress'] = i % 40;
    it['total'] = 40;
    it['status'] = i % 5 == 0 ? 'completed' : (i % 3 == 0 ? 'planned' : 'active');
    it['synopsis'] = 'A synopsis of moderate length for title $i. ' * 6;
    it['genres'] = ['Action', 'Drama', 'Slice of Life'];
    it['coverUrl'] = 'https://example.com/covers/$i.jpg';
    it['createdAt'] = end - (i * 3 * day ~/ 2);
    library.add(it);
  }
  state['library'] = library;
  final sessions = <dynamic>[...(state['sessions'] as List)];
  for (var i = 0; i < _sessions; i++) {
    final s = jsonClone(sessionTemplate) as Map<String, dynamic>;
    final ts = end - 1 - i * (4 * 365 * day ~/ _sessions);
    final lib = 'lib_bench_${i % _titles}';
    s['id'] = 'ses_bench_$i';
    s['sessionGroupId'] = 'grp_bench_${i ~/ 2}';
    s['timestamp'] = ts;
    s['date'] = isoDateUtc(ts);
    s['categoryId'] = cats[i % cats.length];
    s['assignedCategoryId'] = s['categoryId'];
    s['xp'] = 200 + i % 900;
    s['titles'] = [
      {'title': 'Bench Title ${i % _titles}', 'libraryId': lib, 'qty': 1 + i % 3, 'repeat': false, 'loggedAt': ts},
    ];
    sessions.add(s);
  }
  sessions.sort((a, b) => jsNum((a as Map)['timestamp']).compareTo(jsNum((b as Map)['timestamp'])));
  state['sessions'] = sessions;
  state['activityLog'] = [
    for (var i = 0; i < _activity; i++)
      {
        'id': 'act_bench_$i',
        'timestamp': end - i * day,
        'action': 'Edit title',
        'detail': 'Bench Title $i',
        'changes': [
          {'id': 'lib_bench_$i', 'title': 'Bench Title $i', 'kind': 'changed', 'fields': ['progress: 1 → 2', 'status: active → completed']},
        ],
        'titleIds': ['lib_bench_$i'],
        'titleSnapshot': 'Bench Title $i',
        'xpEarned': 15,
        if (i % 20 == 0) 'deletedItems': [for (var k = 0; k < 5; k++) library[(i + k) % library.length]],
      },
  ];
  final ledger = asMap(state['xpLedger'])!;
  ledger['libraryAdditions'] = {for (var i = 0; i < _titles; i++) 'lib_bench_$i': 15};
  ledger['logCompletions'] = {for (var i = 0; i < _titles; i += 5) 'lib_bench_$i': 50};
  state['completionTimeline'] = [
    for (var i = 0; i < _titles; i += 5) {'id': 'ct_$i', 'libraryId': 'lib_bench_$i', 'completedAt': end - i * day, 'title': 'Bench Title $i'},
  ];
  return jsonClone(state) as Map<String, dynamic>;
}

final _rows = <String>[];

/// Hands [s] to an isolate and back (top-level, so only [s] is sent).
Future<Map<String, dynamic>> _handOver(Map<String, dynamic> s) => Isolate.run(() => s);

T _time<T>(String label, T Function() run, {int repeat = 1}) {
  late T out;
  final times = <int>[];
  for (var i = 0; i < repeat; i++) {
    final sw = Stopwatch()..start();
    out = run();
    times.add(sw.elapsedMilliseconds);
  }
  times.sort();
  _rows.add('${label.padRight(58)} ${times[times.length ~/ 2].toString().padLeft(7)} ms');
  return out;
}

Future<T> _timeAsync<T>(String label, Future<T> Function() run) async {
  final sw = Stopwatch()..start();
  final out = await run();
  _rows.add('${label.padRight(58)} ${sw.elapsedMilliseconds.toString().padLeft(7)} ms');
  return out;
}

void main() {
  test('large account benchmark', () async {
    final fx = (jsonDecode(File('test/fixtures/rec-quick-progress.json').readAsStringSync()) as Map).cast<String, dynamic>();
    final task = (fx['task'] as Map).cast<String, dynamic>();
    final draft = (fx['logDraft'] as Map).cast<String, dynamic>();
    final state = _bigAccount((fx['before'] as Map).cast<String, dynamic>());

    final text = _time('jsonEncode (whole account)', () => jsonEncode(state));
    _rows.add('${'  account size'.padRight(58)} ${(text.length / 1e6).toStringAsFixed(1).padLeft(7)} MB');
    final sizes = {for (final e in state.entries) e.key: jsonEncode(e.value).length};
    final top = sizes.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    for (final e in top.take(5)) {
      _rows.add('${'    ${e.key}'.padRight(58)} ${(e.value / 1e6).toStringAsFixed(2).padLeft(7)} MB');
    }
    _time('jsonDecode (whole account)', () => jsonDecode(text));
    final raw = _time('encodeStateData (gzip + base64)', () => encodeStateData(state));
    _rows.add('${'  compressed size'.padRight(58)} ${((raw['data'] as String).length / 1e6).toStringAsFixed(1).padLeft(7)} MB');
    _time('decodeStateData', () => decodeStateData(raw));
    _time('jsonClone (whole account)', () => jsonClone(state));

    // What Beta 15 did on the screen's thread when handing the account to an isolate.
    final sw = Stopwatch()..start();
    final handed = _handOver(state);
    final syncPart = sw.elapsedMilliseconds;
    await handed;
    _rows.add('${'Beta 15: hand account to isolate (screen thread part)'.padRight(58)} ${syncPart.toString().padLeft(7)} ms');
    _rows.add('${'Beta 15: hand account to isolate (total)'.padRight(58)} ${sw.elapsedMilliseconds.toString().padLeft(7)} ms');
    _time('Beta 15: diffStates(account, full copy)', () => diffStates(state, jsonClone(state) as Map<String, dynamic>));

    _time('AccountView (new view after each change)', () => AccountView(state));
    _time('AccountView + library + logs', () {
      final v = AccountView(state);
      return v.library.length + v.logs.length;
    });

    // Background work in Beta 16.
    final draftOp = DraftOp('d', {'active': false, 'modifiedAt': 1});
    final hand2 = Stopwatch()..start();
    final merged = mergeInBackground(runInIsolate, raw, [draftOp]);
    final hand2Sync = hand2.elapsedMilliseconds;
    await merged;
    _rows.add('${'Beta 16: sync merge, screen thread part'.padRight(58)} ${hand2Sync.toString().padLeft(7)} ms');
    _rows.add('${'Beta 16: sync merge (decode+replay+encode, background)'.padRight(58)} ${hand2.elapsedMilliseconds.toString().padLeft(7)} ms');
    _time('mergeState inline (same work)', () => mergeState(raw, [draftOp]));

    _time('xpPreviewData (trial save, background in the app)', () => xpPreviewData(jsonClone(state) as Map<String, dynamic>, task, draft));
    _time('  of which jsonClone', () => jsonClone(state));
    final saveCopy = jsonClone(state) as Map<String, dynamic>;
    _time('applyRecLog (Save, screen thread)', () => applyRecLog(saveCopy, RecLogRequest.create(task, draft)));
    final taskCopy = jsonClone(state) as Map<String, dynamic>;
    _time('TaskOp.perform reroll (screen thread)', () => TaskOp.perform(taskCopy, TaskAction.reroll));
    _time('xpMetrics', () => xpMetrics(state));

    // Pages (computed once per change of the account while the page is open).
    final now = DateTime.fromMillisecondsSinceEpoch(1793433600000);
    _time('Statistics page model', () {
      final m = StatsModel(state, now);
      final parts = <Object?>[
        m.xp, m.level, m.life, m.today, m.week, m.month, m.streak, m.last7, m.last30, m.last90, m.titles,
        m.libraryStatus, m.priorities, m.achievements, m.averageDaily, m.averageRating, m.categoryBalance, m.categoryMix,
        m.categoryStreaks, m.completionRate, m.completionTimeline, m.heatmapYears, m.leastConsumed, m.mediaTypeMix,
        m.mostConsumed, m.mostNeglected, m.rated8, m.rated95, m.ratedCount, m.ratingDistribution, m.recapMonths,
        m.repeats, m.saturation, m.avgDaily7, m.avgSession, m.peakDay, m.mostActiveDay, m.totalUnits, m.logicalSessions,
      ];
      for (final y in m.heatmapYears) {
        parts.add(m.heatmap(y));
      }
      for (final mo in m.recapMonths) {
        parts.add(m.recap(mo));
      }
      return parts.length;
    });
    _time("Today's Balance", () => todayBalance(state, now.millisecondsSinceEpoch));
    _time('On This Day', () => onThisDay(state, now));
    _time('XP History', () => xpHistory(state));
    _time('History list order', () {
      final logs = List<LogRecord>.of(AccountView(state).logs)..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return logs.length;
    });

    // Edits: Beta 15 (full copy + full compare) vs Beta 16 (copy what is touched).
    final t = findTitle(state, 'lib_bench_7')!;
    final f = TitleFields.of(t);
    final fields = TitleFields(
      title: f.title, categoryId: f.categoryId, progress: 12, total: f.total, status: f.status, priority: f.priority,
      estimatedMinutes: f.estimatedMinutes, tags: f.tags, rating: 7.5, coverUrl: f.coverUrl,
      repeatFull: f.repeatFull, repeatExtra: f.repeatExtra, startedAt: f.startedAt, completedAt: f.completedAt,
    );
    var n = 0;
    String uid() => 'id_bench_${n++}';
    final when = DateTime.now().millisecondsSinceEpoch;
    _time('Beta 15: edit a title (full copy + compare)', () {
      final copy = jsonClone(state) as Map<String, dynamic>;
      saveTitle(copy, 'lib_bench_7', fields, when, uid);
      return diffStates(state, copy).length;
    });
    _time('Beta 16: edit a title (lazy copy)', () {
      final copy = LazyStateCopy(state);
      saveTitle(copy, 'lib_bench_7', fields, when, uid);
      _rows.add('    touched: ${copy.touched.join(', ')}');
      return diffStates(state, copy).length;
    });
    _time('Beta 16: delete one log (lazy copy)', () {
      final copy = LazyStateCopy(state);
      deleteSessions(copy, {'ses_bench_100'}, when);
      _rows.add('    touched: ${copy.touched.join(', ')}');
      return diffStates(state, copy).length;
    });
    final applied = jsonClone(state) as Map<String, dynamic>;
    final lazy = LazyStateCopy(applied);
    saveTitle(lazy, 'lib_bench_7', fields, when, uid);
    final op = editFromStates(applied, lazy, now: when)!;
    _time('Beta 16: apply the saved edit to the account', () => op.apply(applied));
    expect(findTitle(applied, 'lib_bench_7')!['progress'], 12);

    // ignore: avoid_print
    print('\n==== MediaFlow large-account benchmark ====\n${_rows.join('\n')}\n===========================================\n');
  }, timeout: const Timeout(Duration(minutes: 20)));
}
