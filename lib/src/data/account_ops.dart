// Changes made on this device, kept until they reach the cloud. Each one can be
// replayed on a newer cloud copy: ids and random results are fixed when the
// change is made, and replaying something already present changes nothing.

import 'dart:convert';

import '../logic/action_xp.dart';
import '../logic/extras.dart';
import '../logic/leveling.dart';
import '../logic/log_engine.dart';
import '../logic/rec_submit.dart';
import '../logic/recommend.dart';
import '../logic/resume.dart';
import '../util/js.dart';
import 'edit_op.dart';

abstract class AccountOp {
  String get id;
  String get kind;

  /// Applies the change to [state] in place. Returns true if anything changed.
  bool apply(Map<String, dynamic> state);

  /// Why the last [apply] refused a change that was not already present.
  String? rejection;

  Map<String, dynamic> toJson();

  static AccountOp fromJson(Map<String, dynamic> j) {
    switch (j['kind']) {
      case 'task':
        return TaskOp.fromJson(j);
      case 'draft':
        return DraftOp.fromJson(j);
      case 'batchDraft':
        return BatchDraftOp(jsStr(j['id']), asMap(j['section']) ?? const {});
      case 'recLog':
        return RecLogOp(RecLogRequest.fromJson(asMap(j['request']) ?? const {}));
      case 'batch':
        return BatchLogOp(LogRequest.fromJson(asMap(j['request']) ?? const {}));
      case 'setting':
        return SettingOp.fromJson(j);
      case 'edit':
        return EditOp.fromJson(j);
      case 'tool':
        return ToolOp(jsStr(j['id']), jsStr(j['tool']), asMap(j['value']) ?? const {});
      case 'appTime':
        return AppTimeOp.fromJson(j);
      case 'xpEvent':
        return XpEventOp(ActionXpOp.fromJson(j));
      case 'away':
        return AwayXpOp(from: jsNum(j['from']).toInt(), to: jsNum(j['to']).toInt());
      default:
        // Beta 12 stored bare Batch Log requests.
        return BatchLogOp(LogRequest.fromJson(j));
    }
  }
}

/// A Batch Log (the Log sheet outside recommendations).
class BatchLogOp extends AccountOp {
  BatchLogOp(this.request);
  final LogRequest request;

  @override
  String get id => request.groupId;
  @override
  String get kind => 'batch';
  @override
  bool apply(Map<String, dynamic> state) => applyLog(state, request).applied;
  @override
  Map<String, dynamic> toJson() => {'kind': kind, 'request': request.toJson()};
}

/// Logging a MediaFlow Recommends task.
class RecLogOp extends AccountOp {
  RecLogOp(this.request);
  final RecLogRequest request;

  @override
  String get id => request.groupId;
  @override
  String get kind => 'recLog';
  @override
  bool apply(Map<String, dynamic> state) {
    final outcome = applyRecLog(state, request);
    rejection = outcome.applied || outcome.alreadyApplied ? null : (outcome.error ?? 'The log no longer matches your account.');
    return outcome.applied;
  }
  @override
  Map<String, dynamic> toJson() => {'kind': kind, 'request': request.toJson()};
}

/// The open logging form (shared with the website through resumeStateV285).
class DraftOp extends AccountOp {
  DraftOp(this.id, this.logging);
  @override
  final String id;
  final Map<String, dynamic> logging;

  @override
  String get kind => 'draft';
  @override
  bool apply(Map<String, dynamic> state) => applyLoggingSection(state, logging);
  @override
  Map<String, dynamic> toJson() => {'kind': kind, 'id': id, 'logging': logging};

  static DraftOp fromJson(Map<String, dynamic> j) => DraftOp(jsStr(j['id']), asMap(j['logging']) ?? const {});
}

/// Website v577: the Batch Log draft (resumeStateV285.mf577Batch), newer wins.
class BatchDraftOp extends AccountOp {
  BatchDraftOp(this.id, this.section);
  @override
  final String id;
  final Map<String, dynamic> section;

  @override
  String get kind => 'batchDraft';
  @override
  bool apply(Map<String, dynamic> state) => applyBatchSection(state, section);
  @override
  Map<String, dynamic> toJson() => {'kind': kind, 'id': id, 'section': section};
}

/// MediaFlow Recommends session actions.
enum TaskAction { start, reroll, skip, end, rerollTitle }

class TaskOp extends AccountOp {
  TaskOp({
    required this.id,
    required this.action,
    required this.createdAt,
    this.expectedTaskId,
    this.resultTask,
    this.historyEntry,
    this.skipSessionId,
  });

  @override
  final String id;
  final TaskAction action;
  final int createdAt;

