// Logging a MediaFlow Recommends task = the website's App.submitLog (v554) with
// every wrapper that changes the account, applied in the website's order:
//
//   v400 bulk unit stamps → v394 custom runtime split → v369 per-unit checks
//   → v287 Collection traversal → v252 season capture → v179 progress recompute
//   → [mfActivity snapshot → BASE submitLog (sessions, System Respect XP,
//      Library progress + persistLibrary hooks, next task) → activity entry]
//   → v120 logged-completion XP → v121 repeat XP → v137 start dates
//   → v252 per-season progress → v369 exact seconds + contiguous unit progress
//   → mf553 reroll-title bonus → draft cleared → v149 streak annotations.
//
// Verified against fixtures recorded from the real website
// (test/recommendation_golden_test.dart, tool/website_reference/).

import 'dart:convert';
import 'dart:math' as math;

import '../state/models.dart';
import '../util/js.dart';
import 'leveling.dart';
import 'library_hooks.dart';
import 'log_draft.dart';
import 'log_engine.dart';
import 'recommend.dart';
import 'resume.dart';

T _clone<T>(T value) => jsonDecode(jsonEncode(value)) as T;

/// A recommendation log, with every id fixed up front so it can be replayed on
/// a newer cloud copy without creating duplicates.
class RecLogRequest {
  RecLogRequest({
    required this.task,
    required this.logDraft,
    required this.createdAt,
    required this.sessionIds,
    required this.groupId,
    required this.activityId,
    required this.eventId,
    required this.newTitleIds,
    this.nextTask,
  });

  factory RecLogRequest.create(Map<String, dynamic> task, Map<String, dynamic> logDraft, {int? now}) {
    final t = now ?? DateTime.now().millisecondsSinceEpoch;
    final n = asList(logDraft['entries']).length;
    return RecLogRequest(
      task: _clone(task),
      logDraft: _clone(logDraft),
      createdAt: t,
      sessionIds: [for (var i = 0; i < n + 2; i++) mediaFlowUid(t)],
      groupId: mediaFlowUid(t),
      activityId: mediaFlowUid(t),
      eventId: mediaFlowUid(t),
      newTitleIds: [for (var i = 0; i < n; i++) mediaFlowUid(t)],
    );
  }

  final Map<String, dynamic> task;
  final Map<String, dynamic> logDraft;
  final int createdAt;
  final List<String> sessionIds;
  final String groupId;
  final String activityId;
  final String eventId;
  final List<String> newTitleIds;

  /// The task that follows, generated once on the device so replays agree.
  Map<String, dynamic>? nextTask;

  bool get itemized => logDraft['v369Interface'] == 'itemized';
  String get commitId => itemized ? jsStr(logDraft['v369CommitId']) : '';

  Map<String, dynamic> toJson() => {
        'task': task,
        'logDraft': logDraft,
        'createdAt': createdAt,
        'sessionIds': sessionIds,
        'groupId': groupId,
        'activityId': activityId,
        'eventId': eventId,
        'newTitleIds': newTitleIds,
        'nextTask': nextTask,
      };

  static RecLogRequest fromJson(Map<String, dynamic> j) => RecLogRequest(
        task: asMap(j['task']) ?? <String, dynamic>{},
        logDraft: asMap(j['logDraft']) ?? <String, dynamic>{},
        createdAt: jsNum(j['createdAt']).toInt(),
        sessionIds: asList(j['sessionIds']).map(jsStr).toList(),
        groupId: jsStr(j['groupId']),
        activityId: jsStr(j['activityId']),
        eventId: jsStr(j['eventId']),
        newTitleIds: asList(j['newTitleIds']).map(jsStr).toList(),
        nextTask: asMap(j['nextTask']),
      );
}

class RecLogOutcome {
  RecLogOutcome({required this.applied, this.alreadyApplied = false, this.error});
  final bool applied;
  final bool alreadyApplied;
  final String? error;
  final List<String> sessionIds = [];
  final List<String> completed = [];
  double xp = 0;
  double respectXP = 0;
  bool respected = false;
  Map<String, dynamic>? nextTask;
}

