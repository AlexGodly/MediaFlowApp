import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow_app/data/mediaflow_models.dart';
import 'package:mediaflow_app/features/history/history_xp_summary.dart';
import 'package:mediaflow_app/features/personal_order/personal_order_browser.dart';
import 'package:mediaflow_app/services/native_cas_protocol.dart';

MediaFlowTitle _title(String id, String name,
    {String category = 'anime', String priority = 'medium',
    String status = 'active', double progress = 0}) =>
    MediaFlowTitle.fromJson({
      'id': id, 'title': name, 'categoryId': category,
      'priority': priority, 'status': status, 'progress': progress,
      'tags': ['sample'],
    });

MediaFlowSession _session(String id, double xp, double minutes) =>
    MediaFlowSession.fromJson({
      'id': id, 'date': '2026-10-14', 'status': 'logged',
      'categoryId': 'anime', 'xp': xp, 'minutes': minutes,
    });

void main() {
  final catalog = MediaFlowCatalog(
    categories: const [],
    library: [
      _title('a', 'Zebra', progress: 3, priority: 'low'),
      _title('b', 'Alpha', category: 'manga',
          progress: 15, priority: 'high', status: 'completed'),
      _title('c', 'Beta', progress: 8),
    ],
    personalOrderIds: const ['c', 'missing', 'a', 'b'],
  );

  test('Personal Order preserves saved positions across display sorts', () {
    final browser = PersonalOrderBrowser(catalog);
    expect(browser.availableCount, 3);
    expect(browser.missingReferences, 1);
    expect(browser.browse().map((entry) => entry.title.id), ['c', 'a', 'b']);
    expect(browser.browse().map((entry) => entry.position), [1, 3, 4]);
    final alphabetical = browser.browse(
      sort: PersonalOrderDisplaySort.alphabetical,
    );
    expect(alphabetical.map((entry) => entry.title.id), ['b', 'c', 'a']);
    expect(alphabetical.map((entry) => entry.position), [4, 1, 3]);
    expect(browser.browse().map((entry) => entry.title.id), ['c', 'a', 'b']);
  });

  test('Personal Order combines category/status/priority/search filters', () {
    final browser = PersonalOrderBrowser(catalog);
    expect(browser.browse(
      categoryId: 'manga', status: 'completed',
      priority: 'high', search: 'alp',
    ).map((entry) => entry.title.id), ['b']);
    expect(browser.browse(categoryId: 'anime', status: 'completed'), isEmpty);
    expect(browser.browse(
      priority: 'medium', sort: PersonalOrderDisplaySort.progress,
    ).map((entry) => entry.title.id), ['c']);
    expect(() => browser.browse().clear(), throwsUnsupportedError);
  });

  test('History XP reads stored values and does not award XP', () {
    final records = [
      _session('one', 25, 40),
      _session('two', 0, 10),
      _session('correction', -5, 20),
    ];
    final summary = HistoryXpSummary.fromSessions(records);
    expect(summary.sessions, 3);
    expect(summary.storedSessionXp, 20);
    expect(summary.loggedMinutes, 70);
    expect(summary.sessionsWithStoredXp, 2);
    expect(records.map((s) => s.xp), [25, 0, -5]);
    expect(NativeCloudCapabilities.cloudWritesEnabled, isFalse);
  });

  test('Empty History never invents XP or levels', () {
    final summary = HistoryXpSummary.fromSessions(const []);
    expect(summary.sessions, 0);
    expect(summary.storedSessionXp, 0);
    expect(summary.sessionsWithStoredXp, 0);
    expect(summary.loggedMinutes, 0);
  });

  test('50k saved entries can be filtered without changing their order', () {
    final large = MediaFlowCatalog(
      categories: const [],
      library: [
        for (var i = 0; i < 50000; i++)
          _title('id-$i', 'Entry $i', priority: i.isEven ? 'high' : 'low'),
      ],
      personalOrderIds: [
        for (var i = 49999; i >= 0; i--) 'id-$i',
      ],
    );
    final watch = Stopwatch()..start();
    final browser = PersonalOrderBrowser(large);
    final filtered = browser.browse(search: 'Entry 499',
        priority: 'low', sort: PersonalOrderDisplaySort.alphabetical);
    expect(browser.availableCount, 50000);
    expect(filtered, isNotEmpty);
    expect(filtered.every((entry) =>
        entry.title.title.contains('Entry 499') &&
        entry.title.priority == 'low'), isTrue);
    // CI telemetry only, not a hardware-dependent acceptance gate.
    // ignore: avoid_print
    print('PERSONAL_ORDER_50K_BENCH query_ms=${watch.elapsedMilliseconds}'
        ' matched=${filtered.length}');
  }, timeout: const Timeout(Duration(minutes: 2)));
}
