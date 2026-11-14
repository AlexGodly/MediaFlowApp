// "XP for this log" — the website's logging XP card (mf537/mf542/mf553), filled
// in by a trial save: the draft is saved on a throwaway copy of the account in
// the background (AccountController.previewXp), and the card shows exactly
// what saving would award.

import 'dart:math' as math;

import '../util/js.dart';
import 'leveling.dart';
import 'library_hooks.dart';
import 'log_draft.dart';
import 'rec_submit.dart';

/// Everything the card shows, as plain data (crosses the isolate boundary).
class XpPreview {
  XpPreview(this.data);
  final Map<String, dynamic> data;

  String? get error => data['error'] as String?;
  num get total => data['total'] as num? ?? 0;
  num get consumption => data['consumption'] as num? ?? 0;
  num get respect => data['respect'] as num? ?? 0;
  num get streakBonus => data['streakBonus'] as num? ?? 0;
  num get streakDay => data['streakDay'] as num? ?? 0;
  num get dayMultiplier => data['dayMultiplier'] as num? ?? 1;
  bool get respected => data['respected'] == true;
  bool get eligible => data['eligible'] == true;
  List<Map<String, dynamic>> get extras => asList(data['extras']).map(asMap).whereType<Map<String, dynamic>>().toList();
  List<Map<String, dynamic>> get categories => asList(data['categories']).map(asMap).whereType<Map<String, dynamic>>().toList();
  Map<String, dynamic> get respectDetails => asMap(data['respectDetails']) ?? const {};
  num get rawTotal => data['rawTotal'] as num? ?? 0;
}

double _sum(Object? map) =>
    (asMap(map) ?? const {}).values.fold<double>(0, (a, v) => a + math.max(0, jsNum(v)));