/// Applies [req] to [state] in place, exactly as the website's submit would.
RecLogOutcome applyRecLog(Map<String, dynamic> state, RecLogRequest req, {RandomSource? random}) {
  final sessions = listIn(state, 'sessions');
  final ids = req.sessionIds.toSet();
  final commit = req.commitId;
  for (final raw in sessions) {
    final s = asMap(raw);
    if (s == null) continue;
    if (ids.contains(jsStr(s['id']))) return RecLogOutcome(applied: false, alreadyApplied: true);
    if (commit.isNotEmpty &&
        jsStr(s['sessionGroupId'] ?? s['v369CommitId']) == commit &&
        (jsTruthy(s['v369Itemized']) || jsTruthy(s['v369CommitId']))) {
      return RecLogOutcome(applied: false, alreadyApplied: true);
    }
  }

  final now = req.createdAt;
  final l = Leveling(state);
  final task = _clone(req.task);
  final draft = _clone(req.logDraft);
  var idSeq = 0;
  String nextId() => idSeq < req.sessionIds.length ? req.sessionIds[idSeq++] : '${req.eventId}_s${idSeq++}';
  var metaSeq = 0;
  String metaUid() => '${req.eventId}_${metaSeq++}';
  final tracker = LibraryTracker(state);
  final r = Recommender(state, now: now, random: random);

  // ---- new typed titles (the website adds them while the form is open) -------
  final assignedId = jsStr(task['categoryId']);
  final entriesRaw = asList(draft['entries']);
  for (var k = 0; k < entriesRaw.length; k++) {
    final e = asMap(entriesRaw[k]);
    if (e == null || jsTruthy(e['libraryId'])) continue;
    final title = jsStr(e['title']).trim();
    if (title.isEmpty) continue;
    final editor = LogDraftEditor(state: state, task: task, logDraft: draft, entryDraft: {}, clock: () => now);
    var match = editor.findLibraryMatch(assignedId, title);
    if (match == null) {
      final key = cleanTitle(title).toLowerCase();
      match = editor.library.where((i) => i['status'] != 'dropped' && cleanTitle(i['title']).toLowerCase() == key).firstOrNull;
    }
    if (match == null) {
      final id = k < req.newTitleIds.length ? req.newTitleIds[k] : '${req.eventId}_n$k';
      match = <String, dynamic>{
        'id': id, 'title': title, 'categoryId': assignedId, 'progress': 0, 'total': null, 'status': 'active',
        'priority': 'medium', 'estimatedMinutes': null, 'tags': ['manual'], 'source': 'manual',
        'createdAt': now, 'completedAt': null,
      };
      listIn(state, 'library').add(match);
      _awardLibraryAddition(state, l, id, now, metaUid);
      tracker.save(state, l, now, metaUid);
    }
    e['libraryId'] = match['id'];
    final isRepeat = match['status'] == 'completed' ||
        (jsNum(match['total']) > 0 && jsNum(match['progress']) >= jsNum(match['total']));
    e['isRepeat'] = e['isRepeat'] == true || isRepeat;
  }
  final editor = LogDraftEditor(state: state, task: task, logDraft: draft, entryDraft: {}, clock: () => now);
  final itemized = editor.itemized;

  // ---- mf553: reroll-title bonus forecast (before anything changes) --------------
  final reroll = _rerollUnitRows(state, task, draft, editor, l, r);

  // ---- v400: Progress Reached / Amount Consumed dates on their units --------------
  if (itemized) {
    for (var i = 0; i < editor.entries.length; i++) {
      final e = editor.entries[i];
      final m = LogDraftEditor.method(e);
      if (m == 'unit') continue;
      final stamp = editor.bulkStamp(e, m);
      for (final u in editor.relevant(e, editor.item(e['libraryId'])).units) {
        u['loggedAt'] = stamp;
        u['v369UpdatedAt'] = now;
      }
    }
    // ---- v394: split a custom total runtime across the units ------------------------
    for (final e in editor.entries) {
      final units = editor.units(e);
      final total = jsNumFromKey(e, 'v394RuntimeSeconds');
      if (e['v394RuntimeManual'] != true || units.isEmpty || total == null || !total.isFinite || total < 0) continue;
      final seconds = jsRound(total).toInt();
      final q = seconds ~/ units.length, rem = seconds % units.length;
      for (var i = 0; i < units.length; i++) {
        units[i]['durationSeconds'] = q + (i < rem ? 1 : 0);
        units[i].remove('minutes');
        units[i]['v369UpdatedAt'] = now;
      }
      e['v394RuntimeManual'] = false;
      e['v394RuntimeSeconds'] = seconds;
    }
  }

  final error = editor.validate();
  if (error != null) return RecLogOutcome(applied: false, error: error);

  // ---- v369: snapshot titles and units ---------------------------------------------
  final baseLibrary = <String, ({Map<String, dynamic> item, double progress, List<Map<String, dynamic>> seasons})>{};
  final capturedUnits = <String, ({List<Map<String, dynamic>> units, bool repeat})>{};
  if (itemized) {
    if (!jsTruthy(draft['v369CommitId'])) draft['v369CommitId'] = req.groupId;
    editor.sync369();
    for (final e in editor.entries) {
      final item = editor.item(e['libraryId'])!;
      baseLibrary[jsStr(item['id'])] = (
        item: item,
        progress: jsNum(item['progress']),
        seasons: LogDraftEditor.seasonsOf(item).map((s) => Map<String, dynamic>.from(s)).toList(),
      );
      capturedUnits[jsStr(e['libraryId'])] =
          (units: editor.units(e).map((u) => Map<String, dynamic>.from(u)).toList(), repeat: e['isRepeat'] == true);
    }
  }

  // ---- v287: Collection traversal ------------------------------------------------------
  final source = asMap(task['v287OrderSource']) ?? r.orderSourceForTask(task);
  final recommendedId = jsStr(task['libraryId']);
  var traversed = false;
  if (source != null && source['type'] == 'collection' && jsTruthy(source['assignmentId']) && recommendedId.isNotEmpty &&
      editor.entries.any((e) => _consumes(e, recommendedId))) {
    final plan = mapIn(state, 'orderPlan');
    final list = asList(plan['collectionAssignments']);
    for (var i = 0; i < list.length; i++) {
      final a = asMap(list[i]);
      if (a == null || jsStr(a['id']) != jsStr(source['assignmentId'])) continue;
      final before = asList(a['traversedTitleIds']).map(jsStr).toList();
      if (!before.contains(recommendedId)) {
        final next = Map<String, dynamic>.from(a)
          ..['traversedTitleIds'] = [...before, recommendedId]
          ..['modifiedAt'] = now;
        plan['collectionAssignments'] = [for (var j = 0; j < list.length; j++) j == i ? next : list[j]];
        plan['modifiedAt'] = now;
        traversed = true;
      }
      break;
    }
  }

  // ---- v252: season choices for the History rows ------------------------------------
  final captured = [
    for (final e in editor.entries)
      (
        libraryId: jsStr(e['libraryId']),
        repeat: e['isRepeat'] == true,
        useSeason: e['v252UseSeasonView'] == true && jsTruthy(e['v252SeasonId']),
        seasonId: e['v252SeasonId'],
        seasonNumber: e['v252SeasonNumber'],
        seasonName: jsStr(e['v252SeasonName']),
        seasonEpisode: e['v252SeasonEpisode'] == null ? null : jsOut(_v252Num(e['v252SeasonEpisode'])),
        globalEnd: e['v179EndProgress'] == null ? null : jsOut(jsNum(e['v179EndProgress'])),
      ),
  ];

  // ---- v179: progress mode = final progress reached ------------------------------------
  if (editor.mode == 'progress') {
    for (final e in editor.entries) {
      final item = editor.item(e['libraryId']);
      if (item == null) continue;
      final s = jsNumFromKey(e, 'v179StartProgress');
      final start = s != null && s.isFinite ? math.max(0.0, s) : LogDraftEditor.startProgress(item);
      final end = LogDraftEditor.clampEnd(item, e['v179EndProgress']);
      e['v179StartProgress'] = jsOut(start);
      e['v179EndProgress'] = jsOut(end);
      e['qty'] = jsOut(LogDraftEditor.calculatedQty(item, start, end));
    }
    draft['updateLibrary'] = true;
    editor.syncSingle();
  }

  // ---- snapshots for v120 / mfActivity ------------------------------------------------------
  final wasCompleted = <String, bool>{for (final i in editor.library) jsStr(i['id']): isCompletedItem(i)};
  final libraryBefore = _librarySnapshot(state);
  final ledgerBefore = _ledgerTotals(state);
  final completedBefore = editor.library.where(isCompletedItem).length;
  final libraryCountBefore = editor.library.length;
  final sessionCountBefore = sessions.length;

  // ==== BASE submitLog ======================================================================
  final assignedCat = r.getCategory(assignedId);
  final entries = editor.entries;
  final enteredAmount = jsNum(draft['amount']).clamp(0, 999999).toDouble();
  final totalMinutes = jsNum(draft['minutes']).clamp(0, 999999).toDouble();
  final extra = jsStr(draft['note']).trim();
  final groupId = itemized ? jsStr(draft['v369CommitId']) : req.groupId;
  final targetMid = task['targetMid'];

  final groups = <String, ({Map<String, dynamic> cat, List<Map<String, dynamic>> entries, List<double> sums})>{};
  if (entries.isNotEmpty) {
    for (final e in entries) {
      final item = editor.item(e['libraryId']);
      final actual = item != null ? r.getCategory(jsStr(item['categoryId'])) : assignedCat;
      final qty = math.max(0.0, jsNum(e['qty']));
      final g = groups.putIfAbsent(jsStr(actual['id']), () => (cat: actual, entries: <Map<String, dynamic>>[], sums: [0.0, 0.0]));
      g.entries.add(e);
      g.sums[0] += qty;
      g.sums[1] += qty * math.max(1.0, jsNum(actual['minutesPerUnit']));
    }
  } else if (enteredAmount > 0) {
    groups[jsStr(assignedCat['id'])] = (
      cat: assignedCat,
      entries: <Map<String, dynamic>>[],
      sums: [enteredAmount, math.max(1.0, enteredAmount * math.max(1.0, jsNum(assignedCat['minutesPerUnit'])))],
    );
  }
  final grouped = groups.values.toList();
  var totalWeight = grouped.fold<double>(0, (n, g) => n + g.sums[1]);
  if (totalWeight == 0) totalWeight = 1;
  var minutesLeft = totalMinutes;
  final today = isoDateUtc(now);
  final added = <Map<String, dynamic>>[];
  for (var index = 0; index < grouped.length; index++) {
    final g = grouped[index];
    final cat = g.cat;
    final isAssigned = jsStr(cat['id']) == jsStr(assignedCat['id']);
    final amount = g.sums[0];
    final double groupMinutes = itemized
        ? g.entries.fold<double>(0, (n, e) => n + editor.units(e).fold<double>(0, (t, u) => t + LogDraftEditor.unitSeconds(u))) / 60
        : (index == grouped.length - 1
            ? minutesLeft
            : math.min(minutesLeft, jsRound(totalMinutes * (g.sums[1] / totalWeight))));
    minutesLeft = math.max(0, minutesLeft - groupMinutes);
    var status = 'logged';
    if (isAssigned) {
      final mid = jsNum(targetMid);
      status = amount < mid ? 'partial' : (amount > mid ? 'over' : 'complete');
    }
    final health = categoryStatusOf(cat, sessions, now);
    final xp = l.consumptionXP(Category(cat), amount, groupMinutes, health);
    final note = [_entriesNote(g.entries), extra].where((x) => x.isNotEmpty).join(' — ');
    final session = <String, dynamic>{
      'id': nextId(),
      'timestamp': now,
      'date': today,
      'categoryId': cat['id'],
      'assignedCategoryId': assignedCat['id'],
      'assignedTargetAmount': targetMid,
      'sessionGroupId': groupId,
      'followedAssignedCategory': isAssigned,
      'targetAmount': isAssigned ? targetMid : jsOut(amount),
      'actualAmount': jsOut(amount),
      'minutes': jsOut(groupMinutes),
      'note': note,
      'status': status,
      'unit': cat['unit'],
      'xp': jsOut(xp),
      'healthStatus': health,
      'source': 'recommendation',
      if (itemized) ...{
        'v369Itemized': true,
        'v369CommitId': groupId,
        'v369DurationSeconds': jsOut(jsRound(groupMinutes * 60)),
      },
      'titles': [
        for (final e in g.entries)
          () {
            final units = itemized ? editor.units(e).map((u) => Map<String, dynamic>.from(u)).toList() : <Map<String, dynamic>>[];
            final stamp = jsNum(e['loggedAt']);
            final valid = stamp.isFinite && stamp >= 946684800000 && stamp <= now + 86400000;
            return <String, dynamic>{
              'title': cleanTitle(e['title']),
              'libraryId': jsTruthy(e['libraryId']) ? e['libraryId'] : null,
              'qty': jsOut(jsNum(e['qty'])),
              'repeat': e['isRepeat'] == true,
              'loggedAt': units.isNotEmpty
                  ? jsOut(units.map((u) => jsNum(u['loggedAt'])).reduce(math.min))
                  : (valid ? jsOut(stamp) : now),
              if (itemized) ...{
                'v369Itemized': true,
                'v369Units': units,
                'v369DurationSeconds': jsOut(units.fold<double>(0, (n, u) => n + LogDraftEditor.unitSeconds(u))),
              },
            };
          }(),
      ],
    };
    sessions.add(session);
    added.add(session);
  }
  if (!grouped.any((g) => jsStr(g.cat['id']) == jsStr(assignedCat['id']) && g.sums[0] > 0)) {
    final skipped = <String, dynamic>{
      'id': nextId(), 'timestamp': now, 'date': today, 'categoryId': assignedCat['id'],
      'assignedCategoryId': assignedCat['id'], 'assignedTargetAmount': targetMid, 'sessionGroupId': groupId,
      'followedAssignedCategory': false, 'targetAmount': targetMid, 'actualAmount': 0, 'minutes': 0,
      'note': 'Recommendation not followed', 'status': 'skipped', 'unit': assignedCat['unit'], 'xp': 0,
      'healthStatus': categoryStatusOf(assignedCat, sessions, now), 'source': 'recommendation', 'titles': <dynamic>[],
    };
    sessions.add(skipped);
    added.add(skipped);
  }

  final outcome = RecLogOutcome(applied: true);
  for (final s in added) {
    outcome.sessionIds.add(jsStr(s['id']));
  }

  // v165/v180: System Respect XP.
  final respect = _applyRespectReward(state, r, l, task, entries, added, now);
  outcome.respected = respect.respected;
  outcome.respectXP = respect.bonus;

  // Library progress.
  if (draft['updateLibrary'] == true) {
    for (final e in entries) {
      final item = jsTruthy(e['libraryId']) ? editor.item(e['libraryId']) : editor.findLibraryMatch(jsStr(assignedCat['id']), jsStr(e['title']));
      if (item == null || e['isRepeat'] == true) continue;
      double progress;
      if (itemized && e['v369Units'] is List) {
        progress = editor.projectedProgress(item, e);
      } else {
        progress = jsNum(item['progress']) + jsNum(e['qty']);
      }
      final hasTotal = jsTruthy(item['total']);
      final total = jsNum(item['total']);
      if (hasTotal) progress = math.min(progress, total);
      item['progress'] = jsOut(progress);
      if (hasTotal && progress >= total && item['status'] != 'dropped') {
        item['status'] = 'completed';
        if (!jsTruthy(item['completedAt'])) item['completedAt'] = now;
        final timeline = listIn(state, 'completionTimeline');
        if (!timeline.any((x) => jsStr(asMap(x)?['libraryId']) == jsStr(item['id']))) {
          timeline.add(<String, dynamic>{
            'libraryId': item['id'], 'title': cleanTitle(item['title']), 'categoryId': item['categoryId'],
            'completedAt': item['completedAt'],
          });
        }
      } else if (item['status'] == 'planned') {
        item['status'] = 'active';
      }
    }
    tracker.save(state, l, now, metaUid);
  }

  // Next task.
  final consumed = grouped.where((g) => g.sums[0] > 0).map((g) => jsStr(g.cat['id'])).toList();
  final next = req.nextTask != null
      ? _clone(req.nextTask!)
      : Recommender(state, now: now, random: random).generateTask(consumed.isNotEmpty ? consumed : [jsStr(assignedCat['id'])]);
  req.nextTask ??= next == null ? null : _clone(next);
  outcome.nextTask = next;
  final current = asMap(state['currentTask']);
  if (current == null || jsStr(current['id']) == jsStr(req.task['id'])) {
    state['currentTask'] = next;
  }

  // ---- mfActivity: the History entry for this log ------------------------------------------
  final lastSession = sessions.isNotEmpty ? asMap(sessions.last) : null;
  final changes = _diffLibrary(libraryBefore, _librarySnapshot(state));
  final changeIds = <String>[];
  for (final c in changes) {
    final id = jsStr(c['id']);
    if (id.isNotEmpty && !changeIds.contains(id)) changeIds.add(id);
  }
  annotateStreakXP(state, l);
  var xpEarned = 0.0;
  for (final s in added) {
    if (s['status'] != 'skipped') xpEarned += jsNum(s['xpWithStreak']);
  }
  final ledgerAfter = _ledgerTotals(state);
  xpEarned += ledgerAfter - ledgerBefore;
  xpEarned += (editor.library.length - libraryCountBefore) * jsRound(l.reward('libraryAdditionXP'));
  xpEarned += (editor.library.where(isCompletedItem).length - completedBefore) * l.completionXP;
  final activity = <String, dynamic>{
    'id': req.activityId,
    'timestamp': now,
    'action': 'Log consumption',
    'detail': lastSession == null ? '' : '${_jsNumText(lastSession['actualAmount'])} ${jsStr(lastSession['unit'])}',
    'changes': changes,
    'titleIds': changeIds,
    'titleSnapshot': changeIds.length == 1
        ? cleanTitle(editor.item(changeIds.first)?['title'] ?? changes.first['title'])
        : '',
    'xpEarned': jsOut(math.max(0, jsRound(xpEarned))),
  };
  final log = listIn(state, 'activityLog');
  log.insert(0, activity);
  if (log.length > 1000) log.removeRange(1000, log.length);

  // ---- v120: XP for titles completed by this log ----------------------------------------------
  var completionBonus = 0.0;
  for (final i in editor.library) {
    final id = jsStr(i['id']);
    if (wasCompleted[id] != false || !isCompletedItem(i)) continue;
    outcome.completed.add(cleanTitle(i['title']));
    if (!l.enabled) continue;
    final ledger = mapIn(ledgerOf(state), 'logCompletions');
    if (!ledger.containsKey(id)) {
      ledger[id] = jsOut(l.loggingCompletionBonusXP);
      completionBonus += l.loggingCompletionBonusXP;
    }
  }
  if (completionBonus > 0) {
    activity['xpEarned'] = jsOut(math.max(0.0, jsNum(activity['xpEarned'])) + completionBonus);
    tracker.save(state, l, now, metaUid);
  }

  // ---- v121: repeat XP --------------------------------------------------------------------------
  final hasRepeat = added.any((s) => asList(s['titles']).any((t) {
        final m = asMap(t);
        if (m == null || jsNum(m['qty']) <= 0) return false;
        if (m['repeat'] == true) return true;
        return asList(m['v369Units']).any((u) => asMap(u)?['isRepeat'] == true);
      }));
  if (hasRepeat) recalculateRepeatXP(state, l);

  // ---- v137: start dates ------------------------------------------------------------------------
  reconcileStarts(state, added, now);
  tracker.save(state, l, now, metaUid);

  // ---- v252: per-season progress + season details on History rows ------------------------------
  var libraryChanged = false;
  for (final row in captured) {
    final item = row.libraryId.isEmpty ? null : editor.item(row.libraryId);
    if (item == null || row.repeat || LogDraftEditor.seasonsOf(item).isEmpty) continue;
    distributeSeasonProgress(item, jsNum(item['progress']), now, req.eventId);
    item['modifiedAt'] = now;
    libraryChanged = true;
  }
  if (libraryChanged) tracker.save(state, l, now, metaUid);
  final byLibrary = {for (final c in captured) if (c.libraryId.isNotEmpty) c.libraryId: c};
  for (final s in added) {
    for (final t in asList(s['titles'])) {
      final m = asMap(t);
      final meta = byLibrary[jsStr(m?['libraryId'])];
      if (m == null || meta == null || !meta.useSeason) continue;
      m['season'] = {
        'id': meta.seasonId, 'number': meta.seasonNumber, 'name': meta.seasonName,
        'episode': meta.seasonEpisode, 'globalEndProgress': meta.globalEnd,
      };
    }
  }

  // ---- v287: Personal Order bookkeeping -----------------------------------------------------------
  if (traversed) {
    r.annotateOrderSource(asMap(state['currentTask']));
    r.reconcileAllQueues();
    mapIn(state, 'orderPlan')['modifiedAt'] = now;
  } else if (recommendedId.isNotEmpty) {
    r.reconcileAllQueues();
  }

  // ---- v369: exact seconds and unit-by-unit progress ------------------------------------------------
  if (itemized) {
    for (final s in added) {
      var exact = 0.0;
      var any = false;
      for (final t in asList(s['titles'])) {
        final m = asMap(t);
        final data = capturedUnits[jsStr(m?['libraryId'])];
        if (m == null || data == null) continue;
        m['v369Units'] = data.units.map((u) => Map<String, dynamic>.from(u)).toList();
        final secs = data.units.fold<double>(0, (n, u) => n + LogDraftEditor.unitSeconds(u));
        m['v369DurationSeconds'] = jsOut(secs);
        m['v369Itemized'] = true;
        m['loggedAt'] = jsOut(data.units.map((u) => jsNum(u['loggedAt'])).fold<double>(double.infinity, math.min));
        exact += secs;
        any = true;
      }
      if (any || asList(s['titles']).any((t) => asMap(t)?['v369Itemized'] == true)) {
        s['v369DurationSeconds'] = jsOut(exact);
        s['minutes'] = jsOut(exact / 60);
      }
    }
    var changed = false;
    for (final entry in baseLibrary.entries) {
      final row = capturedUnits[entry.key];
      if (row == null || row.repeat) continue;
      final base = entry.value;
      final known = [...editor.knownUnits(base.item), ...row.units];
      if (base.seasons.isEmpty) {
        final progress = LogDraftEditor.contiguousProgress(base.progress, known, null, base.item['total']);
        if (jsNum(base.item['progress']) != progress) {
          base.item['progress'] = jsOut(progress);
          if (base.item['status'] == 'completed' && jsNum(base.item['total']) > progress) base.item['status'] = 'active';
          base.item['modifiedAt'] = now;
          changed = true;
        }
        continue;
      }
      for (final season in base.seasons) {
        season['progress'] = jsOut(LogDraftEditor.contiguousProgress(season['progress'], known, jsStr(season['id']), season['total']));
      }
      base.item['seasons'] = base.seasons;
      syncTitleFromSeasons(base.item, req.eventId);
      base.item['modifiedAt'] = now;
      changed = true;
    }
    if (changed) tracker.save(state, l, now, metaUid);
  }

  // ---- mf553: XP for consuming a rerolled title ---------------------------------------------------------
  final consumedRows = added.where((s) => s['status'] != 'skipped' && jsNum(s['actualAmount']) > 0).toList();
  if (reroll.units > 0 && consumedRows.isNotEmpty) {
    final dayMultiplier = l.streakMultiplier(prospectiveTodayStreak(
        [for (var i = 0; i < sessionCountBefore; i++) sessions[i]], now));
    var delta = 0.0;
    for (final s in consumedRows) {
      final row = reroll.byCategory[jsStr(s['categoryId'])];
      if (row == null) continue;
      final rotation = l.rotationMultiplier(jsStr(s['healthStatus']));
      final raw = row * rotation;
      final base = jsNum(s['xp']) + math.max(0.0, jsNum(s['v165RespectBonusXP']));
      final before = jsRound(base * dayMultiplier), after = jsRound((base + raw) * dayMultiplier);
      delta += math.max(0.0, after - before);
    }
    if (delta > 0) {
      final target = consumedRows.where((s) => jsStr(s['categoryId']) == jsStr(task['categoryId'])).firstOrNull ?? consumedRows.first;
      if (target['v553RerollTitleBonusAwarded'] != true) {
        target['xp'] = jsOut(math.max(0.0, jsNum(target['xp']) + delta));
        target['v553RerollTitleBonusAwarded'] = true;
        target['v553RerollTitleBonusXP'] = jsOut(delta);
        target['v553RerollTitleBonusUnits'] = reroll.units;
        target['v553RerollTitleBonusBaseXP'] = jsOut(reroll.baseXP);
        target['v553RerollTitleNames'] = reroll.titles;
      }
    }
  }

  // ---- the form closes: the shared draft is cleared --------------------------------------------------------
  clearLoggingDraft(state, now, submittedCommitId: jsStr(req.logDraft['v369CommitId']), submittedAt: now);

  // ---- v149: streak XP on every log ----------------------------------------------------------------------------
  annotateStreakXP(state, l);
  for (final s in added) {
    outcome.xp += jsNum(s['xpWithStreak']);
  }
  outcome.xp += completionBonus;
  state['savedAt'] = now;
  return outcome;
}

