import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow_app/data/mediaflow_full_state.dart';
import 'package:mediaflow_app/services/native_cas_protocol.dart';
import 'package:mediaflow_app/services/native_snapshot_codec.dart';

void main() {
  final fixtureFile = File('test/fixtures/m28_v410_lossless_sample.json');

  Map<String, dynamic> example() =>
      jsonDecode(fixtureFile.readAsStringSync()) as Map<String, dynamic>;

  test('complete source structure, root keys and all 38 default settings', () {
    final raw = example();
    final state = MediaFlowFullState.parse(raw);
    final info = state.inspect();
    expect(NativeSnapshotCodec.equivalent(state.json, raw), isTrue);
    expect(info.libraryCount, 2);
    expect(info.sessionCount, 1);
    expect(info.collectionCount, 1);
    expect(info.orderTitleCount, 2);
    expect(info.settingsKeys.length, greaterThanOrEqualTo(38));
    expect(info.unrecognizedRoots, contains('v410UnknownRoot'));
    expect(state.containsRoot('v410UnknownRoot'), isTrue);
    expect(state.containsRoot('noSuchRoot'), isFalse);
    expect(state.at(['library', 0, 'providerMetadata', 'malId']), 1977);
    expect(state.at(['library', 0, 'seasons', 0, 'futureSeason',
      'providerIds', 'one']), 543);
    expect(state.at(['sessions', 0, 'titles', 0, 'v369Units', 0,
      'unknownUnit']), [5, 4, 3]);
    expect(state.at(['settings','leveling','futureLedgerConfig','keys']),
      ['k2', 'k1']);
    expect(state.at(['orderPlan','unknownQueue','deep','k']), 'v');
    expect(state.at(['library',1,'extraNull']), isNull);
  });

  test('defensive deep copies prevent mutation through getters and paths', () {
    final state = MediaFlowFullState.parse(example());
    final data = state.json;
    (data['library'] as List).clear();
    ((state.at(['xpLedger']) as Map)['libraryAdditions'] as Map).clear();
    ((state.originalWire as Map)['settings'] as Map).clear();
    expect(state.inspect().libraryCount, 2);
    expect(state.at(['xpLedger','libraryAdditions','v410-1']), 10);
    expect(state.at(['settings','theme']), 'dark');
  });

  test('plain JSONB preserves all nested unknowns and timestamp precision', () {
    final raw = example();
    final state = MediaFlowFullState.parse(raw);
    expect(state.format, MediaFlowWireFormat.jsonObject);
    final encoded = state.encodeForLocalParityTest();
    expect(encoded, isA<Map>());
    expect(NativeSnapshotCodec.equivalent(raw, encoded), isTrue);
    expect(state.at(['sessions',0,'timestamp']),
        '2026-10-01T12:34:56.123+01:00');
  });

  test('string JSON account format round-trips unchanged', () {
    final text = jsonEncode(example());
    final state = MediaFlowFullState.parse(text);
    expect(state.format, MediaFlowWireFormat.jsonString);
    expect(state.encodeForLocalParityTest(), text);
    expect(NativeSnapshotCodec.equivalent(
      jsonDecode(state.encodeForLocalParityTest() as String), example()
    ), isTrue);
  });

  test('gzip envelope metadata and nested opaque fields survive unchanged', () {
    final raw = example();
    final envelope = <String, dynamic>{
      '__mediaflowCompressed': 'gzip',
      'data': base64Encode(gzip.encode(utf8.encode(jsonEncode(raw)))),
      'futureEnvelopeExtension': {'digest': 'keep', 'order': [3,1,2]},
    };
    final state = MediaFlowFullState.parse(envelope);
    expect(state.format, MediaFlowWireFormat.gzipEnvelope);
    expect(state.encodeForLocalParityTest(), envelope);
    final preview = state.simulateScalarReplacement(
      ['library', 0, 'priority'], 'medium');
    final packed = preview.encodeForLocalParityTest();
    expect(packed, isA<Map>());
    expect((packed as Map)['futureEnvelopeExtension'],
      envelope['futureEnvelopeExtension']);
    final decoded = MediaFlowFullState.parse(packed);
    expect(decoded.at(['library',0,'priority']), 'medium');
    expect(decoded.at(['library',0,'providerMetadata','customArray']),
      [null,true,2.5,{'future':'value'}]);
    expect(decoded.at(['settings','unknownFutureSetting']),
      {'map': {'array': [1, false, null]}});
    expect(state.at(['library',0,'priority']), 'high');
  });

  test('simulated scalar edits preserve all other roots and nested records', () {
    final before = MediaFlowFullState.parse(example());
    final changed = before.simulateScalarReplacement(
      ['settings','leveling','collectionAddTitleXP'], 99);
    expect(changed.isLocalSimulation, isTrue);
    final after = MediaFlowFullState.parse(changed.encodeForLocalParityTest());
    expect(after.at(['settings','leveling','collectionAddTitleXP']), 99);
    expect(after.at(['settings','leveling','futureLedgerConfig']),
      {'keys':['k2','k1']});
    expect(after.at(['xpLedger']), before.at(['xpLedger']));
    expect(after.at(['activityLog']), before.at(['activityLog']));
    expect(after.at(['orderPlan']), before.at(['orderPlan']));
    expect(after.at(['completionTimeline']), before.at(['completionTimeline']));
    expect(after.at(['collections']), before.at(['collections']));
    expect(after.at(['library']), before.at(['library']));
    expect(after.at(['v410UnknownRoot']), before.at(['v410UnknownRoot']));
    expect(after.at(['settings','leveling','collectionAddTitleXP']),
      isNot(before.at(['settings','leveling','collectionAddTitleXP'])));
  });

  test('refuses empty, corrupted, ambiguous or destructive state', () {
    for (final invalid in [
      null, <String,dynamic>{}, {'library': [], 'categories': []},
      {'library': 'not-an-array', 'categories': [], 'sessions': [],
       'settings': {}},
      {'library': [null], 'categories': [], 'sessions': [],
       'settings': {}},
      {'library': [], 'categories': [], 'sessions': [],
       'settings': <String, dynamic>{}, 'orderPlan': {'titleIds':'bad'}},
      {'__mediaflowCompressed':'brotli', 'data':'abc'},
      {'__mediaflowCompressed':'gzip', 'data':'invalid'},
    ]) {
      expect(() => MediaFlowFullState.parse(invalid), throwsFormatException);
    }
  });

  test('simulation refuses object replacement, insertion and array resizing', () {
    final state = MediaFlowFullState.parse(example());
    final bad = <List<Object>>[
      ['library',0,'missingField'], ['library',12,'priority'],
      ['settings','neverSeen'], ['library',0,'seasons'],
      ['settings','leveling'], ['collections',0,'titleIds'],
      ['settings','leveling','futureLedgerConfig','newKey'],
      ['library',0,'priority',0], ['sessions',0,'titles',1,'qty'],
    ];
    for (final path in bad) {
      expect(() => state.simulateScalarReplacement(path, 'x'),
          throwsFormatException, reason: path.toString());
    }
    expect(() => state.simulateScalarReplacement(
      ['library',0,'priority'], ['low']), throwsFormatException);
    expect(() => state.simulateScalarReplacement(
      ['library',0,'priority'], 'high'), throwsFormatException);
    expect(() => state.simulateScalarReplacement(
      ['library',0,'progress'], double.nan), throwsFormatException);
    expect(state.at(['library',0,'priority']), 'high');
    expect(NativeCloudCapabilities.cloudWritesEnabled, isFalse);
    expect(NativeCloudCapabilities.hasServerSideCas, isFalse);
    expect(NativeCloudCapabilities.offlineWriteQueueEnabled, isFalse);
  });

  test('existing read-only catalog is deliberately not a lossless save model', () {
    final full = MediaFlowFullState.parse(example());
    final projected = full.readOnlyCatalog();
    expect(projected.library, hasLength(2));
    expect(projected.library.first.seasons, hasLength(2));
    expect(projected.sessions.first.titles.first.units, hasLength(1));
    expect(full.at(['library',0,'providerMetadata','malId']), 1977);
    expect(full.at(['settings','unknownFutureSetting']), isNotNull);
    expect(full.at(['xpLedger','v348ActionEvents','a1']), 12);
  });

  test('large synthetic raw library remains intact after local roundtrip', () {
    final raw = example();
    final titles = raw['library'] as List;
    for (var i = 0; i < 15000; i++) {
      titles.add({
        'id': 'synthetic-$i', 'title': 'Title $i',
        'seasons': [{'number': 1, 'progress': 0, 'total': 12,
          'unknown': {'index': i}}],
        'unknownFuture': [i, null, {'flag': i.isEven}],
      });
    }
    final full = MediaFlowFullState.parse(raw);
    expect(full.inspect().libraryCount, 15002);
    final result = MediaFlowFullState.parse(full.encodeForLocalParityTest());
    expect(result.inspect().libraryCount, 15002);
    expect(result.at(['library', 15001, 'unknownFuture']),
      [14999, null, {'flag': false}]);
  });
}
