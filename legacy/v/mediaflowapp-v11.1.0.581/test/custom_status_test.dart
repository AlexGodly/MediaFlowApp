// Custom Status: cleaning, schedules, times and the pinned title.

import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow/src/logic/custom_status.dart';

void main() {
  test('statuses are cleaned: types, links, buttons (max 2, https only)', () {
    final s = normalizeStatus({
      'type': 'dancing',
      'name': 'YouTube Music',
      'detailsUrl': 'http://insecure.example',
      'stateUrl': 'https://music.youtube.com/watch?v=x',
      'buttons': [
        {'label': 'Listen Along', 'url': 'https://music.youtube.com'},
        {'label': 'No link', 'url': ''},
        {'label': 'Two', 'url': 'https://a.example'},
        {'label': 'Three', 'url': 'https://b.example'},
      ],
      'partyCurrent': 2,
      'partyMax': 4,
      'extra': 'kept',
    });
    expect(s['type'], 'playing');
    expect(s['detailsUrl'], '');
    expect(s['stateUrl'], 'https://music.youtube.com/watch?v=x');
    expect((s['buttons'] as List).length, 2);
    expect((s['buttons'] as List).first, {'label': 'Listen Along', 'url': 'https://music.youtube.com'});
    expect(s['extra'], 'kept');
    expect(statusHasContent(s), isTrue);
    expect(statusHasContent(blankStatus()), isFalse);
  });

  test('a daily schedule window, including one that passes midnight', () {
    final evening = <String, dynamic>{'enabled': true, 'kind': 'daily', 'days': <int>[], 'from': '20:00', 'to': '22:00'};
    expect(scheduleWindowStart(evening, DateTime(2026, 11, 8, 21, 30)), DateTime(2026, 11, 8, 20));
    expect(scheduleWindowStart(evening, DateTime(2026, 11, 8, 22, 0)), isNull);
    final night = <String, dynamic>{'enabled': true, 'kind': 'daily', 'days': [6], 'from': '23:00', 'to': '02:00'}; // Saturday night
    expect(scheduleWindowStart(night, DateTime(2026, 11, 7, 23, 30)), DateTime(2026, 11, 7, 23)); // Sat
    expect(scheduleWindowStart(night, DateTime(2026, 11, 8, 1, 0)), DateTime(2026, 11, 7, 23)); // Sun 01:00, started Sat
    expect(scheduleWindowStart(night, DateTime(2026, 11, 8, 23, 30)), isNull); // Sunday night: not scheduled
    expect(scheduleWindowStart({...evening, 'enabled': false}, DateTime(2026, 11, 8, 21)), isNull);
    final once = <String, dynamic>{'enabled': true, 'kind': 'once', 'date': '2026-12-24', 'from': '18:00', 'to': '23:00'};
    expect(scheduleWindowStart(once, DateTime(2026, 12, 24, 19)), DateTime(2026, 12, 24, 18));
    expect(scheduleWindowStart(once, DateTime(2026, 12, 25, 19)), isNull);
  });

  test('applied status wins; schedules fill in; an absolute end ends it', () {
    final now = DateTime(2026, 11, 8, 21);
    final scheduled = <String, dynamic>{
      'id': 'p1',
      'name': 'Evening',
      'status': {'name': 'Night shift'},
      'schedule': {'enabled': true, 'kind': 'daily', 'from': '20:00', 'to': '22:00'},
    };
    final store = <String, dynamic>{
      'profiles': [scheduled],
    };
    final settings = <String, dynamic>{kCustomStatusKey: store};
    final s = currentCustomStatus(settings, now)!;
    expect(s.status['name'], 'Night shift');
    expect(s.source, 'schedule:Evening');
    expect(s.appliedAt, DateTime(2026, 11, 8, 20).millisecondsSinceEpoch);

    store['active'] = {'name': 'Manual', 'appliedAt': 5};
    expect(currentCustomStatus(settings, now)!.source, 'manual');

    store['active'] = {
      'name': 'Ended',
      'timeMode': 'absolute',
      'end': now.subtract(const Duration(minutes: 1)).millisecondsSinceEpoch,
      'appliedAt': 5,
    };
    expect(currentCustomStatus(settings, now)!.source, 'schedule:Evening', reason: 'an ended status gives way');
  });

  test('relative times are worked out from when the status was applied', () {
    final at = DateTime(2026, 11, 8, 12).millisecondsSinceEpoch;
    expect(statusTimes(normalizeStatus({'timeMode': 'relative', 'relStart': 12, 'relEnd': 3}), at),
        (start: at - 12 * 60000, end: at + 3 * 60000));
    expect(statusTimes(normalizeStatus({'timeMode': 'relative'}), at), (start: at, end: 0));
    expect(statusTimes(normalizeStatus({'timeMode': 'none', 'start': 5}), at), (start: 0, end: 0));
    expect(statusTimes(normalizeStatus({'timeMode': 'absolute', 'start': 10, 'end': 20}), at), (start: 10, end: 20));
  });

  test('a pinned title lasts until stopped, until its time, or for this run only', () {
    final now = DateTime(2026, 11, 8).millisecondsSinceEpoch;
    expect(activePin({'pinned': {'titleId': 't1', 'until': 0}}, now)?.titleId, 't1');
    expect(activePin({'pinned': {'titleId': 't1', 'until': now - 1}}, now), isNull);
    expect(activePin({'pinned': {'titleId': 't1', 'until': now + 1}}, now)?.titleId, 't1');
    expect(activePin({'pinned': {'titleId': 't1', 'session': kAppSessionId}}, now)?.titleId, 't1');
    expect(activePin({'pinned': {'titleId': 't1', 'session': 'another-run'}}, now), isNull);
    expect(activePin({'pinned': null}, now), isNull);
  });
}