double _v252Num(Object? v) {
  final n = jsNumOrNull(v);
  return n != null && n.isFinite ? math.max(0, jsRound(n)) : 0;
}

bool _consumes(Map<String, dynamic> e, String libraryId) {
  if (jsStr(e['libraryId']) != libraryId) return false;
  if (jsNum(e['qty']) > 0) return true;
  final start = jsNumFromKey(e, 'v179StartProgress'), end = jsNumFromKey(e, 'v179EndProgress');
  return end != null && end.isFinite && (start == null || !start.isFinite || end > start);
}

/// `awardLibraryAdditionXP` as called by the log form for a new typed title.
void _awardLibraryAddition(Map<String, dynamic> state, Leveling l, String id, int now, String Function() uid) {
  final ledger = ledgerOf(state);
  const keys = ['libraryAdditions', 'v334StartedTitles', 'v335FirstEpisodeRewards'];
  final before = {for (final k in keys) k: Map<String, dynamic>.from(mapIn(ledger, k))};
  final lev = asMap(asMap(state['settings'])?['leveling']) ?? const {};
  final disabled = lev['enabled'] == false;
  // v334: a new title added as Active is a genuine first start.
  final started = mapIn(ledger, 'v334StartedTitles');
  if (!started.containsKey(id)) started[id] = disabled ? 0 : jsOut(jsRound(l.reward('firstTitleStartXP')));
  // Base: Library-addition XP.
  final additions = mapIn(ledger, 'libraryAdditions');
  if (!jsTruthy(additions[id])) additions[id] = jsOut(math.max(0, jsRound(l.reward('libraryAdditionXP'))));
  if (!l.enabled) return;
  final meta = mapIn(ledger, 'v348EventMeta');
  for (final k in const ['v348ActionEvents', 'v348LibraryAdditionBonus', 'v348LibraryCompletionBonus']) {
    mapIn(ledger, k);
  }
  final multiplier = awardMultiplier(l, asList(state['sessions']), now);
  const labels = {'libraryAdditions': 'Library · new title', 'v334StartedTitles': 'First title start', 'v335FirstEpisodeRewards': 'First episode'};
  for (final k in keys) {
    final after = mapIn(ledger, k);
    for (final e in after.entries.toList()) {
      final added = jsNum(e.value) - jsNum(before[k]![e.key]);
      if (added <= 0) continue;
      final xp = jsRound(added * multiplier);
      if (xp - added > 0) after[e.key] = jsOut(jsNum(e.value) + xp - added);
      meta['$k:${e.key}:$now:${uid()}'] = {
        'kind': k, 'baseXP': jsOut(added), 'multiplier': jsOut(multiplier), 'xp': jsOut(xp),
        'timestamp': now, 'source': labels[k], 'subjectId': e.key,
      };
    }
  }
  final bonus = mapIn(ledger, 'v348LibraryAdditionBonus');
  if (!bonus.containsKey(id) && !before['libraryAdditions']!.containsKey(id) && additions.containsKey(id)) {
    final base = math.max(0.0, jsRound(l.reward('libraryAdditionXP')));
    final xp = jsRound(base * multiplier);
    bonus[id] = jsOut(math.max(0.0, xp - base));
    meta['library-add:$id'] = {
      'kind': 'libraryAdditions', 'baseXP': jsOut(base), 'multiplier': jsOut(multiplier), 'xp': jsOut(xp),
      'timestamp': now, 'source': 'Library · new title', 'subjectId': id,
    };
  }
}