  /// The task the user was looking at (null for start).
  final String? expectedTaskId;
  final Map<String, dynamic>? resultTask;
  final Map<String, dynamic>? historyEntry;
  final String? skipSessionId;

  @override
  String get kind => 'task';

  /// Performs [action] on [state] (the device's copy) and returns the op that
  /// repeats it, or null if there was nothing to do.
  static TaskOp? perform(Map<String, dynamic> state, TaskAction action, {int? now, RandomSource? random}) {
    final t = now ?? DateTime.now().millisecondsSinceEpoch;
    final current = asMap(state['currentTask']);
    final expected = current == null ? null : jsStr(current['id']);
    final r = Recommender(state, now: t, random: random);
    final l = Leveling(state);
    TaskActionResult result;
    String? skipId;
    switch (action) {
      case TaskAction.start:
        result = startSession(state, r);
      case TaskAction.reroll:
        result = rotateTask(state, r);
      case TaskAction.skip:
        skipId = mediaFlowUid(t);
        result = skipTask(state, r, l, skipSessionId: skipId);
      case TaskAction.end:
        result = endSession(state, r);
      case TaskAction.rerollTitle:
        result = rerollTitle(state, r);
    }
    if (!result.changed) return null;
    if (action != TaskAction.start && action != TaskAction.rerollTitle) clearLoggingDraft(state, t);
    state['savedAt'] = t;
    final task = asMap(state['currentTask']);
    Map<String, dynamic>? entry;
    if (action == TaskAction.rerollTitle && task != null) {
      final history = asList(task['v180RecommendationHistory']);
      entry = history.isEmpty ? null : asMap(history.last);
    }
    return TaskOp(
      id: mediaFlowUid(t),
      action: action,
      createdAt: t,
      expectedTaskId: expected,
      resultTask: task == null ? null : jsonDecode(jsonEncode(task)) as Map<String, dynamic>,
      historyEntry: entry,
      skipSessionId: skipId,
    );
  }

  @override
  bool apply(Map<String, dynamic> state) {
    final current = asMap(state['currentTask']);
    final currentId = current == null ? null : jsStr(current['id']);
    final r = Recommender(state, now: createdAt);
    switch (action) {
      case TaskAction.start:
        if (state['sessionActive'] == true && current != null) return false;
        startSession(state, r, presetTask: _copy(resultTask));
      case TaskAction.reroll:
        if (currentId == null || currentId != expectedTaskId) return false;
        rotateTask(state, r, presetTask: _copy(resultTask));
        clearLoggingDraft(state, createdAt);
      case TaskAction.skip:
        if (currentId == null || currentId != expectedTaskId) return false;
        if (asList(state['sessions']).any((s) => jsStr(asMap(s)?['id']) == skipSessionId)) return false;
        skipTask(state, r, Leveling(state), presetTask: _copy(resultTask), skipSessionId: skipSessionId);
        clearLoggingDraft(state, createdAt);
      case TaskAction.end:
        if (state['sessionActive'] != true && current == null) return false;
        endSession(state, r);
        clearLoggingDraft(state, createdAt);
      case TaskAction.rerollTitle:
        if (currentId == null || currentId != expectedTaskId || historyEntry == null) return false;
        final history = asList(current!['v180RecommendationHistory']);
        if (history.any((h) => jsNum(asMap(h)?['shownAt']) == jsNum(historyEntry!['shownAt']) &&
            jsStr(asMap(h)?['libraryId']) == jsStr(historyEntry!['libraryId']))) {
          return false;
        }
        if (!rerollTitle(state, r, presetEntry: historyEntry).changed) return false;
    }
    state['savedAt'] = createdAt;
    return true;
  }

  static Map<String, dynamic>? _copy(Map<String, dynamic>? m) =>
      m == null ? null : jsonDecode(jsonEncode(m)) as Map<String, dynamic>;

  @override
  Map<String, dynamic> toJson() => {
        'kind': kind,
        'id': id,
        'action': action.name,
        'createdAt': createdAt,
        'expectedTaskId': expectedTaskId,
        'resultTask': resultTask,
        'historyEntry': historyEntry,
        'skipSessionId': skipSessionId,
      };

  static TaskOp fromJson(Map<String, dynamic> j) => TaskOp(
        id: jsStr(j['id']),
        action: TaskAction.values.firstWhere((a) => a.name == j['action'], orElse: () => TaskAction.start),
        createdAt: jsNum(j['createdAt']).toInt(),
        expectedTaskId: j['expectedTaskId'] is String ? j['expectedTaskId'] as String : null,
        resultTask: asMap(j['resultTask']),
        historyEntry: asMap(j['historyEntry']),
        skipSessionId: j['skipSessionId'] is String ? j['skipSessionId'] as String : null,
      );
}


