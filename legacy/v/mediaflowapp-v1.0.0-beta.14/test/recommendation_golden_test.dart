// MediaFlow Recommends in the app must change the account exactly like the
// real website (v554). Fixtures come from running the website itself
// (tool/website_reference/generate_recommendation_goldens.py).
//
// Run with TZ=UTC (the fixtures were recorded in UTC).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow/src/data/account_ops.dart';
import 'package:mediaflow/src/logic/leveling.dart';
import 'package:mediaflow/src/logic/log_draft.dart';
import 'package:mediaflow/src/logic/rec_submit.dart';
import 'package:mediaflow/src/logic/recommend.dart';
import 'package:mediaflow/src/logic/resume.dart';
import 'package:mediaflow/src/state/state_codec.dart';

Map<String, dynamic> _load(String name) =>
    (jsonDecode(File('test/fixtures/$name.json').readAsStringSync()) as Map).cast<String, dynamic>();

Map<String, dynamic> _copy(Object? v) => (jsonDecode(jsonEncode(v)) as Map).cast<String, dynamic>();

/// Replaces values that legitimately differ between runs (random ids, the
/// exact millisecond of "now") so the rest can be compared exactly.
Object? normalize(Object? value, int now, Set<String> oldSessionIds) {
  Object? walk(Object? v) {
    if (v is num) {
      if (v >= now && v < now + 120000) return 'NOW';
      return v.toDouble();
    }
    if (v is List) return [for (final x in v) walk(x)];
    if (v is Map) return {for (final e in v.entries) e.key.toString(): walk(e.value)};
    return v;
  }

  final state = _copy(value);
  for (final k in ['savedAt', 'portableExtras', '__mfAndroidCompanionDraftV1']) {
    state.remove(k);
  }
  for (final s in (state['sessions'] as List)) {
    final m = s as Map;
    if (oldSessionIds.contains(m['id'])) continue;
    m['id'] = 'NEW';
    if (m.containsKey('sessionGroupId')) m['sessionGroupId'] = 'GROUP';
    if (m.containsKey('v369CommitId')) m['v369CommitId'] = 'GROUP';
  }
  final log = state['activityLog'];
  if (log is List && log.isNotEmpty) (log.first as Map)['id'] = 'ACTIVITY';
  final settings = state['settings'] as Map;
  settings.remove('v181Logging'); // changed by a fixture script, not by logging
  final ledger = (state['xpLedger'] as Map?) ?? {};
  ledger.remove('v334ActiveTimeDays'); // website foreground-time tracking
  // The website's own forecast-vs-actual safety net (mf544). The app's minutes
  // in progress mode are always derived, so it never has a shortfall to credit.
  ledger.remove('v544LogAwardGuarantees');
  final events = (ledger['v348ActionEvents'] as Map?) ?? {};
  ledger['v348ActionEvents'] = (events.entries.map((e) => '${e.key.toString().split(':').first}=${e.value}').toList()..sort());
  final meta = (ledger['v348EventMeta'] as Map?) ?? {};
  ledger['v348EventMeta'] = (meta.values.map((v) => jsonEncode(walk(v))).toList()..sort());
  return walk(state);
}

Object? _normX(Object? v, int now) => (normalize({'sessions': [], 'settings': {}, 'x': v}, now, const {}) as Map)['x'];

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

/// The account exactly as the website had it when Submit was pressed.
({Map<String, dynamic> state, Map<String, dynamic> draft, List<String> newIds}) _atSubmit(Map<String, dynamic> fx) {
  final state = deepCopyState((fx['before'] as Map).cast<String, dynamic>());
  final libraryAtSubmit = (fx['libraryAtSubmit'] as List).cast<Map>();
  final beforeIds = {for (final i in (state['library'] as List)) (i as Map)['id']};
  final draft = _copy(fx['logDraft']);
  final newIds = <String>[];
  // Titles typed into the form are created by the app when the log is saved.
  for (final e in (draft['entries'] as List).cast<Map>()) {
    if (!beforeIds.contains(e['libraryId'])) {
      newIds.add(e['libraryId'] as String);
      e['libraryId'] = null;
    } else {
      newIds.add('unused');
    }
  }
  state['library'] = [for (final i in libraryAtSubmit) if (beforeIds.contains(i['id'])) _copy(i)];
  state['respectState'] = _copy(fx['respectAtSubmit']);
  state['currentTask'] = _copy(fx['task']);
  state['sessionActive'] = true;
  return (state: state, draft: draft, newIds: newIds);
}