/// `entriesNote`.
String _entriesNote(List<Map<String, dynamic>> entries) => entries.map((e) {
      final qty = jsNum(e['qty']);
      return qty > 1 ? '${jsStr(e['title'])} ×${_jsNumText(e['qty'])}' : jsStr(e['title']);
    }).join(', ');

String _jsNumText(Object? v) {
  if (v is String) return v;
  final n = jsNum(v);
  if (n.isNaN) return 'NaN';
  if (n == n.truncateToDouble() && n.abs() < 1e21) return n.toInt().toString();
  return n.toString();
}

// ---- System Respect XP (v165 + v167 + v180) ------------------------------------------------

String _normTitle(Object? v) => cleanTitle(jsStr(v)).trim().toLowerCase();

double _round2(double v) => jsRound((v.isNaN || v == 0 ? 1 : v) * 100) / 100;

/// `v167NormalizeRespectConfig`.
Map<String, dynamic> normalizeRespectConfig(Object? raw) {
  final src = asMap(raw) ?? const {};
  double c(String k, double min, double max, double fallback) {
    final n = jsNumFromKey(src, k);
    return n != null ? n.clamp(min, max).toDouble() : fallback;
  }

  return {
    'categoryBaseXP': jsOut(jsRound(c('categoryBaseXP', 0, 10000, 10))),
    'exactTitleBaseXP': jsOut(jsRound(c('exactTitleBaseXP', 0, 10000, 25))),
    'noSkipGrowthPercent': jsOut(c('noSkipGrowthPercent', 0, 100, 8)),
    'noSkipCapPercent': jsOut(c('noSkipCapPercent', 0, 1000, 50)),
    'firstPickGrowthPercent': jsOut(c('firstPickGrowthPercent', 0, 100, 14)),
    'firstPickCapPercent': jsOut(c('firstPickCapPercent', 0, 1000, 75)),
    'modifiedAt': jsOut(math.max(0.0, jsNum(src['modifiedAt']))),
  };
}

