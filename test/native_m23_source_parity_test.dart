// ignore_for_file: prefer_interpolation_to_compose_strings
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow_app/data/mediaflow_models.dart';
import 'package:mediaflow_app/services/native_cas_protocol.dart';
import 'package:mediaflow_app/services/native_history_xp_parity.dart';
import 'package:mediaflow_app/services/native_submission_grouping_preview.dart';
import 'package:mediaflow_app/services/native_logging_parity_preview.dart';
import 'package:mediaflow_app/services/native_offline_projection_codec.dart';

void main() {
  final v = jsonDecode(File('test/fixtures/m23_source_vectors.json')
      .readAsStringSync()) as Map<String, dynamic>;

  test('source-executable History and streak fixtures match native', () {
    for (final row in v['history'] as List) {
      final item = Map<String, dynamic>.from(row as Map);
      final sessions = (item['sessions'] as List).map(
        (s) => MediaFlowSession.fromJson(Map<String,dynamic>.from(s as Map)),
      ).toList();
      final result = NativeHistoryXpParity.analyze(sessions);
      expect(result.logicalActions, item['expectedLogical']);
      expect(result.knownBaseXp, item['expectedKnownBase']);
      expect(result.knownStreakBonusXp, item['expectedKnownStreakBonus']);
      expect(result.unresolvedXpRows, item['expectedUnresolved']);
      expect(result.skippedRows, item['expectedSkipped']);
      expect(result.mayWriteCloud, isFalse);
    }
    expect(NativeCloudCapabilities.cloudWritesEnabled, isFalse);
  });

  test('pinned v120 and v369 source fixtures match native calculations', () {
    for (final row in v['completion'] as List) {
      final item = Map<String,dynamic>.from(row as Map);
      final title = MediaFlowTitle.fromJson({
        'id':'fixture','status':item['status'],
        'progress':item['progress'],'total':item['total'],
      });
      expect(NativeLoggingParityPreview.isCompleted(title), item['expected']);
    }
    for (final row in v['contiguous'] as List) {
      final item = Map<String,dynamic>.from(row as Map);
      expect(NativeLoggingParityPreview.contiguousProgress(
        start: item['start'] as int,
        unitNumbers: (item['units'] as List).cast<int>(),
        total: item['total'] as int,
      ), item['expected']);
    }
  });

  test('pinned original submitLog split fixtures match native previews', () {
    for (final row in v['grouping'] as List) {
      final item = Map<String,dynamic>.from(row as Map);
      final got = NativeSubmissionGroupingPreview.group(
        assignedCategoryId: item['assigned'] as String,
        target: (item['target'] as num).toDouble(),
        minutes: (item['minutes'] as num).toDouble(),
        inputs: (item['entries'] as List).map((raw) {
          final entry = Map<String,dynamic>.from(raw as Map);
          return NativeGroupingInput(
            categoryId: entry['categoryId'] as String,
            quantity: (entry['qty'] as num).toDouble(),
            minutesPerUnit: (entry['minutesPerUnit'] as num).toDouble(),
          );
        }),
      );
      final expected = (item['expected'] as List)
          .map((row) => Map<String,dynamic>.from(row as Map)).toList();
      expect(got.length, expected.length);
      for (var i=0;i<got.length;i++) {
        expect(got[i].categoryId, expected[i]['categoryId']);
        expect(got[i].quantity, expected[i]['quantity']);
        expect(got[i].minutes, expected[i]['minutes']);
        expect(got[i].status, expected[i]['status']);
        expect(got[i].maySubmit, isFalse);
        expect(got[i].exactXp, isNull);
      }
    }
  });

  test('explicit completion ID evidence respects five minute window', () {
    final at = DateTime.utc(2026,10,14,10);
    MediaFlowTitle completed(DateTime? time) => MediaFlowTitle.fromJson({
      'id':'t1','status':'completed','progress':12,'total':12,
      if(time!=null)'completedAt': time.toIso8601String(),
    });
    MediaFlowSession record(DateTime time,{bool skipped=false,String id='t1'})
      => MediaFlowSession.fromJson({
        'id':'session','timestamp':time.toIso8601String(),
        'status':skipped?'skipped':'logged',
        'titles':[{'libraryId':id,'qty':1}],
      });
    expect(NativeHistoryXpParity.hasExplicitCompletionEvidence(
      completed(at),[record(at.add(const Duration(minutes:5)))]),isTrue);
    expect(NativeHistoryXpParity.hasExplicitCompletionEvidence(
      completed(at),[record(at.add(const Duration(minutes:5,seconds:1)))]),isFalse);
    expect(NativeHistoryXpParity.hasExplicitCompletionEvidence(
      completed(at),[record(at,skipped:true)]),isFalse);
    expect(NativeHistoryXpParity.hasExplicitCompletionEvidence(
      completed(at),[record(at,id:'different')]),isFalse);
    expect(NativeHistoryXpParity.hasExplicitCompletionEvidence(
      completed(null),[record(at)]),isFalse);
  });

  test('encrypted read-only projection retains group/XP evidence', () {
    final before = MediaFlowCatalog(categories: const [],
      library: [MediaFlowTitle.fromJson({
        'id':'t1','status':'completed',
        'completedAt':'2026-10-14T10:00:00Z'})],
      sessions: [MediaFlowSession.fromJson({
        'id':'s','sessionGroupId':'g','batchGroupId':'b',
        'healthStatus':'healthy','assignedCategoryId':'anime','xp':42,
      })]);
    final after = NativeOfflineProjectionCodec.decode(
        NativeOfflineProjectionCodec.encode(before));
    expect(after.library.single.completedAt,DateTime.utc(2026,10,14,10));
    expect(after.sessions.single.sessionGroupId,'g');
    expect(after.sessions.single.batchGroupId,'b');
    expect(after.sessions.single.healthStatus,'healthy');
    expect(after.sessions.single.assignedCategoryId,'anime');
    expect(after.sessions.single.xp,42);
  });

  test('100k sessions group efficiently without invented XP', () {
    final records=[for(var i=0;i<100000;i++)
      MediaFlowSession.fromJson({
        'id':'row-'+i.toString(),
        'sessionGroupId':'group-'+(i~/4).toString(),
        'date':'2026-10-14','status':'logged','xp':0,
      }),
    ];
    final watch=Stopwatch()..start();
    final result=NativeHistoryXpParity.analyze(records);
    expect(result.logicalActions,25000);
    expect(result.unresolvedXpRows,100000);
    expect(result.knownBaseXp,0);
    expect(result.knownStreakBonusXp,0);
    expect(records.last.xp,0);
    // ignore: avoid_print
    print('M23_100K_AUDIT_MS='+watch.elapsedMilliseconds.toString());
  },timeout:const Timeout(Duration(minutes:3)));
}