/// The trial save itself (synchronous; also used by tests).
Map<String, dynamic> xpPreviewData(Map<String, dynamic> state, Map<String, dynamic> task, Map<String, dynamic> logDraft) {
  final l = Leveling(state);
  final editor = LogDraftEditor(state: state, task: task, logDraft: logDraft, entryDraft: {});
  final problem = editor.validate();
  final ledger = asMap(state['xpLedger']) ?? const {};
  const keys = ['logCompletions', 'v334StartedTitles', 'v335FirstEpisodeRewards', 'v348LibraryCompletionBonus', 'v348LibraryAdditionBonus', 'libraryAdditions'];
  final before = {for (final k in keys) k: _sum(ledger[k])};
  final completedBefore = asList(state['library']).map(asMap).whereType<Map<String, dynamic>>().where(isCompletedItem).length;
  final libraryBefore = asList(state['library']).length;
  final sessionsBefore = asList(state['sessions']).length;
  final now = DateTime.now().millisecondsSinceEpoch;
  if (problem != null && editor.entries.isEmpty && !(jsNum(logDraft['amount']) > 0)) {
    return {'error': null, 'eligible': false, 'total': 0};
  }
  final req = RecLogRequest(
    task: task,
    logDraft: logDraft,
    createdAt: now,
    sessionIds: [for (var i = 0; i < 64; i++) 'preview_$i'],
    groupId: 'preview_group',
    activityId: 'preview_activity',
    eventId: 'preview',
    newTitleIds: [for (var i = 0; i < 64; i++) 'preview_new_$i'],
    nextTask: const {'id': 'preview_next'},
  );
  final outcome = applyRecLog(state, req);
  if (!outcome.applied) {
    return {'error': outcome.error ?? problem ?? 'This log can’t be saved yet.', 'eligible': false, 'total': 0};
  }
  final added = asList(state['sessions']).skip(sessionsBefore).map(asMap).whereType<Map<String, dynamic>>().toList();
  final rows = added.where((s) => s['status'] != 'skipped').toList();
  double consumption = 0, respect = 0, streak = 0, repeat = 0, reroll = 0, raw = 0;
  final cats = asList(state['categories']).map(asMap).whereType<Map<String, dynamic>>().toList();
  final categories = <Map<String, dynamic>>[];
  for (final s in rows) {
    final xp = math.max(0.0, jsNum(s['xp']));
    final rep = math.max(0.0, jsNum(s['repeatBonusXP']));
    final rr = math.max(0.0, jsNum(s['v553RerollTitleBonusXP']));
    final rsp = math.max(0.0, jsRound(jsNum(s['v165RespectBonusXP'])));
    final base = xp - rep - rr;
    consumption += base;
    repeat += rep;
    reroll += rr;
    respect += rsp;
    streak += math.max(0.0, jsNum(s['streakBonusXP']));
    raw += jsNum(s['streakBaseXP']);
    final cat = cats.where((c) => jsStr(c['id']) == jsStr(s['categoryId'])).firstOrNull ?? const <String, dynamic>{};
    final status = jsStr(s['healthStatus']);
    final unitsXP = jsRound(jsNum(s['actualAmount'])) * l.unitXP(jsStr(cat['unit']));
    final minuteXP = jsRound(jsNum(s['minutes'])) * math.max(0.0, l.minuteXP);
    categories.add({
      'name': jsStr(cat['name']).isEmpty ? 'Category' : jsStr(cat['name']),
      'unit': jsStr(s['unit']),
      'status': status,
      'amount': jsNum(s['actualAmount']),
      'minutes': jsNum(s['minutes']),
      'base': unitsXP + minuteXP,
      'rotation': l.rotationMultiplier(status),
      'xp': base,
      'respect': rsp,
    });
  }
  final after = asMap(state['xpLedger']) ?? const {};
  double delta(String k) => math.max(0.0, _sum(after[k]) - before[k]!);
  final completed = asList(state['library']).map(asMap).whereType<Map<String, dynamic>>().where(isCompletedItem).length - completedBefore;
  final newTitles = asList(state['library']).length - libraryBefore;
  final extras = <Map<String, dynamic>>[
    if (repeat > 0) {'label': 'Repeat units & full repeats', 'xp': repeat},
    if (completed > 0) {'label': 'Completed-title XP', 'xp': completed * l.completionXP},
    if (delta('logCompletions') > 0) {'label': 'Log completion reward', 'xp': delta('logCompletions')},
    if (delta('v348LibraryCompletionBonus') > 0) {'label': 'Completion streak bonuses', 'xp': delta('v348LibraryCompletionBonus')},
    if (delta('v334StartedTitles') > 0) {'label': 'First title start', 'xp': delta('v334StartedTitles')},
    if (delta('v335FirstEpisodeRewards') > 0) {'label': 'First episode', 'xp': delta('v335FirstEpisodeRewards')},
    if (newTitles > 0) {'label': 'New Library titles', 'xp': newTitles * jsRound(l.reward('libraryAdditionXP')) + delta('v348LibraryAdditionBonus')},
    if (reroll > 0) {'label': 'Reroll title reward', 'xp': reroll},
    // Website v580: task goal XP (already inside the logs' streak XP).
    if (_goalXP(rows) > 0) {'label': _goalLabel(rows), 'xp': _goalXP(rows)},
  ];
  final total = rows.fold<double>(0, (a, s) => a + math.max(0.0, jsNum(s['xpWithStreak']))) +
      extras.where((e) =>
              e['label'] != 'Repeat units & full repeats' && e['label'] != 'Reroll title reward' && !jsStr(e['label']).startsWith('Task goal'))
          .fold<double>(0, (a, e) => a + jsNum(e['xp']));
  final target = rows.where((s) => s['v165RespectXPVersion'] != null).firstOrNull;
  return {
    'error': problem,
    'eligible': rows.isNotEmpty,
    'total': jsRound(total),
    'consumption': consumption,
    'respect': respect,
    'streakBonus': streak,
    'rawTotal': raw,
    'streakDay': rows.isEmpty ? 0 : jsNum(rows.first['streakAtLog']),
    'dayMultiplier': rows.isEmpty ? 1 : jsNum(rows.first['streakMultiplier']),
    'respected': outcome.respected,
    'categories': categories,
    'extras': extras,
    'respectDetails': target == null
        ? <String, dynamic>{}
        : {
            'categoryXP': jsNum(target['v165SystemBaseXP']),
            'titleXP': jsNum(target['v165RecommendedTitleBaseXP']),
            'matched': jsNum(target['v180RespectMatchedCount']),
            'slots': jsNum(target['v180RespectSlotLimit']),
            'noSkip': jsNum(target['v165NoSkipStreak']),
            'noReroll': jsNum(target['v165NoRerollStreak']),
            'noSkipMultiplier': jsNum(target['v165NoSkipMultiplier']),
            'noRerollMultiplier': jsNum(target['v165NoRerollMultiplier']),
          },
  };
}

/// Website v580: the task goal XP on these logs (before the day streak).
double _goalXP(List<Map<String, dynamic>> rows) => rows.fold(0.0, (a, s) => a + math.max(0.0, jsNum(s['mf580GoalXP'])));

/// "Task goal · minimum (2) +100 · maximum (4) +300".
String _goalLabel(List<Map<String, dynamic>> rows) {
  final g = rows.map((s) => asMap(s['mf580Goal'])).whereType<Map<String, dynamic>>().firstOrNull;
  if (g == null) return 'Task goal';
  String n(Object? v) => jsNum(v) == jsNum(v).roundToDouble() ? jsNum(v).toInt().toString() : '${jsNum(v)}';
  final bits = [
    if (jsNum(g['min']) > 0) 'minimum (${n(g['low'])}) +${n(g['min'])}',
    if (jsNum(g['max']) > 0) 'maximum (${n(g['high'])}) +${n(g['max'])}',
    if (jsNum(g['extra']) > 0) 'past the maximum +${n(g['extra'])}',
  ];
  return bits.isEmpty ? 'Task goal' : 'Task goal · ${bits.join(' · ')}';
}