({double noSkip, double noReroll, double combined}) respectMultipliers(Map<String, dynamic> cfg, num noSkip, num noReroll) {
  final skip = math.max(0.0, noSkip.toDouble()), reroll = math.max(0.0, noReroll.toDouble());
  final a = _round2(1 + math.min(jsNum(cfg['noSkipCapPercent']) / 100, jsNum(cfg['noSkipGrowthPercent']) / 100 * jsLog2(math.max(1, skip))));
  final b = _round2(1 + math.min(jsNum(cfg['firstPickCapPercent']) / 100, jsNum(cfg['firstPickGrowthPercent']) / 100 * jsLog2(math.max(1, reroll))));
  return (noSkip: a, noReroll: b, combined: _round2(a * b));
}

/// `v180RespectSlotLimit`.
int respectSlotLimit(Recommender r, Map<String, dynamic> task) {
  if (!r.exactTitles) return 0;
  final cat = r.getCategory(jsStr(task['categoryId']));
  final unit = jsStr(cat['unit']).isNotEmpty ? jsStr(cat['unit']) : jsStr(task['unit']);
  if (RegExp(r'(^|[^a-z])(movies?|films?|books?|titles?)([^a-z]|$)', caseSensitive: false).hasMatch(unit.toLowerCase())) {
    final mid = jsNum(task['targetMid']);
    return math.max(1, jsRound(mid == 0 || mid.isNaN ? 1 : mid).toInt());
  }
  return 1;
}

