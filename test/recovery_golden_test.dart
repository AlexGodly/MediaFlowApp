// Metadata Recovery must propose and write exactly what the website does.
// Fixtures: tool/website_reference/generate_recovery_goldens.mjs runs the
// website's own v439 code (mf439Proposals / mf439Apply).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow/src/data/records.dart' show jsStringify;
import 'package:mediaflow/src/logic/recovery.dart';

void main() {
  final fx = jsonDecode(File('test/fixtures/recovery-golden.json').readAsStringSync()) as Map<String, dynamic>;

  for (final raw in fx['scenarios'] as List) {
    final sc = (raw as Map).cast<String, dynamic>();
    test('metadata recovery: ${sc['name']}', () {
      final item = (jsonDecode(jsonEncode(sc['item'])) as Map).cast<String, dynamic>();
      final rows = [for (final r in sc['rows'] as List) (jsonDecode(jsonEncode(r)) as Map).cast<String, dynamic>()];
      final preview = metadataProposals(item, rows);
      final select = (sc['select'] as Map?)?.cast<String, dynamic>() ?? const {};
      for (final p in preview.proposals) {
        if (select.containsKey(p.token)) {
          p.selected = true;
          p.choice = select[p.token] as int;
        }
      }
      final res = applyMetadata(item, preview, sc['now'] as int, automatic: sc['mode'] == 'automatic');
      final want = (sc['expected'] as Map).cast<String, dynamic>();
      expect(
        [
          for (final p in preview.proposals)
            {
              'token': p.token,
              'status': p.status,
              'selected': p.selected,
              'choice': p.choice,
              'options': p.options.length,
              'providers': [for (final s in p.options.first.sources) s.provider],
              'confidence': p.options.first.confidence,
            },
        ],
        want['proposals'],
      );
      expect([for (final e in preview.errors) e.$1], want['errors']);
      final r = (want['result'] as Map).cast<String, dynamic>();
      expect([res.changed, res.legacy, res.fields, res.ratings], [r['changed'], r['legacy'], r['fields'], r['ratings']]);
      expect(jsStringify(item), want['itemJson'], reason: 'saved title must be byte-identical');
    });
  }

  for (final raw in fx['coverLinks'] as List) {
    final lc = (raw as Map).cast<String, dynamic>();
    test('cover ID linking: ${lc['name']}', () {
      final item = (jsonDecode(jsonEncode(lc['item'])) as Map).cast<String, dynamic>();
      final cand = (lc['candidate'] as Map).cast<String, dynamic>();
      final entry = (lc['entry'] as Map).cast<String, dynamic>();
      final c = CoverCandidate(
        url: 'https://example.com/c.jpg',
        provider: cand['provider'] as String,
        title: item['title'] as String,
        confidence: 0.97,
        reason: '',
        recordId: cand['recordId'] as String,
        externalIdKey: cand['externalIdKey'] as String,
        recordUrl: cand['recordUrl'] as String,
        reportedIds: [
          if (entry['idMal'] != null) ('mal', '${entry['idMal']}'),
          if ((entry['externals'] as Map?)?['imdb'] != null) ('imdb', '${(entry['externals'] as Map)['imdb']}'),
        ],
      );
      final exp = (lc['expected'] as Map).cast<String, dynamic>();
      expect([for (final r in c.ids) [r.$1, r.$2]], exp['ids']);
      expect([for (final l in coverIdLinks(item, c)) {'key': l.key, 'value': l.value, 'existing': l.existing, 'conflict': l.conflict}], exp['links']);
      final q = quickCoverLink(item, c);
      expect({'key': q.key, 'id': q.id, 'canLink': q.canLink}, exp['quick'], reason: 'Quick Title Recovery link');
      expect(linkCoverIds(item, c, manual: lc['manual'] as bool), exp['changes']);
      expect(jsStringify(item), exp['itemJson']);
    });
  }

  test('cover evidence follows the website rules', () {
    final item = <String, dynamic>{'title': 'Frieren', 'year': 2023};
    expect(coverEvidence(item, 'Frieren', 2023).confidence, 0.97);
    expect(coverEvidence(item, 'frieren', null).confidence, 0.89);
    expect(coverEvidence(item, 'Frieren', 2019).confidence, 0.48);
    expect(coverEvidence(item, 'Frieren: Beyond', 2023).confidence, 0);
  });

  test('provider settings are written like the website', () {
    final saved = metadataSettingsToSave({'v439Metadata': {'enabled': ['jikan'], 'custom': 1}}, ['tmdb', 'anilist', 'jikan'], 40);
    expect(saved.keys.toList(), ['enabled', 'batchSize', 'maxBatch', 'minimumConfidence', 'manualReview', 'custom']);
    expect(saved['enabled'], ['jikan', 'anilist', 'tmdb'], reason: 'listed in the website order');
    expect(saved['maxBatch'], 40);
    final presets = presetsToSave({'v453RecoveryPresets': {'anime': {'cover': ['tenrai']}}}, 'anime', ['jikan', 'jikan', 'nope']);
    expect(presets, {'anime': {'cover': ['tenrai'], 'metadata': ['jikan']}});
    expect(presetsToSave({'v453RecoveryPresets': {'anime': {'metadata': ['jikan']}}}, 'anime', null), isEmpty);
  });
}
