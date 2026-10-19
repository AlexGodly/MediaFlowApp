import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// Account-shell-local Dashboard tools. Never serializes into v410 cloud state,
/// logging, History, or XP. Numeric rules mirror v256 runtime calculator.
enum NativeM36RuntimeMode { chain, multi }

class NativeM36Duration {
  const NativeM36Duration(this.hours, this.minutes, this.seconds);
  const NativeM36Duration.zero() : hours = 0, minutes = 0, seconds = 0;

  final int hours, minutes, seconds;

  factory NativeM36Duration.normalized(int hours, int minutes, int seconds) =>
    NativeM36Duration(
      hours.clamp(0, 99999).toInt(), minutes.clamp(0, 59).toInt(),
      seconds.clamp(0, 59).toInt());

  factory NativeM36Duration.fromSeconds(int seconds) {
    final valid = math.max(0, seconds);
    return NativeM36Duration(
      valid ~/ 3600, (valid % 3600) ~/ 60, valid % 60);
  }

  int get totalSeconds => hours * 3600 + minutes * 60 + seconds;
  String get clock => '${hours.toString().padLeft(2, '0')}:'
      '${minutes.toString().padLeft(2, '0')}:'
      '${seconds.toString().padLeft(2, '0')}';

  NativeM36Duration withField(String field, int value) {
    if (!const {'h','m','s'}.contains(field)) {
      throw const FormatException('Unknown runtime field');
    }
    return NativeM36Duration.normalized(
      field == 'h' ? value : hours,
      field == 'm' ? value : minutes,
      field == 's' ? value : seconds);
  }
}

/// This is the original website v256 chain/multi semantics: nonzero rows
/// count toward the result, chain carries its cumulative item count forward.
class NativeM36RuntimeCalculator extends ChangeNotifier {
  NativeM36RuntimeMode mode = NativeM36RuntimeMode.chain;
  List<NativeM36Duration> chain = [
    const NativeM36Duration.zero(), const NativeM36Duration.zero()];
  List<NativeM36Duration> rows = [
    const NativeM36Duration.zero(), const NativeM36Duration.zero()];
  int resultSeconds = 0;
  int resultCount = 0;
  int carryCount = 0;
  int previousAccumulatorSeconds = 0;
  int previousAccumulatorCount = 0;
  bool hasResult = false;
  int inputRevision = 0;

  void edit(String scope, int index, String field, String input) {
    final collection = scope == 'chain' ? chain : scope == 'multi' ? rows : null;
    if (collection == null || index < 0 || index >= collection.length) {
      throw const FormatException('Invalid runtime position');
    }
    final value = int.tryParse(input.trim()) ?? 0;
    collection[index] = collection[index].withField(field, value);
    // Avoid rebuilding a live TextFormField on every keystroke.
  }

  void switchMode(NativeM36RuntimeMode next) {
    if (next == mode) return;
    if (next == NativeM36RuntimeMode.multi) {
      rows = chain.any((v) => v.totalSeconds > 0)
          ? List.of(chain) : [
              const NativeM36Duration.zero(),const NativeM36Duration.zero()];
    } else {
      chain = [
        rows[0],rows.length > 1 ? rows[1] : const NativeM36Duration.zero()];
    }
    mode = next;
    inputRevision++;
    notifyListeners();
  }

  void addRow() {
    if (rows.length >= 100) throw StateError('Maximum 100 runtime rows');
    mode = NativeM36RuntimeMode.multi;
    rows.add(const NativeM36Duration.zero());
    inputRevision++;
    notifyListeners();
  }

  void removeRow(int index) {
    if (rows.length <= 2 || index < 0 || index >= rows.length) {
      throw StateError('Multi-row mode requires two rows');
    }
    rows.removeAt(index);
    inputRevision++;
    notifyListeners();
  }

  bool calculate() {
    if (mode == NativeM36RuntimeMode.multi) {
      final values = rows.map((v) => v.totalSeconds).toList();
      final count = values.where((v) => v > 0).length;
      if (count == 0) return false;
      resultSeconds = values.fold(0, (a,b) => a+b);
      resultCount = count;
      carryCount = 0;
      previousAccumulatorSeconds = 0;
      previousAccumulatorCount = 0;
    } else {
      final a = chain[0].totalSeconds, b = chain[1].totalSeconds;
      if (a <= 0 && b <= 0) return false;
      final firstCount = carryCount > 0 ? carryCount : (a > 0 ? 1 : 0);
      previousAccumulatorSeconds = a;
      previousAccumulatorCount = firstCount;
      resultSeconds = a + b;
      resultCount = firstCount + (b > 0 ? 1 : 0);
    }
    hasResult = true;
    notifyListeners();
    return true;
  }

  void continueResult() {
    if (!hasResult) throw StateError('Calculate a result first');
    mode = NativeM36RuntimeMode.chain;
    chain = [
      NativeM36Duration.fromSeconds(resultSeconds),
      const NativeM36Duration.zero()];
    carryCount = math.max(1,resultCount);
    inputRevision++;
    notifyListeners();
  }

  void previousTotal() {
    if (!hasResult || previousAccumulatorSeconds <= 0) {
      throw StateError('No previous accumulated runtime');
    }
    final previous = previousAccumulatorSeconds;
    final count = math.max(1,previousAccumulatorCount);
    mode = NativeM36RuntimeMode.chain;
    chain = [
      NativeM36Duration.fromSeconds(previous),
      const NativeM36Duration.zero()];
    resultSeconds = previous;
    resultCount = count;
    carryCount = count;
    inputRevision++;
    notifyListeners();
  }

  /// v256 uses Math.round(seconds/60), including half-up; local output only.
  int? get proposedLoggingMinutes =>
      hasResult ? ((resultSeconds + 30) ~/ 60) : null;

  void clear() {
    mode = NativeM36RuntimeMode.chain;
    chain = [const NativeM36Duration.zero(),const NativeM36Duration.zero()];
    rows = [const NativeM36Duration.zero(),const NativeM36Duration.zero()];
    resultSeconds = 0;resultCount = 0;carryCount = 0;
    previousAccumulatorSeconds = 0;previousAccumulatorCount = 0;
    hasResult = false;
    inputRevision++;
    notifyListeners();
  }
}

/// Stopwatch uses monotonic elapsed time, not wall-clock calendar changes.
class NativeM36Stopwatch extends ChangeNotifier {
  final Stopwatch _watch = Stopwatch();
  Duration _saved = Duration.zero;
  bool get isRunning => _watch.isRunning;
  Duration get elapsed => _saved + _watch.elapsed;
  void start() { if (!_watch.isRunning) { _watch.start();notifyListeners(); } }
  void pause() {
    if (_watch.isRunning) {
      _saved += _watch.elapsed;_watch.reset();_watch.stop();
      notifyListeners();
    }
  }
  void reset() {
    _watch.reset();_watch.stop();_saved = Duration.zero;notifyListeners();
  }
  @override
  void dispose() { _watch.stop();super.dispose(); }
}

class NativeM36DashboardToolsController {
  final NativeM36Stopwatch stopwatch = NativeM36Stopwatch();
  final NativeM36RuntimeCalculator calculator = NativeM36RuntimeCalculator();
  void dispose() { stopwatch.dispose();calculator.dispose(); }
}