({bool respected, double bonus}) _applyRespectReward(Map<String, dynamic> state, Recommender r, Leveling l,
    Map<String, dynamic> task, List<Map<String, dynamic>> entries, List<Map<String, dynamic>> groupRows, int now) {
  final st = ensureRespectState(state);
  final settings = mapIn(state, 'settings');
  final cfg = normalizeRespectConfig(settings['systemRespectXP']);
  settings['systemRespectXP'] = cfg;
  final respected = groupRows.any((s) =>
      s['status'] != 'skipped' && jsStr(s['categoryId']) == jsStr(task['categoryId']) && jsNum(s['actualAmount']) > 0);
  if (!respected) {
    st['noSkipStreak'] = 0;
    st['noRerollStreak'] = 0;
    st['currentRerolls'] = 0;
    st['modifiedAt'] = now;
    return (respected: false, bonus: 0);
  }
  final hadReroll = jsNum(st['currentRerolls']) > 0;
  final noSkip = jsNum(st['noSkipStreak']).toInt() + 1;
  final noReroll = hadReroll ? 0 : jsNum(st['noRerollStreak']).toInt() + 1;
  final exactEnabled = r.exactTitles;
  // v180RespectMatchInfo
  var slotLimit = 0;
  var eligible = <Map<String, dynamic>>[];
  final matched = <Map<String, dynamic>>[];
  if (exactEnabled) {
    final history = r.ensureHistory(task);
    slotLimit = respectSlotLimit(r, task);
    eligible = history.take(slotLimit).toList();
    final loggedIds = <String>{}, loggedTitles = <String>{};
    void add(Object? id, Object? title, Object? qty) {
      if (!(jsNum(qty) > 0)) return;
      final sid = jsStr(id), key = _normTitle(title);
      if (sid.isNotEmpty) loggedIds.add(sid);
      if (key.isNotEmpty) loggedTitles.add(key);
    }

    for (final e in entries) {
      add(e['libraryId'], e['title'], e['qty']);
    }
    for (final s in groupRows) {
      for (final t in asList(s['titles'])) {
        final m = asMap(t);
        add(m?['libraryId'], m?['title'], m?['qty']);
      }
    }
    for (var i = 0; i < eligible.length; i++) {
      final rec = eligible[i];
      final id = jsStr(rec['libraryId']), title = _normTitle(rec['title']);
      if ((id.isNotEmpty && loggedIds.contains(id)) || (title.isNotEmpty && loggedTitles.contains(title))) {
        Map<String, dynamic>? item;
        if (id.isNotEmpty) item = r.library.where((x) => jsStr(x['id']) == id).firstOrNull;
        if (item == null && title.isNotEmpty) item = r.library.where((x) => _normTitle(x['title']) == title).firstOrNull;
        matched.add({'slot': i + 1, 'libraryId': id, 'title': cleanTitle(item?['title'] ?? rec['title'])});
      }
    }
  }
  final categoryXP = math.max(0.0, jsRound(jsNum(cfg['categoryBaseXP'])));
  final exactPerTitle = math.max(0.0, jsRound(jsNum(cfg['exactTitleBaseXP'])));
  final exactTitleXP = exactEnabled ? exactPerTitle * matched.length : 0.0;
  final baseRespectXP = categoryXP + exactTitleXP;
  final mult = respectMultipliers(cfg, noSkip, noReroll);
  final bonus = l.enabled ? math.max(0.0, jsRound(baseRespectXP * mult.noSkip * mult.noReroll)) : 0.0;

  st['noSkipStreak'] = noSkip;
  st['noRerollStreak'] = noReroll;
  st['bestNoSkipStreak'] = math.max(jsNum(st['bestNoSkipStreak']).toInt(), noSkip);
  st['bestNoRerollStreak'] = math.max(jsNum(st['bestNoRerollStreak']).toInt(), noReroll);

  final target = groupRows.where((s) => s['status'] != 'skipped' && jsStr(s['categoryId']) == jsStr(task['categoryId'])).firstOrNull ??
      groupRows.where((s) => s['status'] != 'skipped').firstOrNull;
  if (target != null) {
    final history = r.ensureHistory(task);
    final initial = eligible.isNotEmpty ? eligible.first : (history.isNotEmpty ? history.first : null);
    target
      ..['v165RespectBonusXP'] = jsOut(bonus)
      ..['v165RespectBaseXP'] = jsOut(baseRespectXP)
      ..['v165SystemBaseXP'] = jsOut(categoryXP)
      ..['v165RecommendedTitleBaseXP'] = jsOut(exactTitleXP)
      ..['v165RecommendedTitleFollowed'] = matched.isNotEmpty
      ..['v165ExactTitleRecommendationEnabled'] = exactEnabled
      ..['v165RecommendedLibraryId'] = exactEnabled ? jsStr(initial?['libraryId'] ?? task['libraryId']) : ''
      ..['v165RecommendedTitle'] = exactEnabled ? cleanTitle(initial?['title'] ?? task['title']) : ''
      ..['v165NoSkipStreak'] = noSkip
      ..['v165NoRerollStreak'] = noReroll
      ..['v165NoSkipMultiplier'] = jsOut(mult.noSkip)
      ..['v165NoRerollMultiplier'] = jsOut(mult.noReroll)
      ..['v165RespectMultiplier'] = jsOut(mult.combined)
      ..['v165RerollsBeforeLog'] = st['currentRerolls']
      ..['v165RespectXPVersion'] = 165
      ..['v180RespectXPVersion'] = 180
      ..['v180TitleRerollsBeforeLog'] = math.max(0, history.length - 1)
      ..['v180RespectSlotLimit'] = slotLimit
      ..['v180RespectEligibleShown'] = eligible.length
      ..['v180RespectMatchedCount'] = matched.length
      ..['v180RespectMatchedRecommendations'] = [for (final m in matched) Map<String, dynamic>.from(m)]
      ..['v180RecommendationHistory'] = [for (final h in history) Map<String, dynamic>.from(h)]
      ..['v180ExactTitleXPPerMatch'] = jsOut(exactPerTitle)
      ..['v167RespectConfigAtLog'] = {
        'categoryBaseXP': jsOut(categoryXP),
        'exactTitleBaseXP': jsOut(exactPerTitle),
        'noSkipGrowthPercent': cfg['noSkipGrowthPercent'],
        'noSkipCapPercent': cfg['noSkipCapPercent'],
        'firstPickGrowthPercent': cfg['firstPickGrowthPercent'],
        'firstPickCapPercent': cfg['firstPickCapPercent'],
      };
  }
  st['currentRerolls'] = 0;
  st['lastRewardAt'] = now;
  st['modifiedAt'] = now;
  return (respected: true, bonus: bonus);
}

