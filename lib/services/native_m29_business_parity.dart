import 'dart:math' as math;

/// Source-backed, pure v410 business rules. These methods process isolated
/// synthetic maps or detached snapshots; they NEVER mutate account records,
/// write cloud state, award XP or submit History events.
///
/// Source anchors: scheduler 007, v252 seasons, v369/v394 advanced logging,
/// v348 Collection/Personal Order reward *detection*. Runtime overrides and
/// real side effects still require separate end-to-end certification.
abstract final class NativeM29BusinessParity {
  static double number(Object? raw) {
    if (raw == null) return 0;
    if (raw is bool) return raw ? 1 : 0;
    if (raw is num) return raw.toDouble();
    if (raw is String && raw.trim().isEmpty) return 0;
    return double.tryParse(raw.toString()) ?? double.nan;
  }

  static double orNumber(Object? raw, [double fallback = 0]) {
    final value = number(raw);
    return value.isNaN || value == 0 ? fallback : value;
  }

  static int jsRound(double n) => (n + .5).floor();
  static int jsFloor(Object? n) {
    final value = orNumber(n);
    return value.isFinite ? value.floor() : 0;
  }

  static List<Map<String, dynamic>> _maps(Object? rows) {
    if (rows is! List) return [];
    return [for (final row in rows)
      if (row is Map) Map<String, dynamic>.from(row)];
  }

  static List<Map<String, dynamic>> consumedSessions(Object? rows) =>
      _maps(rows).where((s) =>
        s['status'] != 'skipped' &&
        (orNumber(s['minutes']) > 0 || orNumber(s['actualAmount']) > 0)
      ).toList();

