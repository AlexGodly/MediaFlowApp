// 7.0.0.567 contract: logs keep their real time, Consuming…, Discord title
// names, ratings from Details Recovery and the refresh rule (website v566/v567).

import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow/src/logic/consuming.dart';
import 'package:mediaflow/src/logic/log_times.dart';
import 'package:mediaflow/src/logic/ratings_engine.dart';
import 'package:mediaflow/src/logic/recovery.dart';
import 'package:mediaflow/src/util/js.dart';

void main() {
  const day = 86400000;
  final now = DateTime.utc(2026, 11, 13, 12).millisecondsSinceEpoch;

  group('log times', () {
    final t0 = now - 2 * day, t1 = now - day;
    Map<String, dynamic> session() => {
          'id': 's1',
          'timestamp': now,
          'date': isoDateUtc(now),
          'status': 'complete',
          'xp': 100,
          'actualAmount': 4,
          'minutes': 80,
          'v369DurationSeconds': 4800,
          'sessionGroupId': 'g1',
          'titles': [
            {
              'title': 'A',
              'libraryId': 'L1',
              'qty': 4,
              'loggedAt': t0,
              'v369Units': [
                {'id': 'u1', 'loggedAt': t0, 'durationSeconds': 1200},
                {'id': 'u2', 'loggedAt': t0 + 60000, 'durationSeconds': 1200},
                {'id': 'u3', 'loggedAt': t1, 'durationSeconds': 1200},
                {'id': 'u4', 'loggedAt': now, 'durationSeconds': 1200},
              ],
            },
          ],
        };

    test('each unit counts on its own day; totals unchanged', () {
      final parts = redateSession(session(), {'id:L1': t0}, 'unit', now);
      expect(parts.map((p) => p['date']), [isoDateUtc(t0), isoDateUtc(t1), isoDateUtc(now)]);
      expect(parts.map((p) => p['id']), ['s1_d1', 's1_d2', 's1']);
      expect(parts.map((p) => jsNum(p['xp'])), [50, 25, 25]);
      expect(parts.fold<double>(0, (n, p) => n + jsNum(p['actualAmount'])), 4);
      expect(parts.map((p) => jsNum(p['minutes'])), [40, 20, 20]);
      expect(parts.map((p) => p['status']), ['logged', 'logged', 'complete']);
      expect(parts.map((p) => (p['mf566Split'] as Map)['part']), [1, 2, 3]);
    });

    test('"when added": the whole title on the day it was added', () {
      final parts = redateSession(session(), {'id:L1': t0}, 'added', now);
      expect(parts.length, 1);
      expect(parts.first['date'], isoDateUtc(t0));
    });

    test('a log all on its save day is left as it was', () {
      final s = session();
      (s['titles'] as List).first['v369Units'] = [
        {'id': 'u1', 'loggedAt': now - 3600000, 'durationSeconds': 1200},
      ];
      final parts = redateSession(s, {'id:L1': now - 3600000}, 'unit', now);
      expect(parts.single['timestamp'], now);
      expect(parts.single.containsKey('mf566SavedAt'), false);
    });

    test('setting default', () {
      expect(logTimeMode(null), 'unit');
      expect(logTimeMode({'mf566LogTime': 'added'}), 'added');
    });
  });

  group('Consuming…', () {
    final task = {
      'libraryId': 'R2',
      'v180RecommendationHistory': [
        {'libraryId': 'R1'},
        {'libraryId': 'R2'},
      ],
    };
    final draft = {
      'entries': [
        {'libraryId': 'A', 'loggedAt': 10, 'v369UpdatedAt': 50},
        {'libraryId': 'B', 'loggedAt': 20},
      ],
    };
    test('sources', () {
      expect(consumingTitleId({}, task, draft, now), 'A', reason: 'default: last edited');
      expect(consumingTitleId({'consumingSource': 'reroll'}, task, draft, now), 'R2');
      expect(consumingTitleId({'consumingSource': 'recommended'}, task, draft, now), 'R1');
      expect(consumingTitleId({'consumingSource': 'assigned'}, task, draft, now), null);
      expect(consumingTitleId({}, null, null, now), null, reason: 'no open log');
    });
    test('a chosen title wins; Clear hides the shown title until the source moves on', () {
      final pinned = {'pinned': {'titleId': 'P', 'until': 0, 'session': ''}};
      expect(consumingTitleId(pinned, task, draft, now), 'P');
      final cleared = clearedConsuming(pinned, 'P', now);
      expect(cleared['pinned'], null);
      expect(consumingTitleId(cleared, task, draft, now), 'A', reason: 'the source shows another title');
      final clearedA = clearedConsuming({}, 'A', now);
      expect(consumingTitleId(clearedA, task, draft, now), null, reason: 'Stop / Clear: back to the normal status');
    });
  });

  group('Discord title names', () {
    final item = {
      'id': 'T',
      'title': 'Sousou no Frieren',
      'titleEnglish': 'Frieren: Beyond Journey\'s End',
      'categoryId': 'anime',
    };
    final english = {
      'mf565TitleNames': {'global': 'en', 'categories': {}},
    };
    test('follows MediaFlow by default, or always the main name', () {
      expect(discordTitleName(item, settings: english, config: {}), 'Frieren: Beyond Journey\'s End');
      expect(discordTitleName(item, settings: english, config: {'titleName': 'main'}), 'Sousou no Frieren');
    });
    test('a Discord-only name, while consuming or kept for the title', () {
      final c1 = withDiscordName({}, 'T', custom: 'Frieren ✨');
      expect(discordTitleName(item, settings: english, config: c1, consuming: true), 'Frieren ✨');
      expect(discordTitleName(item, settings: english, config: c1), 'Frieren: Beyond Journey\'s End', reason: 'only while consuming');
      final c2 = withDiscordName({}, 'T', lang: 'main', keep: true);
      expect(discordTitleName(item, settings: english, config: c2), 'Sousou no Frieren');
      expect(item['title'], 'Sousou no Frieren', reason: 'the title itself never changes');
    });
  });

  group('ratings from Details Recovery', () {
    FieldProposal ratingProposal({Object? original, bool update = false}) => FieldProposal(
          token: 'rating.mal',
          label: 'MAL rating',
          options: [
            FieldOption({'score': 8.4, 'scale': 10, 'votes': null}, 1)..sources.add(FieldSource('jikan', 'r1', 'Frieren', 'Exact title', 1)),
          ],
          original: original,
          hasOriginal: false,
          isProtected: false,
          disagree: false,
          same: false,
          selected: true,
          status: update ? 'update' : 'ready',
          ratingUpdate: update,
        );

    test('a filled rating is marked as a recovery rating', () {
      final item = <String, dynamic>{'id': 'm1', 'title': 'Frieren'};
      applyMetadata(item, MetadataPreview('m1', 'Frieren', [ratingProposal()], const [], const ['jikan']), now);
      final prov = ((item['universalMetadata'] as Map)['provenance'] as Map)['rating.mal'] as Map;
      expect(prov['via'], 'recovery');
    });

    test('an automatic rating with a newer value is updated', () {
      final item = <String, dynamic>{
        'id': 'm1',
        'title': 'Frieren',
        'universalMetadata': {
          'externalRatings': {'mal': {'score': 7, 'scale': 10, 'votes': null, 'source': 'simkl'}},
          'provenance': {'rating.mal': {'source': 'simkl', 'verified': true}},
        },
      };
      applyMetadata(item, MetadataPreview('m1', 'Frieren', [ratingProposal(original: {'score': 7, 'scale': 10}, update: true)], const [], const ['jikan']), now);
      final env = item['universalMetadata'] as Map;
      expect(jsNum(((env['externalRatings'] as Map)['mal'] as Map)['score']), 8.4);
      expect(((env['provenance'] as Map)['rating.mal'] as Map)['via'], 'recovery');
    });

    test('refresh: a recovery rating takes a newer value from any source; others keep their rule', () {
      Map<String, dynamic> item(String? via) => {
            'id': 'x',
            'title': 'X',
            'universalMetadata': {
              'externalRatings': {'mal': {'score': 8.1, 'scale': 10, 'votes': null, 'source': 'jikan'}},
              'provenance': {'rating.mal': {'source': 'jikan', 'verified': true, 'recordId': 'r1', if (via != null) 'via': via}},
            },
          };
      final found = RatingsFound([
        {'provider': 'simkl', 'recordId': 's9', 'ratings': {'mal': {'score': 8.3, 'scale': 10}}},
      ], const {}, const [], const []);
      final a = item('recovery');
      applyRatings(a, found, now);
      expect(jsNum(((a['universalMetadata'] as Map)['externalRatings'] as Map)['mal']['score']), 8.3);
      final b = item(null);
      applyRatings(b, found, now);
      expect(jsNum(((b['universalMetadata'] as Map)['externalRatings'] as Map)['mal']['score']), 8.1);
      final c = item('recovery');
      applyRatings(c, RatingsFound(const [], const {}, const [], const []), now);
      expect(jsNum(((c['universalMetadata'] as Map)['externalRatings'] as Map)['mal']['score']), 8.1, reason: 'nothing new: kept');
    });
  });
}
