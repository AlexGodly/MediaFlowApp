// Changes made on this device, kept until they reach the cloud. Each one can be
// replayed on a newer cloud copy: ids and random results are fixed when the
// change is made, and replaying something already present changes nothing.

import 'dart:convert';

import '../logic/leveling.dart';
import '../logic/log_engine.dart';
import '../logic/rec_submit.dart';
import '../logic/recommend.dart';
import '../logic/resume.dart';
import '../util/js.dart';

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
      case 'recLog':
        return RecLogOp(RecLogRequest.fromJson(asMap(j['request']) ?? const {}));
      case 'batch':
        return BatchLogOp(LogRequest.fromJson(asMap(j['request']) ?? const {}));
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