  /// v90: one submission containing multiple category-specific rows is one
  /// scheduler event, not multiple recency/penalty events.
  static List<NativeM29LogicalEvent> logicalEvents(Object? rows) {
    final source = consumedSessions(rows)
      ..sort((a, b) => orNumber(b['timestamp'])
        .compareTo(orNumber(a['timestamp'])));
    final groups = <String, NativeM29LogicalEvent>{};
    var synthetic = 0;
    for (final s in source) {
      final groupId = (s['sessionGroupId'] ?? '').toString();
      final id = (s['id'] ?? '').toString();
      final key = groupId.isNotEmpty
          ? 'group:$groupId'
          : 'session:${id.isNotEmpty ? id : "synthetic-${++synthetic}"}';
      final event = groups.putIfAbsent(key,
        () => NativeM29LogicalEvent(key));
      event.timestamp = math.max(event.timestamp, orNumber(s['timestamp']));
      final category = (s['categoryId'] ?? '').toString();
      if (category.isNotEmpty) event.categoryIds.add(category);
    }
    return groups.values.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  static List<Map<String, dynamic>> enabledCategories(Object? categories) =>
      _maps(categories).where((cat) => cat['enabled'] == true).toList();

  static double _weight(Map<String, dynamic> c) =>
    math.max(.25, orNumber(c['weight'], 1));

  /// v410 base categoryBalance window weighting with fixed clock in millis.
  /// Source-specific scheduler scope overrides must be tested independently.
  static NativeM29Balance categoryBalance({
    required Map<String, dynamic> category,
    required List<Map<String, dynamic>> categories,
    required List<Map<String, dynamic>> sessions,
    required int nowMillis,
  }) {
    final pool = enabledCategories(categories);
    final totalWeight = pool.fold<double>(
      0, (n, c) => n + _weight(c));
    final share = _weight(category) / (totalWeight == 0 ? 1 : totalWeight);
    final consumed = consumedSessions(sessions);
    const windows = <(int?, double, double)>[
      (3, .35, 60), (7, .25, 120),
      (30, .20, 240), (null, .20, 1),
    ];
    var weighted = 0.0;
    var weights = 0.0;
    for (final (days, windowWeight, minimumMinutes) in windows) {
      final visible = days == null ? consumed : consumed.where(
        (row) => orNumber(row['timestamp']) >=
          nowMillis - days * 86400000).toList();
      final total = visible.fold<double>(
        0, (n, row) => n + math.max(0.0, orNumber(row['minutes'])));
      final forCategory = visible.where(
        (row) => row['categoryId'] == category['id']).fold<double>(
        0, (n, row) => n + math.max(0.0, orNumber(row['minutes'])));
      final ratio = share > 0 ? (total > 0 ? forCategory / total : 0) / share : 1;
      if (total >= minimumMinutes) {
        weighted += math.min(6.0, ratio) * windowWeight;
        weights += windowWeight;
      }
    }
    final last = consumed.where((row) =>
      row['categoryId'] == category['id']).toList()
      ..sort((a, b) => orNumber(b['timestamp'])
        .compareTo(orNumber(a['timestamp'])));
    return NativeM29Balance(
      desiredShare: share,
      ratio: weights > 0 ? weighted / weights : 1,
      daysIdle: last.isEmpty ? double.infinity :
        (nowMillis - orNumber(last.first['timestamp'])) / 86400000,
    );
  }

  static NativeM29Amount suggestedAmount({
    required double target,
    required NativeM29Balance balance,
  }) {
    final t = math.max(1.0, target);
    final ratio = balance.ratio;
    final idle = balance.daysIdle;
    var multiplier = 1.0;
    if (ratio >= 2.5) {
      multiplier *= .50;
    } else if (ratio >= 1.8) {
      multiplier *= .62;
    } else if (ratio >= 1.35) {
      multiplier *= .78;
    } else if (ratio <= .45) {
      multiplier *= 1.35;
    } else if (ratio <= .70) {
      multiplier *= 1.18;
    }
    if (idle.isFinite) {
      if (idle >= 60) {
        multiplier *= 1.65;
      } else if (idle >= 30) {
        multiplier *= 1.50;
      } else if (idle >= 14) {
        multiplier *= 1.32;
      } else if (idle >= 7) {
        multiplier *= 1.18;
      }
    } else {
      multiplier *= 1.5;
    }
    multiplier = multiplier.clamp(.45, 2.0).toDouble();
    final center = math.max(1, jsRound(t * multiplier));
    final low = center <= 2 ? center :
      math.max(1, jsRound(center * .85));
    final high = center <= 2 ? center :
      math.max(low, jsRound(center * 1.15));
    return NativeM29Amount(
      low, high, multiplier,
      multiplier < .9 ? 'reduced' : multiplier > 1.1 ? 'increased' : 'normal',
    );
  }

  /// Deterministic v410 base computeScores, randomness=0.
  static Map<String, double> scores({
    required List<Map<String, dynamic>> categories,
    required List<Map<String, dynamic>> sessions,
    required Map<String, dynamic> settings,
    required int nowMillis,
    List<String> excludeIds = const [],
  }) {
    var pool = enabledCategories(categories).where(
      (c) => !excludeIds.contains(c['id'])).toList();
    if (pool.isEmpty) pool = enabledCategories(categories);
    final events = logicalEvents(sessions);
    final recent = events.take(6).toList();
    final consumed = consumedSessions(sessions);
    double s(String key) => orNumber(settings[key]);
    final result = <String, double>{};
    for (final category in pool) {
      final id = category['id'].toString();
      final last = consumed.where((row) => row['categoryId'] == id).toList()
        ..sort((a, b) => orNumber(b['timestamp'])
          .compareTo(orNumber(a['timestamp'])));
      final days = last.isEmpty ? 0.0 :
        (nowMillis - orNumber(last.first['timestamp'])) / 86400000;
      final neglect = last.isEmpty ? s('neglectCap') :
        math.min(s('neglectCap'), days * s('neglectRate'));
      final recentCount = recent.where((e) => e.categoryIds.contains(id)).length;
      final repetition = recentCount * s('repetitionPenalty');
      var consecutive = 0;
      for (final e in events) {
        if (e.categoryIds.contains(id)) {
          consecutive++;
        } else {
          break;
        }
      }
      final consecutivePenalty = consecutive * s('consecutivePenalty');
      final balance = categoryBalance(category: category,
        categories: categories, sessions: sessions, nowMillis: nowMillis);
      final over = math.max(0.0, balance.ratio - 1);
      final under = math.max(0.0, 1 - balance.ratio);
      final saturation = math.min(70.0, over * s('saturationWeight') * 2.2);
      final bonus = math.min(28.0, under * s('neglectCap') * .55);
      final seasonal = category['seasonal'] == true
        ? s('seasonalBonus') + s('seasonalFreshCount') * 4 : 0.0;
      final raw = orNumber(category['weight']) * 8 +
        neglect + bonus + seasonal - repetition -
        consecutivePenalty - saturation;
      result[id] = math.max(math.max(raw, 1.5), .5);
    }
    return result;
  }

  static int _v252Num(Object? input, [int fallback = 0]) {
    final value = number(input);
    return value.isFinite ? math.max(0, jsRound(value)) : fallback;
  }

  static int? _seasonNumber(Object? input) {
    if (input == null || input.toString().trim().isEmpty) return null;
    final n = number(input);
    return n.isFinite ? math.max(0, jsRound(n)) : null;
  }

  static String _seasonLabel(Map<String, dynamic> raw, int index, int? n) {
    final name = (raw['name'] ?? raw['title'] ?? '').toString().trim();
    if (name.isNotEmpty) return name;
    if (n == 0) return 'Specials';
    if (n != null) return 'Season $n';
    return 'Season ${index + 1}';
  }

  /// Source v252NormalizeSeasons + v252SortSeasons, detached normalized rows.
  static List<NativeM29Season> normalizeSeasons(Object? input,
      {String source = 'manual'}) {
    final raw = _maps(input);
    final output = <NativeM29Season>[];
    for (var i = 0; i < raw.length; i++) {
      final s = raw[i];
      final n = _seasonNumber(s['number'] ?? s['season'] ??
        s['season_number'] ?? s['seasonNumber']);
      final totalValue = s['total'] ?? s['totalEpisodes'] ??
        s['total_episodes'] ?? s['total_episodes_count'] ??
        s['episodes_count'] ?? s['episode_count'];
      final total = totalValue == null || totalValue.toString().trim().isEmpty
        ? null : _v252Num(totalValue);
      var progress = _v252Num(s['progress'] ?? s['watchedEpisodes'] ??
        s['watched_episodes'] ?? s['watched_episodes_count'] ??
        s['episodes_watched']);
      if (total != null && total > 0) progress = math.min(progress, total);
      output.add(NativeM29Season(
        (s['id'] ?? s['seasonId'] ?? s['season_id'] ?? 'synthetic-${i+1}').toString(),
        n, _seasonLabel(s, i, n), progress, total,
      ));
    }
    final indexed = output.asMap().entries.toList()
      ..sort((a,b) {
        final an=a.value.number, bn=b.value.number;
        if (an == null && bn == null) return a.key.compareTo(b.key);
        if (an == null) return 1;
        if (bn == null) return -1;
        final order=an.compareTo(bn);
        return order != 0 ? order : a.key.compareTo(b.key);
      });
    return indexed.map((e)=>e.value).toList(growable:false);
  }

  static NativeM29SeasonAggregate seasonAggregate(Object? input) {
    final seasons=normalizeSeasons(input);
    var progress=0, total=0, known=0;
    for(final s in seasons){
      progress += s.progress;
      total += s.total ?? 0;
      if ((s.total ?? 0) > 0) known++;
    }
    return NativeM29SeasonAggregate(progress,
      total > 0 ? total : null, known, seasons.length);
  }

  static int seasonOffset(List<NativeM29Season> seasons, String seasonId) {
    var offset=0;
    for (final s in seasons) {
      if (s.id==seasonId) break;
      offset += (s.total ?? 0) > 0 ? s.total! : s.progress;
    }
    return math.max(0, offset);
  }

  /// Canonical v394ExactContiguous: duplicates and gaps must remain visible.
  static bool exactContiguous(Object? units, int base) {
    final numbers = _maps(units).map((u) => jsFloor(u['number'])).toList()
      ..sort();
    for (var i=0;i<numbers.length;i++){
      if(numbers[i]!=base+i+1) return false;
    }
    return true;
  }

  /// v369Seconds followed by v394RuntimeForEntry manual override.
  static int unitSeconds(Map<String,dynamic> u) {
    final duration=number(u['durationSeconds']);
    if (u.containsKey('durationSeconds') && duration.isFinite) {
      return math.max(0, duration.floor());
    }
    return math.max(0, jsRound(orNumber(u['minutes'])*60));
  }
  static int runtimeForEntry(Map<String,dynamic> entry) {
    final units=_maps(entry['v369Units']);
    final actual=units.fold<int>(0, (total,u)=>total+unitSeconds(u));
    if (entry['v394RuntimeManual']==true && units.isNotEmpty) {
      final raw=number(entry['v394RuntimeSeconds']);
      if (raw.isFinite && raw>=0) return jsRound(raw);
    }
    return actual;
  }

  /// Pure subset of v348TouchCollection action detection, no awards.
  static Map<String,int> collectionActionChanges(
      List<String> before, List<String> after) {
    final previous=before.toSet();
    final added=after.where((id)=>!previous.contains(id)).length;
    final oldCommon=before.where((id)=>after.contains(id)).join('\u0000');
    final newCommon=after.where((id)=>previous.contains(id)).join('\u0000');
    final commonCount=before.where((id)=>after.contains(id)).length;
    return {'collectionAddTitleXP':added,
      'collectionReorderTitleXP':
        commonCount>1 && oldCommon!=newCommon ? 1 : 0};
  }

  /// v348CompareOrder: reports *candidate* action counts only, never XP.
  static Map<String,int> orderActionChanges({
    required List<String> beforeTitles,
    required List<String> afterTitles,
    required List<String> beforeAssignments,
    required List<String> afterAssignments,
    required Map<String,List<String>> beforeQueues,
    required Map<String,List<String>> afterQueues,
  }) {
    final beforeSet=beforeTitles.toSet(),afterSet=afterTitles.toSet();
    final newTitles=afterTitles.where((id)=>!beforeSet.contains(id)).length;
    final oldCommon=beforeTitles.where((id)=>afterSet.contains(id)).toList();
    final newCommon=afterTitles.where((id)=>beforeSet.contains(id)).toList();
    final reorderTitle=oldCommon.length>1 &&
      oldCommon.join('\u0000')!=newCommon.join('\u0000');
    final oldAssignments=beforeAssignments.toSet();
    final newAssigned=afterAssignments.where(
      (id)=>!oldAssignments.contains(id)).length;
    var movedQueue=false;
    if(newAssigned==0) {
      for (final key in {...beforeQueues.keys,...afterQueues.keys}) {
        final old=beforeQueues[key]??const <String>[];
        final now=afterQueues[key]??const <String>[];
        final commonOld=old.where(
          (id)=>id.startsWith('c:')&&now.contains(id)).toList();
        final commonNew=now.where(
          (id)=>id.startsWith('c:')&&old.contains(id)).toList();
        final moved=commonOld.any(
          (id)=>old.indexOf(id)!=now.indexOf(id));
        if ((commonOld.length>1 &&
            commonOld.join('\u0000')!=commonNew.join('\u0000')) || moved){
          movedQueue=true; break;
        }
      }
    }
    return {
      'orderAddTitleXP':newTitles,
      'orderReorderTitleXP':reorderTitle?1:0,
      'orderAddCollectionXP':newAssigned,
      'orderReorderCollectionXP':movedQueue?1:0,
    };
  }
}

class NativeM29LogicalEvent {
  NativeM29LogicalEvent(this.key);
  final String key;
  double timestamp=0;
  final Set<String> categoryIds=<String>{};
}

class NativeM29Balance {
  const NativeM29Balance({required this.desiredShare,
    required this.ratio,required this.daysIdle});
  final double desiredShare, ratio, daysIdle;
}

class NativeM29Amount {
  const NativeM29Amount(this.low,this.high,this.multiplier,this.direction);
  final int low,high;
  final double multiplier;
  final String direction;
}

class NativeM29Season {
  const NativeM29Season(this.id,this.number,this.name,this.progress,this.total);
  final String id,name;
  final int? number,total;
  final int progress;
}

class NativeM29SeasonAggregate {
  const NativeM29SeasonAggregate(
    this.progress,this.total,this.knownTotals,this.count);
  final int progress, knownTotals,count;
  final int? total;
}
