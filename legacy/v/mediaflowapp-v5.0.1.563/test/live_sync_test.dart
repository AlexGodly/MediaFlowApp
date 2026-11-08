// 3.0.0: time in the app earns XP like time on the website, and the logging
// draft follows the website live on per-record accounts.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow/src/data/account_controller.dart';
import 'package:mediaflow/src/data/account_ops.dart';
import 'package:mediaflow/src/data/sync_engine.dart';
import 'package:mediaflow/src/logic/resume.dart';
import 'package:mediaflow/src/logic/stats.dart';
import 'package:mediaflow/src/state/state_codec.dart';
import 'package:mediaflow/src/util/js.dart';

import 'support/fakes.dart';

Map<String, dynamic> _account() {
  final fx = jsonDecode(File('test/fixtures/log-mixed-batch.json').readAsStringSync()) as Map;
  return deepCopyState((fx['before'] as Map).cast<String, dynamic>());
}

void main() {
  test('app time earns XP per minute with the streak multiplier, apart from website time', () {
    final s = _account();
    final now = DateTime.utc(2026, 11, 7, 12).millisecondsSinceEpoch;
    final day = isoDateUtc(now);
    final before = xpMetrics(s).total;
    AppTimeOp(id: 'a', day: day, ms: 10 * 60000, platform: 'android', at: now).apply(s);
    AppTimeOp(id: 'b', day: day, ms: 5 * 60000, platform: 'windows', at: now + 1).apply(s);
    final row = asMap(asMap(asMap(s['xpLedger'])!['v561AppTimeDays'])![day])!;
    expect(row['ms'], 15 * 60000);
    expect(asMap(row['platforms']), {'android': 600000, 'windows': 300000});
    final mult = jsNum(row['multiplier']);
    expect(row['xp'], (15 * 2 * mult + 1e-8).floor(), reason: '2 XP a minute (website default) × streak multiplier');
    final m = xpMetrics(s);
    expect(m.total - before, row['xp']);
    expect(m['appActiveMs'], 15 * 60000);
    expect(m['appMs.android'], 600000);
    expect(asMap(asMap(s['xpLedger'])!['v334ActiveTimeDays'])?[day], isNull, reason: 'website time untouched');
  });

  test('app time from two devices adds up after sync', () async {
    final cloud = FakeRecordCloud(_account());
    final first = await syncOnce(cloud, 'u', const [], background: runInline);
    final now = DateTime.utc(2026, 11, 7, 12).millisecondsSinceEpoch;
    final day = isoDateUtc(now);
    final a = await syncOnce(cloud, 'u', [AppTimeOp(id: 'p', day: day, ms: 60000, platform: 'android', at: now)],
        knownRaw: first.raw, knownIndex: first.index, background: runInline);
    expect(a.uploaded, 1);
    // A second device that had not seen the first one's minute yet.
    await syncOnce(cloud, 'u', [AppTimeOp(id: 'w', day: day, ms: 120000, platform: 'windows', at: now + 5)],
        knownRaw: first.raw, knownIndex: first.index, background: runInline);
    final row = asMap(asMap(asMap(cloud.recordState['xpLedger'])!['v561AppTimeDays'])![day])!;
    expect(row['ms'], 180000);
  });

  test('a draft typed on the website shows up on the open log page within seconds', () async {
    final cloud = FakeRecordCloud(_account());
    final account = AccountController(
      userId: 'u',
      email: 'e',
      cloud: cloud,
      cache: MemoryCache(),
      background: runInline,
      fallbackInterval: Duration.zero,
      deviceId: 'test-device',
    );
    await account.start();
    expect(account.usesRecords, isTrue);
    final at = DateTime.now().millisecondsSinceEpoch + 1000;
    final task = {'id': 'task_live', 'categoryId': 'anime', 'title': 'Live'};
    cloud.websiteSavesRecords((s) {
      final resume = asMap(s['resumeStateV285']) ?? <String, dynamic>{};
      s['resumeStateV285'] = {
        ...resume,
        'logging': activeLogging(task: task, logDraft: {'note': 'from the website'}, entryDraft: {}, modifiedAt: at),
      };
    });
    final changed = await account.pullDraftNow();
    expect(changed, isTrue);
    final logging = readLogging(account.view!.state)!;
    expect(logging['active'], isTrue);
    expect(asMap(logging['logDraft'])!['note'], 'from the website');
    expect(await account.pullDraftNow(), isFalse, reason: 'the same draft is not taken twice');
    account.dispose();
  });

  test('a draft typed in the app reaches the website records without a full sync', () async {
    final cloud = FakeRecordCloud(_account());
    final account = AccountController(
      userId: 'u',
      email: 'e',
      cloud: cloud,
      cache: MemoryCache(),
      background: runInline,
      fallbackInterval: Duration.zero,
      deviceId: 'test-device',
      liveDraftDelay: Duration.zero,
    );
    await account.start();
    final at = DateTime.now().millisecondsSinceEpoch + 1000;
    final task = {'id': 'task_app', 'categoryId': 'anime', 'title': 'App'};
    await account.saveDraft(activeLogging(task: task, logDraft: {'note': 'from the app'}, entryDraft: {}, modifiedAt: at));
    for (var n = 0; n < 50; n++) {
      final logging = readLogging(cloud.recordState);
      if (logging != null && asMap(logging['logDraft'])?['note'] == 'from the app') break;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    final site = readLogging(cloud.recordState)!;
    expect(asMap(site['logDraft'])!['note'], 'from the app');
    expect(jsNum(site['modifiedAt']), at);
    account.dispose();
  });
}