/// Sets one account setting (`state.settings[path...]`), like the website's
/// Settings controls. Replays keep the newest value: a value saved on another
/// device after this change was made is not overwritten.
class SettingOp extends AccountOp {
  SettingOp({required this.id, required this.path, required this.value, required this.createdAt, this.previous});

  @override
  final String id;
  final List<String> path;
  final Object? value;
  final Object? previous;
  final int createdAt;

  @override
  String get kind => 'setting';

  static SettingOp create(Map<String, dynamic> state, List<String> path, Object? value, {int? now}) {
    final t = now ?? DateTime.now().millisecondsSinceEpoch;
    return SettingOp(id: mediaFlowUid(t), path: path, value: value, createdAt: t, previous: readSetting(state, path));
  }

  static Object? readSetting(Map<String, dynamic> state, List<String> path) {
    Object? cur = state['settings'];
    for (final k in path) {
      final m = asMap(cur);
      if (m == null) return null;
      cur = m[k];
    }
    return cur;
  }

  @override
  bool apply(Map<String, dynamic> state) {
    final current = readSetting(state, path);
    if (jsonEncode(current) == jsonEncode(value)) return false;
    // Someone changed it after this device did (newest change wins).
    if (jsonEncode(current) != jsonEncode(previous) && jsNum(state['savedAt']) > createdAt) return false;
    var node = asMap(state['settings']);
    if (node == null) {
      node = <String, dynamic>{};
      state['settings'] = node;
    }
    for (var i = 0; i < path.length - 1; i++) {
      var next = asMap(node![path[i]]);
      if (next == null) {
        next = <String, dynamic>{};
        node[path[i]] = next;
      }
      node = next;
    }
    node![path.last] = jsonDecode(jsonEncode(value));
    state['savedAt'] = createdAt > jsNum(state['savedAt']) ? createdAt : state['savedAt'];
    return true;
  }

  @override
  Map<String, dynamic> toJson() =>
      {'kind': kind, 'id': id, 'path': path, 'value': value, 'previous': previous, 'createdAt': createdAt};

  static SettingOp fromJson(Map<String, dynamic> j) => SettingOp(
        id: jsStr(j['id']),
        path: asList(j['path']).map(jsStr).toList(),
        value: j['value'],
        previous: j['previous'],
        createdAt: jsNum(j['createdAt']).toInt(),
      );
}

/// Stopwatch / Runtime Calculator state (`dashboardToolsV257`); the newest
/// `modifiedAt` wins, as in the website's own merge.
class ToolOp extends AccountOp {
  ToolOp(this.id, this.tool, this.value);

  @override
  final String id;
  final String tool; // 'stopwatch' | 'runtimeCalculator'
  final Map<String, dynamic> value;

  @override
  String get kind => 'tool';

  @override
  bool apply(Map<String, dynamic> state) => writeTool(state, tool, value);

  @override
  Map<String, dynamic> toJson() => {'kind': kind, 'id': id, 'tool': tool, 'value': value};
}

/// Time spent in the app (website v561 `xpLedger.v561AppTimeDays`): counted like
/// the website's active time (v334 `v334EarnTime`: XP per minute × today's
/// streak multiplier), kept apart from the website's own time so neither side
/// overwrites the other, with a per-platform split for Statistics. Replayed
/// once on the newest cloud copy, so two devices' minutes add up.
class AppTimeOp extends AccountOp {
  AppTimeOp({required this.id, required this.day, required this.ms, required this.platform, required this.at});

  @override
  final String id;
  final String day, platform;
  final int ms, at;

  @override
  String get kind => 'appTime';

  static const ledgerKey = 'v561AppTimeDays';

  @override
  bool apply(Map<String, dynamic> state) {
    if (ms <= 0 || !isIsoDay(day)) return false;
    var ledger = asMap(state['xpLedger']);
    if (ledger == null) {
      ledger = <String, dynamic>{};
      state['xpLedger'] = ledger;
    }
    var days = asMap(ledger[ledgerKey]);
    if (days == null || ledger[ledgerKey] is List) {
      days = <String, dynamic>{};
      ledger[ledgerKey] = days;
    }
    final old = asMap(days[day]);
    final row = <String, dynamic>{...?old};
    final l = Leveling(state);
    final streak = prospectiveTodayStreak(asList(state['sessions']), at);
    final multiplier = l.streakMultiplier(streak);
    final exact = jsNum(row['exactXP']) + (l.enabled ? (ms / 60000) * l.reward('activeTimeXPPerMinute') * multiplier : 0);
    row['ms'] = jsOut(jsNum(row['ms']) + ms);
    row['exactXP'] = jsOut(exact);
    row['xp'] = (exact + 1e-8).floor();
    row['streak'] = streak;
    row['multiplier'] = jsOut(multiplier);
    row['updatedAt'] = at > jsNum(row['updatedAt']) ? at : jsOut(jsNum(row['updatedAt']));
    final platforms = <String, dynamic>{...?asMap(row['platforms'])};
    platforms[platform] = jsOut(jsNum(platforms[platform]) + ms);
    row['platforms'] = platforms;
    days[day] = row;
    // Website v565: MediaFlow was open until now, so this time is never
    // credited again as away time (the newest last-seen wins, as on the website).
    if (at > jsNum(ledger['mf565LastSeenAt'])) ledger['mf565LastSeenAt'] = at;
    return true;
  }