void main() {
  test('fixtures are compared in UTC', () {
    expect(DateTime.now().timeZoneOffset, Duration.zero, reason: 'Run with TZ=UTC.');
  });

  for (final name in [
    'rec-quick-progress',
    'rec-quick-mixed',
    'rec-not-followed',
    'rec-itemized-units',
    'rec-itemized-last',
    'rec-reroll-title',
    'rec-new-title',
  ]) {
    test('a recommendation log matches the website exactly: $name', () {
      final fx = _load(name);
      final now = (fx['now'] as num).toInt();
      final at = _atSubmit(fx);
      final expected = (fx['after'] as Map).cast<String, dynamic>();
      final oldIds = {for (final s in (fx['before']['sessions'] as List)) (s as Map)['id'] as String};
      final req = RecLogRequest(
        task: _copy(fx['task']),
        logDraft: at.draft,
        createdAt: now,
        sessionIds: [for (var i = 0; i < 8; i++) 'native_session_$i'],
        groupId: 'native_group',
        activityId: 'native_activity',
        eventId: 'native_event',
        newTitleIds: at.newIds,
        nextTask: _copy(expected['currentTask']),
      );
      final outcome = applyRecLog(at.state, req);
      expect(outcome.error, isNull);
      expect(outcome.applied, isTrue);

      final got = normalize(at.state, now, oldIds) as Map;
      final want = normalize(expected, now, oldIds) as Map;
      final diffs = <String>[];
      _diff(want, got, 'state', diffs);
      expect(diffs, isEmpty, reason: 'App differs from the website ($name):\n${diffs.take(40).join('\n')}');

      // Replaying the same log (e.g. after a sync conflict) changes nothing.
      final again = applyRecLog(at.state, req);
      expect(again.applied, isFalse);
      expect(again.alreadyApplied, isTrue);
    });
  }

  for (final name in ['engine-start', 'engine-start-exact', 'engine-reroll', 'engine-skip', 'engine-end']) {
    test('MediaFlow Recommends picks like the website: $name', () {
      final fx = _load(name);
      final now = (fx['now'] as num).toInt();
      final state = deepCopyState((fx['before'] as Map).cast<String, dynamic>());
      final live = (fx['live'] as Map).cast<String, dynamic>();
      final r = Recommender(state, now: now + 3000, random: () => 0.5, uid: () => 'TASK');
      final l = Leveling(state);
      final before = (state['sessions'] as List).length;
      switch (name) {
        case 'engine-start' || 'engine-start-exact':
          startSession(state, r);
        case 'engine-reroll':
          rotateTask(state, r);
        case 'engine-skip':
          skipTask(state, r, l);
        case 'engine-end':
          endSession(state, r);
      }
      Object? norm(Object? v) {
        final m = v == null ? null : _copy({'v': v})['v'];
        if (m is Map) {
          m.remove('id');
          m.remove('createdAt');
        }
        return _normX(m, now);
      }

      final diffs = <String>[];
      _diff(norm(live['task']), norm(state['currentTask']), 'task', diffs);
      _diff(_normX(live['respectState'], now),
          _normX(state['respectState'], now), 'respectState', diffs);
      expect(state['sessionActive'], live['sessionActive']);
      if (name == 'engine-skip') {
        final added = (state['sessions'] as List).sublist(before).cast<Map>();
        final want = (fx['after']['sessions'] as List).sublist(before).cast<Map>();
        expect(added.length, want.length);
        for (var i = 0; i < added.length; i++) {
          final a = _copy(added[i])..remove('id');
          final w = _copy(want[i])..remove('id');
          _diff(_normX(w, now),
              _normX(a, now), 'skipped', diffs);
        }
      }
      expect(diffs, isEmpty, reason: 'Task engine differs from the website ($name):\n${diffs.join('\n')}');
    });
  }

  group('the logging form behaves like the website form', () {
    Map<String, dynamic> stateFor(Map<String, dynamic> fx) {
      final state = deepCopyState((fx['before'] as Map).cast<String, dynamic>());
      state['library'] = _copy({'l': fx['libraryAtSubmit']})['l'];
      return state;
    }

    List<Map<String, dynamic>> core(Map<String, dynamic> draft) => [
          for (final e in (draft['entries'] as List).cast<Map>())
            {
              'libraryId': e['libraryId'],
              'qty': (e['qty'] as num).toDouble(),
              'start': (e['v179StartProgress'] as num?)?.toDouble(),
              'end': (e['v179EndProgress'] as num?)?.toDouble(),
              'repeat': e['isRepeat'],
              'units': [
                for (final u in ((e['v369Units'] as List?) ?? const []).cast<Map>())
                  '${u['number']}|${u['seasonId']}|${u['durationSeconds']}|${u['isRepeat']}'
              ],
            }
        ];

    test('quick progress entry', () {
      final fx = _load('rec-quick-progress');
      final state = stateFor(fx);
      final ed = LogDraftEditor.open(state, _copy(fx['task']), clock: () => 1793433603000);
      expect(ed.switchInterface('quick'), isNull);
      ed.entryDraft = {'title': 'Test Anime Alpha', 'qty': 1, 'libraryId': 'lib_alpha', 'endProgress': 5};
      expect(ed.addQuickEntry(), isNull);
      final want = (fx['logDraft'] as Map).cast<String, dynamic>();
      expect(core(ed.logDraft), core(want));
      expect(ed.logDraft['amount'], want['amount']);
      expect(ed.logDraft['minutes'], want['minutes']);
      expect(ed.logDraft['v179Mode'], want['v179Mode']);
    });

    test('per-unit entries with seasons, durations and times', () {
      final fx = _load('rec-itemized-units');
      final state = stateFor(fx);
      var clock = 1793433603000;
      final ed = LogDraftEditor.open(state, _copy(fx['task']), clock: () => clock += 10);
      expect(ed.itemized, isTrue);
      ed.entryDraft = {'title': 'Test Anime Alpha', 'qty': 1, 'libraryId': 'lib_alpha'};
      expect(ed.addQuickEntry(), isNull);
      expect(ed.addUnit(0), isNull);
      expect(ed.addUnit(0), isNull);
      expect(ed.editUnit(0, 0, 'duration-1', 21), isNull);
      expect(ed.editUnit(0, 1, 'time', clock - 3600000), isNull);
      ed.entryDraft = {'title': 'Seasoned Show', 'qty': 1, 'libraryId': 'lib_show'};
      expect(ed.addQuickEntry(), isNull);
      ed.selectSeason(1, 's2');
      expect(ed.addUnit(1), isNull);
      final want = (fx['logDraft'] as Map).cast<String, dynamic>();
      expect(core(ed.logDraft), core(want));
      expect(ed.logDraft['amount'], want['amount']);
      expect(ed.logDraft['minutes'], want['minutes']);
      expect(ed.logDraft['v369DurationSeconds'], want['v369DurationSeconds']);
    });

    test('Progress Reached in a season', () {
      final fx = _load('rec-itemized-last');
      final state = stateFor(fx);
      final ed = LogDraftEditor.open(state, _copy(fx['task']), clock: () => 1793433603000);
      ed.entryDraft = {'title': 'Seasoned Show', 'qty': 1, 'libraryId': 'lib_show'};
      expect(ed.addQuickEntry(), isNull);
      ed.setMethod(0, 'last');
      ed.selectSeason(0, 's2');
      expect(ed.setQuantity(0, 3), isNull);
      final want = (fx['logDraft'] as Map).cast<String, dynamic>();
      expect(core(ed.logDraft), core(want));
      expect(ed.logDraft['minutes'], want['minutes']);
    });
  });

  test('a per-unit log made with the form saves on the device and on a fresh cloud copy', () {
    final fx = _load('rec-quick-progress');
    final device = deepCopyState((fx['before'] as Map).cast<String, dynamic>());
    final cloud = _copy(fx['before']);
    final task = _copy(device['currentTask']);
    var clock = DateTime.now().millisecondsSinceEpoch - 60000;
    final ed = LogDraftEditor.open(device, task, clock: () => clock += 1000);
    ed.entryDraft = {'title': 'Test Anime Alpha', 'qty': 1, 'libraryId': 'lib_alpha'};
    expect(ed.addQuickEntry(), isNull);
    expect(ed.addUnit(0), isNull);
    expect(ed.validate(), isNull);
    final req = RecLogRequest.create(task, ed.logDraft);
    final local = applyRecLog(device, req);
    expect(local.error, isNull);
    expect(local.applied, isTrue);
    final restored = AccountOp.fromJson(_copy(RecLogOp(req).toJson()));
    expect(restored.apply(cloud), isTrue);
    final added = (cloud['sessions'] as List).cast<Map>().where((s) => s['v369Itemized'] == true).toList();
    expect(added.length, 1);
    expect(cloud['currentTask']['id'], device['currentTask']['id']);
  });

  group('shared draft and synced recommendation state', () {
    test('the newer draft wins and per-unit drafts of one session merge', () {
      final state = <String, dynamic>{};
      final task = {'id': 't1', 'categoryId': 'seasonal', 'targetMid': 2};
      Map<String, dynamic> draft(List<Map<String, dynamic>> units) => {
            'v369Interface': 'itemized',
            'v369CommitId': 'c1',
            'entries': [
              {'libraryId': 'lib_alpha', 'title': 'A', 'qty': units.length, 'v369UpdatedAt': units.length, 'v369Units': units},
            ],
          };
      final u1 = {'id': 'u1', 'number': 4, 'loggedAt': 100, 'durationSeconds': 60, 'v369UpdatedAt': 100};
      final u2 = {'id': 'u2', 'number': 5, 'loggedAt': 200, 'durationSeconds': 60, 'v369UpdatedAt': 200};
      expect(applyLoggingSection(state, activeLogging(task: task, logDraft: draft([u1]), entryDraft: {}, modifiedAt: 1000)), isTrue);
      expect(applyLoggingSection(state, activeLogging(task: task, logDraft: draft([u2]), entryDraft: {}, modifiedAt: 2000)), isTrue);
      final merged = readLogging(state)!;
      final entries = (merged['logDraft']['entries'] as List).cast<Map>();
      expect([for (final u in entries.single['v369Units'] as List) (u as Map)['id']], ['u1', 'u2']);
      // An older quick draft never replaces a newer one.
      expect(
          applyLoggingSection(state, activeLogging(task: task, logDraft: {'v369Interface': 'quick'}, entryDraft: {}, modifiedAt: 1500)),
          isFalse);
      clearLoggingDraft(state, 3000, submittedCommitId: 'c1');
      expect(readLogging(state)!['active'], isFalse);
    });

    test('task actions replay once on a newer cloud copy', () {
      final fx = _load('engine-reroll');
      final device = deepCopyState((fx['before'] as Map).cast<String, dynamic>());
      final cloud = deepCopyState((fx['before'] as Map).cast<String, dynamic>());
      final op = TaskOp.perform(device, TaskAction.skip, now: (fx['now'] as num).toInt())!;
      final restored = AccountOp.fromJson(_copy(op.toJson()));
      expect(restored.apply(cloud), isTrue);
      expect(cloud['currentTask']['id'], device['currentTask']['id']);
      expect((cloud['sessions'] as List).length, (device['sessions'] as List).length);
      expect(restored.apply(cloud), isFalse, reason: 'already applied');
      expect(cloud['respectState']['totalSkips'], device['respectState']['totalSkips']);
    });

    test('a title reroll keeps the same task and records the history', () {
      final fx = _load('rec-reroll-title');
      final state = deepCopyState((fx['before'] as Map).cast<String, dynamic>());
      state['library'] = _copy({'l': fx['libraryAtSubmit']})['l'];
      final task = _copy(fx['task']);
      task.remove('v180RecommendationHistory');
      task['libraryId'] = 'lib_alpha';
      task['title'] = 'Test Anime Alpha';
      state['currentTask'] = task;
      final r = Recommender(state, now: 1793433602000, random: () => 0.5);
      expect(rerollTitle(state, r).changed, isTrue);
      final history = (state['currentTask']['v180RecommendationHistory'] as List).cast<Map>();
      expect(history.map((h) => h['libraryId']).toList(), ['lib_alpha', 'lib_alpha2']);
      expect(state['currentTask']['id'], task['id']);
      expect(state['currentTask']['v180TitleRerolls'], 1);
    });
  });
}
