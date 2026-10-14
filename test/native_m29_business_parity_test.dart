import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow_app/services/native_m29_business_parity.dart';
import 'package:mediaflow_app/services/native_cas_protocol.dart';

void main() {
  final source = jsonDecode(File('test/fixtures/m29_business_rules_vectors.json')
      .readAsStringSync()) as Map<String, dynamic>;

  test('v90 grouped scheduler events and weighted multi-window balance', () {
    final fixture=Map<String,dynamic>.from(source['scheduler'] as Map);
    final now=fixture['nowMillis'] as int;
    final categories=(fixture['categories'] as List).map(
      (c)=>Map<String,dynamic>.from(c as Map)).toList();
    final sessions=(fixture['sessions'] as List).map((s) {
      final row=Map<String,dynamic>.from(s as Map);
      row['timestamp']=now-((row['daysAgo'] as num)*86400000).round();
      return row;
    }).toList();
    final expected=fixture['expected'] as Map;
    final logical=NativeM29BusinessParity.logicalEvents(sessions);
    expect(logical.length, expected['logicalEventCount']);
    expect(logical.first.categoryIds.toList()..sort(),
        (expected['groupedTopCategories'] as List).cast<String>());
    expect(NativeM29BusinessParity.consumedSessions(sessions),hasLength(4));

    final expectedAmounts=expected['suggested'] as Map;
    final expectedScores=expected['scores'] as Map;
    final scores=NativeM29BusinessParity.scores(
      categories:categories, sessions:sessions,
      settings:Map<String,dynamic>.from(fixture['settings'] as Map),
      nowMillis:now,
    );
    for (final category in categories) {
      final id=category['id'] as String;
      final balance=NativeM29BusinessParity.categoryBalance(
        category:category,categories:categories,
        sessions:sessions,nowMillis:now);
      expect(balance.desiredShare,closeTo(id=='anime'?2/3:1/3,1e-10));
      expect(balance.ratio,isPositive);
      expect(balance.daysIdle,closeTo(1,1e-9));
      final amount=NativeM29BusinessParity.suggestedAmount(
        target:(category['target'] as num).toDouble(),balance:balance);
      final anticipated=expectedAmounts[id] as Map;
      expect(amount.low,anticipated['low']);
      expect(amount.high,anticipated['high']);
      expect(amount.direction,anticipated['direction']);
      expect(scores[id],greaterThanOrEqualTo((expectedScores[id] as Map)['min'] as num));
      expect(scores[id],lessThanOrEqualTo((expectedScores[id] as Map)['max'] as num));
    }
    final noSessions=NativeM29BusinessParity.categoryBalance(
      category:categories[0],categories:categories,
      sessions:[],nowMillis:now);
    expect(noSessions.ratio,1);
    expect(noSessions.daysIdle,isInfinite);
    final untouched=NativeM29BusinessParity.suggestedAmount(
      target:4,balance:noSessions);
    final empty=source['emptyScheduler'] as Map;
    final anticipated=(empty['expected'] as Map)['anime'] as Map;
    expect(untouched.low,anticipated['low']);
    expect(untouched.high,anticipated['high']);
    expect(untouched.direction,anticipated['direction']);
    final emptyScores=NativeM29BusinessParity.scores(
      categories:categories,sessions:[],
      settings:Map<String,dynamic>.from(fixture['settings'] as Map),
      nowMillis:now);
    expect(emptyScores['anime'], anticipated['score']);
  });

  test('v252 season sorting, Specials and total/progress reconciliation', () {
    final fixture=source['seasons'] as Map;
    final rows=fixture['rows'];
    final expected=fixture['expected'] as Map;
    final normalized=NativeM29BusinessParity.normalizeSeasons(rows);
    expect(normalized.map((s)=>s.id).toList(),expected['ids']);
    expect(normalized.map((s)=>s.number).toList(),expected['numbers']);
    expect(normalized.map((s)=>s.name).toList(),expected['names']);
    expect(normalized.map((s)=>s.progress).toList(),expected['progress']);
    final total=NativeM29BusinessParity.seasonAggregate(rows);
    final wanted=expected['aggregate'] as Map;
    expect(total.progress,wanted['progress']);
    expect(total.total,wanted['total']);
    expect(total.knownTotals,wanted['knownTotals']);
    expect(total.count,wanted['count']);
    expect(NativeM29BusinessParity.seasonOffset(normalized,'s2'),
      expected['s2Offset']);
    expect((rows as List)[1]['progress'],13,
      reason:'native normalization must not modify the original input');
  });

  test('v394 non-contiguous Advanced Logging and exact runtime previews', () {
    final fixture=source['advanced'] as Map;
    final exp=fixture['expected'] as Map;
    expect(NativeM29BusinessParity.exactContiguous(
      fixture['contiguous'],fixture['base'] as int),exp['exact']);
    expect(NativeM29BusinessParity.exactContiguous(
      fixture['gapped'],fixture['base'] as int),exp['gapExact']);
    expect(NativeM29BusinessParity.exactContiguous(
      [{'number':11},{'number':11}],10),isFalse,
      reason:'duplicate episodes must not imply new sequential progress');
    final units=fixture['units'];
    expect(NativeM29BusinessParity.runtimeForEntry(
      {'v369Units':units}),exp['seconds']);
    expect(NativeM29BusinessParity.runtimeForEntry({
      'v369Units':units,'v394RuntimeManual':true,
      'v394RuntimeSeconds':360,
    }),exp['manualSeconds']);
    expect(NativeM29BusinessParity.runtimeForEntry({
      'v369Units':units,'v394RuntimeManual':true,
      'v394RuntimeSeconds':-1,
    }),exp['seconds']);
    expect(NativeM29BusinessParity.runtimeForEntry({
      'v369Units':<Object>[], 'v394RuntimeManual':true,
      'v394RuntimeSeconds':360,
    }),0);
  });

  test('v348 Collection and Personal Order actions only detect candidates', () {
    final actions=source['actions'] as Map;
    final c=actions['collection'] as Map;
    final detected=NativeM29BusinessParity.collectionActionChanges(
      (c['before'] as List).cast<String>(),
      (c['after'] as List).cast<String>());
    final expected=Map<String,int>.fromEntries(
      (c['expected'] as List).map((x)=>MapEntry(
        (x as List).first as String,x.last as int)));
    expect(detected,expected);
    expect(NativeM29BusinessParity.collectionActionChanges(
      ['a','b'],['a','b']),{'collectionAddTitleXP':0,
      'collectionReorderTitleXP':0});

    final o=actions['order'] as Map;
    List<String> ids(String key)=>(o[key] as List).map(
      (x)=>(x as Map)['id'] as String).toList();
    Map<String,List<String>> queues(String key)=>Map.fromEntries(
      (o[key] as Map).entries.map((entry)=>MapEntry(
        entry.key as String,(entry.value as List).cast<String>())));
    final first=NativeM29BusinessParity.orderActionChanges(
      beforeTitles:(o['beforeTitles'] as List).cast<String>(),
      afterTitles:(o['afterTitles'] as List).cast<String>(),
      beforeAssignments:ids('beforeAssignments'),
      afterAssignments:ids('afterAssignments'),
      beforeQueues:queues('beforeQueues'),
      afterQueues:queues('beforeQueues'),
    );
    final second=NativeM29BusinessParity.orderActionChanges(
      beforeTitles:(o['afterTitles'] as List).cast<String>(),
      afterTitles:(o['afterTitles'] as List).cast<String>(),
      beforeAssignments:ids('afterAssignments'),
      afterAssignments:ids('afterAssignments'),
      beforeQueues:queues('beforeQueues'),
      afterQueues:queues('afterQueues'),
    );
    expect(first['orderAddTitleXP'],1);
    expect(first['orderReorderTitleXP'],1);
    expect(first['orderAddCollectionXP'],1);
    expect(first['orderReorderCollectionXP'],0);
    expect(second['orderReorderCollectionXP'],1);
    expect(second['orderAddCollectionXP'],0);
    expect(first['orderAddTitleXP']!+first['orderReorderTitleXP']!+
      first['orderAddCollectionXP']!+second['orderReorderCollectionXP']!,4);
    expect(NativeCloudCapabilities.cloudWritesEnabled,isFalse);
    expect(NativeCloudCapabilities.offlineWriteQueueEnabled,isFalse);
    expect(NativeCloudCapabilities.hasServerSideCas,isFalse);
  });

  test('scheduler rejects skipped consumption and extreme ratios remain bounded', () {
    final now=1791979200000;
    final categories=[
      <String,dynamic>{'id':'a','enabled':true,'weight':1,'target':8},
      <String,dynamic>{'id':'b','enabled':true,'weight':1,'target':8},
    ];
    final history=[
      <String,dynamic>{'id':'1','categoryId':'a','status':'logged',
        'minutes':200000,'timestamp':now-86400000},
      <String,dynamic>{'id':'2','categoryId':'b','status':'skipped',
        'minutes':200000,'timestamp':now},
    ];
    final bal=NativeM29BusinessParity.categoryBalance(
      category:categories.first,categories:categories,
      sessions:history,nowMillis:now);
    expect(bal.ratio,greaterThanOrEqualTo(1.35));
    final amount=NativeM29BusinessParity.suggestedAmount(
      target:8,balance:bal);
    expect(amount.direction,'reduced');
    expect(amount.low,greaterThanOrEqualTo(1));
    expect(amount.high,greaterThanOrEqualTo(amount.low));
    expect(amount.multiplier,inInclusiveRange(.45,2.0));
  });
}