// ---- mf553 reroll-title rows ---------------------------------------------------------------

({Map<String, double> byCategory, int units, double baseXP, List<String> titles}) _rerollUnitRows(
    Map<String, dynamic> state, Map<String, dynamic> task, Map<String, dynamic> draft, LogDraftEditor editor, Leveling l, Recommender r) {
  const empty = (byCategory: <String, double>{}, units: 0, baseXP: 0.0, titles: <String>[]);
  final history = asList(task['v180RecommendationHistory']).map(asMap).whereType<Map<String, dynamic>>().toList();
  final entries = editor.entries;
  if (history.isEmpty || entries.isEmpty) return empty;
  final slot = respectSlotLimit(r, task);
  String key(Map<String, dynamic> x) {
    final id = jsStr(x['libraryId']);
    if (id.isNotEmpty) return 'id:$id';
    final t = _normTitle(x['title']);
    return t.isEmpty ? '' : 'title:$t';
  }

  final rerollKeys = <String>{};
  final names = <String, String>{};
  for (final rec in history.skip(slot)) {
    final k = key(rec);
    if (k.isEmpty) continue;
    rerollKeys.add(k);
    names.putIfAbsent(k, () => jsStr(rec['title']).trim().isEmpty ? 'Reroll title' : jsStr(rec['title']).trim());
  }
  if (rerollKeys.isEmpty || !l.enabled) return empty;
  final byCategory = <String, double>{};
  final titles = <String>[];
  var units = 0;
  var baseXP = 0.0;
  for (final e in entries) {
    final k = key(e);
    if (k.isEmpty || !rerollKeys.contains(k)) continue;
    final count = editor.itemized && e['v369Units'] is List ? editor.units(e).length : math.max(0, jsNum(e['qty']).floor());
    if (count == 0) continue;
    final item = editor.item(e['libraryId']);
    final cid = jsStr(item?['categoryId'] ?? task['categoryId'] ?? draft['categoryId']);
    final cat = r.category(cid);
    if (cat == null) continue;
    final perUnit = math.max(0.0, l.unitXP(jsStr(cat['unit'])));
    if (perUnit == 0) continue;
    final xp = count * perUnit;
    byCategory[cid] = (byCategory[cid] ?? 0) + xp;
    units += count;
    baseXP += xp;
    final name = names[k] ?? (jsStr(e['title']).isEmpty ? 'Reroll title' : jsStr(e['title']));
    if (!titles.contains(name)) titles.add(name);
  }
  return (byCategory: byCategory, units: units, baseXP: baseXP, titles: titles);
}