  @override
  Map<String, dynamic> toJson() => {'kind': kind, 'id': id, 'day': day, 'ms': ms, 'platform': platform, 'at': at};

  static AppTimeOp fromJson(Map<String, dynamic> j) => AppTimeOp(
        id: jsStr(j['id']),
        day: jsStr(j['day']),
        ms: jsNum(j['ms']).toInt(),
        platform: jsStr(j['platform']),
        at: jsNum(j['at']).toInt(),
      );
}

/// One XP event (website v565: XP for every action, background work, away
/// time), written to the shared v348 ledger under a fixed key.
class XpEventOp extends AccountOp {
  XpEventOp(this.event);
  final ActionXpOp event;

  @override
  String get id => event.key;
  @override
  String get kind => 'xpEvent';

  @override
  bool apply(Map<String, dynamic> state) => event.write(state) > 0;

  @override
  Map<String, dynamic> toJson() => {'kind': kind, 'id': id, ...event.toJson()};
}

/// Away XP (website v565 mf565CreditAway): time when MediaFlow wasn't open
/// anywhere earns XP at its own rate (settings.leveling.mf565AwayXPPerMinute;
/// default a quarter of the active-time rate), times the day-streak
/// multiplier. Each stretch is stored under its start, so the same time is
/// never credited twice — not by two devices, not as both away and active.
class AwayXpOp extends AccountOp {
  AwayXpOp({required this.from, required this.to});
  final int from, to;

  static const minGap = 15 * 60 * 1000;

  @override
  String get id => 'mf565Away:$from';
  @override
  String get kind => 'away';

  static double rate(Map<String, dynamic> state) {
    final l = Leveling(state);
    final v = asMap(asMap(state['settings'])?['leveling'])?['mf565AwayXPPerMinute'];
    // Missing means the default (Number(undefined) is NaN on the website, not 0).
    final raw = v == null ? null : jsNumOrNull(v);
    if (raw != null && raw.isFinite && raw >= 0) return raw > 100000 ? 100000.0 : raw;
    final active = l.reward('activeTimeXPPerMinute');
    return active > 0 ? active / 4 : 0;
  }

  @override
  bool apply(Map<String, dynamic> state) {
    var ledger = asMap(state['xpLedger']);
    if (ledger == null) {
      ledger = <String, dynamic>{};
      state['xpLedger'] = ledger;
    }
    var changed = false;
    // Someone (another device, the website) was seen after this stretch began: not away.
    final seen = jsNum(ledger['mf565LastSeenAt']);
    if (seen > from) {
      if (to > seen) {
        ledger['mf565LastSeenAt'] = to;
        changed = true;
      }
      return changed;
    }
    var away = asMap(ledger['mf565Away']);
    if (away == null) {
      away = <String, dynamic>{};
      ledger['mf565Away'] = away;
    }
    final gap = to - from;
    if (gap >= minGap && away['$from'] == null) {
      final minutes = gap ~/ 60000, r = rate(state);
      var xp = 0.0;
      if (r > 0 && Leveling(state).enabled) {
        xp = ActionXpOp(key: id, kind: 'mf565Away', base: minutes * r, source: 'Away time',
                details: '${fmtThousands(minutes)} min while MediaFlow was closed', at: to)
            .write(state);
      }
      away['$from'] = <String, dynamic>{'from': from, 'to': to, 'ms': gap, 'xp': jsOut(xp)};
      changed = true;
    }
    if (to > jsNum(ledger['mf565LastSeenAt'])) {
      ledger['mf565LastSeenAt'] = to;
      changed = true;
    }
    return changed;
  }

  @override
  Map<String, dynamic> toJson() => {'kind': kind, 'id': id, 'from': from, 'to': to};
}

/// `toLocaleString()` for whole numbers in en-US (1,234).
String fmtThousands(int n) => n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
