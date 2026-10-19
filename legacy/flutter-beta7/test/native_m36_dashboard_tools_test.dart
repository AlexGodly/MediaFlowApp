import 'package:flutter_test/flutter_test.dart';

import 'package:mediaflow_app/services/native_m36_dashboard_tools.dart';

void main() {
  test('v256 normalization clamps hours minutes and seconds', () {
    final normalized=NativeM36Duration.normalized(100000,-2,99);
    expect(normalized.hours,99999);
    expect(normalized.minutes,0);
    expect(normalized.seconds,59);
    expect(normalized.totalSeconds,99999*3600+59);
    expect(NativeM36Duration.fromSeconds(3661).clock,'01:01:01');
    expect(NativeM36Duration.fromSeconds(-1).clock,'00:00:00');
    expect(() => normalized.withField('unsafe',2),throwsFormatException);
  });

  test('v256 carry-forward sums and preserves runtime counts', () {
    final c=NativeM36RuntimeCalculator();
    addTearDown(c.dispose);
    c.edit('chain',0,'m','42');
    c.edit('chain',1,'m','18');
    expect(c.calculate(),true);
    expect(c.resultSeconds,3600);
    expect(c.resultCount,2);
    expect(c.proposedLoggingMinutes,60);
    c.continueResult();
    expect(c.chain.first.clock,'01:00:00');
    expect(c.chain.last.totalSeconds,0);
    expect(c.carryCount,2);
    c.edit('chain',1,'m','30');
    expect(c.calculate(),true);
    expect(c.resultSeconds,5400);
    expect(c.resultCount,3);
    expect(c.previousAccumulatorSeconds,3600);
    c.previousTotal();
    expect(c.resultSeconds,3600);
    expect(c.resultCount,2);
    expect(c.chain.first.clock,'01:00:00');
  });

  test('v256 multi-row sums only non-zero rows and allows extras', () {
    final c=NativeM36RuntimeCalculator();
    addTearDown(c.dispose);
    c.switchMode(NativeM36RuntimeMode.multi);
    expect(c.calculate(),false);
    c.edit('multi',0,'h','1');
    c.edit('multi',1,'s','30');
    c.addRow();
    c.edit('multi',2,'m','2');
    expect(c.rows.length,3);
    expect(c.calculate(),true);
    expect(c.resultSeconds,3750);
    expect(c.resultCount,3);
    expect(c.previousAccumulatorSeconds,0);
    c.removeRow(1);
    expect(c.rows.length,2);
    expect(c.calculate(),true);
    expect(c.resultSeconds,3720);
    expect(c.resultCount,2);
    expect(() => c.removeRow(0),throwsStateError);
    c.clear();
    expect(c.hasResult,false);
    expect(c.rows.length,2);
  });

  test('half-up rounded minutes match v256 Math.round output', () {
    final c=NativeM36RuntimeCalculator();
    addTearDown(c.dispose);
    c.edit('chain',0,'s','29');
    c.calculate();
    expect(c.proposedLoggingMinutes,0);
    c.edit('chain',0,'s','30');
    c.calculate();
    expect(c.proposedLoggingMinutes,1);
    c.edit('chain',0,'m','1');
    c.calculate();
    expect(c.proposedLoggingMinutes,2);
  });

  test('carry mode change seeds from first two multi-row values', () {
    final c=NativeM36RuntimeCalculator();
    addTearDown(c.dispose);
    c.switchMode(NativeM36RuntimeMode.multi);
    c.edit('multi',0,'m','5');
    c.edit('multi',1,'s','50');
    c.switchMode(NativeM36RuntimeMode.chain);
    expect(c.chain.first.totalSeconds,300);
    expect(c.chain.last.totalSeconds,50);
    expect(c.calculate(),true);
    expect(c.resultSeconds,350);
  });

  test('runtime state cannot be serialized into cloud writes', () {
    final c=NativeM36RuntimeCalculator();
    addTearDown(c.dispose);
    c.edit('chain',0,'m','10');
    c.calculate();
    expect(c.proposedLoggingMinutes,10);
    c.clear();
    expect(c.proposedLoggingMinutes,isNull);
    expect(() => c.edit('cloud',0,'h','1'),throwsFormatException);
    expect(() => c.edit('chain',9,'h','1'),throwsFormatException);
  });

  test('stopwatch pauses, resumes, resets without accumulating paused time',
      () async {
    final watch=NativeM36Stopwatch();
    watch.start();
    expect(watch.isRunning,true);
    await Future<void>.delayed(const Duration(milliseconds:40));
    watch.pause();
    expect(watch.isRunning,false);
    final paused=watch.elapsed;
    await Future<void>.delayed(const Duration(milliseconds:40));
    expect(watch.elapsed,paused);
    watch.start();
    await Future<void>.delayed(const Duration(milliseconds:40));
    watch.pause();
    expect(watch.elapsed,greaterThan(paused));
    watch.reset();
    expect(watch.elapsed,Duration.zero);
    watch.dispose();
  });
}