// ---- activity log helpers ---------------------------------------------------------------------

List<Map<String, dynamic>> _librarySnapshot(Map<String, dynamic> state) => [
      for (final raw in asList(state['library']))
        if (asMap(raw) != null)
          {
            for (final k in const ['id', 'title', 'categoryId', 'status', 'priority', 'progress', 'total', 'rating'])
              k: _clone(asMap(raw)![k]),
          },
    ];

/// `v43DiffSnapshot`.
List<Map<String, dynamic>> _diffLibrary(List<Map<String, dynamic>> before, List<Map<String, dynamic>> after) {
  final b = <Object?, Map<String, dynamic>>{}, a = <Object?, Map<String, dynamic>>{};
  for (final i in before) {
    b[i['id']] = i;
  }
  for (final i in after) {
    a[i['id']] = i;
  }
  final ids = <Object?>{...b.keys, ...a.keys};
  final changes = <Map<String, dynamic>>[];
  String show(Object? v) => v == null ? '—' : (v is num ? _jsNumText(v) : v.toString());
  for (final id in ids) {
    final x = b[id], y = a[id];
    if (x == null && y != null) {
      changes.add({'id': id, 'title': cleanTitle(y['title']), 'kind': 'added'});
    } else if (x != null && y == null) {
      changes.add({'id': id, 'title': cleanTitle(x['title']), 'kind': 'deleted'});
    } else if (x != null && y != null) {
      final fields = <String>[];
      for (final k in const ['title', 'categoryId', 'status', 'priority', 'progress', 'total', 'rating']) {
        if (jsonEncode(_numNorm(x[k])) != jsonEncode(_numNorm(y[k]))) fields.add('$k: ${show(x[k])} → ${show(y[k])}');
      }
      if (fields.isNotEmpty) changes.add({'id': id, 'title': cleanTitle(y['title']), 'kind': 'changed', 'fields': fields});
    }
    if (changes.length >= 25) break;
  }
  return changes;
}

Object? _numNorm(Object? v) => v is num ? jsOut(v.toDouble()) : v;

/// XP-bearing ledger maps that can change while a log is saved.
double _ledgerTotals(Map<String, dynamic> state) {
  final ledger = asMap(state['xpLedger']) ?? const {};
  var total = 0.0;
  for (final k in const ['v334StartedTitles', 'v335FirstEpisodeRewards', 'v348LibraryCompletionBonus', 'v348LibraryAdditionBonus', 'v348ActionEvents']) {
    for (final v in (asMap(ledger[k]) ?? const {}).values) {
      final n = jsNum(v);
      if (n.isFinite) total += n;
    }
  }
  return total;
}
