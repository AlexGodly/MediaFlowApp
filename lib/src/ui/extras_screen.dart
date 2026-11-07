// Extras: the website's Dashboard tools — Today's Balance, On This Day,
// Stopwatch and Runtime Calculator — with the same account data.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/account_controller.dart';
import '../data/account_ops.dart';
import '../logic/extras.dart';
import '../logic/resume.dart';
import '../state/models.dart';
import '../util/js.dart';
import 'theme.dart';
import 'widgets.dart';

class ExtrasScreen extends StatelessWidget {
  const ExtrasScreen({super.key, required this.account});
  final AccountController account;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Extras'), actions: [SyncIndicator(account: account)]),
      body: LiveBuilder(
        listenable: account,
        builder: (context, _) {
          final view = account.view;
          if (view == null) return const SizedBox.shrink();
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                children: [
                  _BalanceCard(view: view),
                  _OnThisDayCard(view: view),
                  StopwatchCard(account: account),
                  RuntimeCalculatorCard(account: account),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

String _statusName(String s) => switch (s) {
      'healthy' => 'Healthy',
      'neglected' => 'Neglected',
      'overused' => 'Overused',
      'due' => 'Due',
      _ => s,
    };

Color _healthColor(String s) => switch (s) {
      'healthy' => MF.good,
      'overused' => MF.bad,
      'neglected' => const Color(0xFFE8A94A),
      'due' => const Color(0xFF7FB2FF),
      _ => MF.textDim,
    };

// ---- Today's Balance ------------------------------------------------------------

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.view});
  final AccountView view;

  @override
  Widget build(BuildContext context) {
    final b = memoFor(view, 'todayBalance', () => todayBalance(view.state, DateTime.now().millisecondsSinceEpoch));
    return SectionCard(
      prefKey: 'extras.balance',
      icon: Icons.balance_rounded,
      title: "Today's Balance",
      subtitle: 'Category health, progress and what needs attention next',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (b.rows.isEmpty)
          Text('No categories are enabled for Today’s Balance.', style: TextStyle(color: MF.textDim))
        else
          for (final r in b.rows) _row(r),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _tile('Consumed today', fmtNumber(b.units), 'units'),
          _tile('Time invested', fmtMinutes(b.minutes), 'today'),
          _tile('Current streak', '${b.streak}', 'days'),
          _tile('Rating queue', fmtNumber(b.unrated), 'unrated titles'),
        ]),
        const SizedBox(height: 12),
        const Text('Balance health overview', style: TextStyle(fontWeight: FontWeight.w800)),
        Text('${b.scopeVisible ? 'Only displayed categories' : 'All categories, including hidden'} · ${b.subjects} total',
            style: TextStyle(color: MF.textDim, fontSize: 12)),
        const SizedBox(height: 6),
        _counts('Today (72 hours)', b.todayCounts),
        _counts('Overall (lifetime)', b.overallCounts),
      ]),
    );
  }

  Widget _counts(String label, Map<String, int> c) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Wrap(spacing: 10, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          for (final k in const ['healthy', 'due', 'neglected', 'overused'])
            Text('${c[k]} $k', style: TextStyle(color: _healthColor(k), fontSize: 12, fontWeight: FontWeight.w700)),
        ]),
      );

  Widget _tile(String label, String value, String unit) => Container(
        width: 150,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: MF.raised, borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(color: MF.textDim, fontSize: 11)),
          Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          Text(unit, style: TextStyle(color: MF.textDim, fontSize: 11)),
        ]),
      );

  Widget _row(BalanceRow r) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: MF.raised, borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            CategoryBadge(r.cat, size: 34),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(r.cat.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                Text('${fmtNumber(r.amount)} ${unitLabel(r.cat.unit, r.amount)} today', style: TextStyle(color: MF.textDim, fontSize: 12)),
              ]),
            ),
            Text('${fmtNumber(r.amount)} / ${fmtNumber(r.target)}', style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(width: 6),
            Text('${r.pct}%', style: TextStyle(color: MF.textDim, fontSize: 12)),
          ]),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: r.pct / 100, minHeight: 5, borderRadius: BorderRadius.circular(4)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 4, children: [
            _chip('Today · ${_statusName(r.today)}', _healthColor(r.today)),
            _chip('Overall · ${_statusName(r.overall)}', _healthColor(r.overall)),
          ]),
          const SizedBox(height: 6),
          Text(r.label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
          Text(r.text, style: TextStyle(color: MF.textDim, fontSize: 12)),
        ]),
      );

  Widget _chip(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
        child: Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
      );
}

// ---- On This Day ----------------------------------------------------------------

class _OnThisDayCard extends StatelessWidget {
  const _OnThisDayCard({required this.view});
  final AccountView view;

  static String _verb(String k) => switch (k) { 'started' => '▶ Started', 'finished' => '✓ Finished', _ => '● Logged' };

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final groups = memoFor(view, 'onThisDay', () => onThisDay(view.state, now));
    const months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    final today = '${months[now.month - 1]} ${now.day}';
    return SectionCard(
      prefKey: 'extras.otd',
      icon: Icons.event_available_rounded,
      title: 'On This Day',
      subtitle: 'Memories and milestones from previous years',
      child: groups.isEmpty
          ? Text(
              'No anniversaries for $today yet. Past History activity and Library start or finish milestones will appear here '
              'when they match today’s date in a previous year.',
              style: TextStyle(color: MF.textDim),
            )
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final g in groups) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 6, bottom: 6),
                  child: Row(children: [
                    Expanded(
                      child: Text('${g.years} year${g.years == 1 ? '' : 's'} ago',
                          style: TextStyle(fontWeight: FontWeight.w900, color: MF.accent)),
                    ),
                    Text('${g.rows.length} event${g.rows.length == 1 ? '' : 's'}', style: TextStyle(color: MF.textDim, fontSize: 12)),
                  ]),
                ),
                for (final x in g.rows) _event(x),
              ],
            ]),
    );
  }

  Widget _event(OtdEvent x) {
    final item = x.item ?? (x.libraryId == null ? null : view.library.where((t) => t.id == x.libraryId).firstOrNull?.raw);
    final cat = view.category(jsStr(item?['categoryId'] ?? x.categoryId));
    final title = item != null ? LibraryTitle(item) : LibraryTitle(<String, dynamic>{'title': x.title, 'categoryId': cat.id});
    final bits = <String>[
      if (x.kind == 'logged' && x.qty > 0) '${fmtNumber(x.qty)} ${unitLabel(cat.unit, x.qty)}',
      if (x.kind == 'logged' && x.minutes.round() > 0) fmtMinutes(x.minutes.round()),
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Cover(title: title, category: cat, width: 38),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(x.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
            Text([_verb(x.kind), ...bits].join(' · '), style: TextStyle(color: MF.textDim, fontSize: 12)),
          ]),
        ),
      ]),
    );
  }
}

// ---- time fields ------------------------------------------------------------------

class _TimeFields extends StatelessWidget {
  const _TimeFields({required this.h, required this.m, required this.s, this.enabled = true, this.onChanged});
  final TextEditingController h, m, s;
  final bool enabled;
  final VoidCallback? onChanged;

  Widget _field(TextEditingController c, String label) => Expanded(
        child: TextField(
          controller: c,
          enabled: enabled,
          textAlign: TextAlign.center,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(labelText: label, isDense: true),
          onChanged: (_) => onChanged?.call(),
        ),
      );

  @override
  Widget build(BuildContext context) => Row(children: [
        _field(h, 'Hours'),
        const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Text(':', style: TextStyle(fontSize: 18))),
        _field(m, 'Minutes'),
        const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Text(':', style: TextStyle(fontSize: 18))),
        _field(s, 'Seconds'),
      ]);
}

int _int(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;

bool _logOpen(AccountController account) {
  final v = account.view;
  final logging = v == null ? null : readLogging(v.state);
  return logging?['active'] == true;
}

// ---- Stopwatch ----------------------------------------------------------------------

class StopwatchCard extends StatefulWidget {
  const StopwatchCard({super.key, required this.account});
  final AccountController account;

  @override
  State<StopwatchCard> createState() => _StopwatchCardState();
}

class _StopwatchCardState extends State<StopwatchCard> {
  final _h = TextEditingController(), _m = TextEditingController(), _s = TextEditingController();
  Timer? _tick;
  double _shownBase = -1;

  AccountController get account => widget.account;

  Stopwatch2 get _sw => Stopwatch2(readTools(account.view!.state).stopwatch);

  @override
  void dispose() {
    _tick?.cancel();
    for (final c in [_h, _m, _s]) {
      c.dispose();
    }
    super.dispose();
  }

  void _syncTicker(Stopwatch2 sw) {
    if (sw.running && _tick == null) {
      _tick = Timer.periodic(const Duration(milliseconds: 250), (_) {
        // Only redraw while Extras is on screen.
        if (mounted && TickerMode.of(context)) setState(() {});
      });
    } else if (!sw.running && _tick != null) {
      _tick!.cancel();
      _tick = null;
    }
    // The fields show the custom starting time, like the website.
    if (sw.resetValue != _shownBase) {
      _shownBase = sw.resetValue;
      final sec = (sw.resetValue / 1000).floor();
      _h.text = '${sec ~/ 3600}';
      _m.text = '${sec % 3600 ~/ 60}';
      _s.text = '${sec % 60}';
    }
  }

  Future<void> _do(String? Function(Stopwatch2 sw, int now) action) async {
    final sw = _sw;
    final now = DateTime.now().millisecondsSinceEpoch;
    final before = sw.data.toString();
    final toast = action(sw, now);
    if (toast != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(toast), duration: const Duration(seconds: 2)));
    }
    if (sw.data.toString() == before) return;
    await account.perform(
      ToolOp(mediaFlowUid(now), 'stopwatch', sw.data),
      supersedes: (p) => p is ToolOp && p.tool == 'stopwatch',
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final sw = _sw;
    _syncTicker(sw);
    final now = DateTime.now().millisecondsSinceEpoch;
    final running = sw.running;
    return SectionCard(
      prefKey: 'extras.stopwatch',
      icon: Icons.timer_rounded,
      title: 'Stopwatch',
      subtitle: 'Track a runtime live or build a custom starting time',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Center(
          child: Text(fmtStopwatch(sw.elapsed(now)),
              style: const TextStyle(fontSize: 46, fontWeight: FontWeight.w900, fontFeatures: [FontFeature.tabularFigures()])),
        ),
        const SizedBox(height: 10),
        _TimeFields(h: _h, m: _m, s: _s, enabled: !running),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
          OutlinedButton(
            onPressed: running ? null : () => _do((x, t) => x.setTime(_int(_h), _int(_m), _int(_s), t)),
            child: const Text('Set time'),
          ),
          OutlinedButton(
            onPressed: running ? null : () => _do((x, t) => x.addTime(_int(_h), _int(_m), _int(_s), t)),
            child: const Text('+ Add'),
          ),
          OutlinedButton(
            onPressed: running ? null : () => _do((x, t) => x.minusTime(_int(_h), _int(_m), _int(_s), t)),
            child: const Text('− Subtract'),
          ),
        ]),
        if (sw.resetValue > 0)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('Custom starting time: ${fmtStopwatch(sw.resetValue)} · Reset returns here.',
                textAlign: TextAlign.center, style: TextStyle(color: MF.textDim, fontSize: 12)),
          ),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
          FilledButton.icon(
            onPressed: running ? null : () => _do((x, t) => x.start(t) ? null : null),
            icon: const Icon(Icons.play_arrow_rounded),
            label: Text(running ? 'Running…' : 'Start'),
          ),
          FilledButton.tonalIcon(
            onPressed: !running ? null : () => _do((x, t) => x.pause(t) ? null : null),
            icon: const Icon(Icons.pause_rounded),
            label: const Text('Pause'),
          ),
          TextButton(
            onPressed: () => _do((x, t) {
              x.reset(t);
              return null;
            }),
            child: const Text('Reset'),
          ),
          TextButton(
            onPressed: () => _do((x, t) {
              x.clear(t);
              return null;
            }),
            child: const Text('Clear to 00:00:00'),
          ),
          if (_logOpen(account))
            OutlinedButton.icon(
              icon: const Icon(Icons.input_rounded),
              label: const Text('Use for minutes'),
              onPressed: () async {
                final minutes = sw.minutes(DateTime.now().millisecondsSinceEpoch);
                final ok = await useMinutesForOpenLog(account, minutes);
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(ok ? '$minutes minutes copied to the current log.' : 'Open a log first.')));
              },
            ),
        ]),
        const SizedBox(height: 8),
        Text('Set any starting time, press Start, and the stopwatch continues upward from there. '
            'It keeps running while the app is closed, and on the website too.',
            textAlign: TextAlign.center, style: TextStyle(color: MF.textDim, fontSize: 12)),
      ]),
    );
  }
}

// ---- Runtime Calculator ------------------------------------------------------------

class RuntimeCalculatorCard extends StatefulWidget {
  const RuntimeCalculatorCard({super.key, required this.account});
  final AccountController account;

  @override
  State<RuntimeCalculatorCard> createState() => _RuntimeCalculatorCardState();
}

class _RuntimeCalculatorCardState extends State<RuntimeCalculatorCard> {
  final List<List<TextEditingController>> _fields = [];
  String _shown = '';

  AccountController get account => widget.account;

  @override
  void dispose() {
    for (final row in _fields) {
      for (final c in row) {
        c.dispose();
      }
    }
    super.dispose();
  }

  RuntimeCalc get _calc => RuntimeCalc(readTools(account.view!.state).runtime);

  List<Map<String, dynamic>> _rowsOf(RuntimeCalc rc) => rc.multi ? rc.rows : rc.chain;

  /// Keeps the text fields in step with the account (unless you're typing).
  void _syncFields(RuntimeCalc rc) {
    final rows = _rowsOf(rc);
    final key = '${rc.data['mode']}|${rows.map((r) => '${r['h']}:${r['m']}:${r['s']}').join(',')}';
    if (key == _shown) return;
    _shown = key;
    while (_fields.length < rows.length) {
      _fields.add([TextEditingController(), TextEditingController(), TextEditingController()]);
    }
    while (_fields.length > rows.length) {
      final gone = _fields.removeLast();
      // Disposed after this frame, once the removed fields have let go of them.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final c in gone) {
          c.dispose();
        }
      });
    }
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      final vals = ['${r['h']}', '${r['m']}', '${r['s']}'];
      for (var k = 0; k < 3; k++) {
        if (_fields[i][k].text != vals[k] && !(int.tryParse(_fields[i][k].text) == r[const ['h', 'm', 's'][k]])) {
          _fields[i][k].text = vals[k];
        }
      }
    }
  }

  Future<void> _save(RuntimeCalc rc, {bool soon = false}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    rc.touch(now);
    await account.perform(
      ToolOp(mediaFlowUid(now), 'runtimeCalculator', rc.data),
      delay: soon ? const Duration(milliseconds: 1500) : null,
      supersedes: (p) => p is ToolOp && p.tool == 'runtimeCalculator',
    );
  }

  /// Copies the typed values into the calculator (`v256UpdateRuntimeField`).
  RuntimeCalc _withTyped() {
    final rc = _calc;
    final scope = rc.multi ? 'multi' : 'chain';
    for (var i = 0; i < _fields.length; i++) {
      for (var k = 0; k < 3; k++) {
        rc.updateField(scope, i, const ['h', 'm', 's'][k], int.tryParse(_fields[i][k].text) ?? 0);
      }
    }
    return rc;
  }

  void _toast(String? t) {
    if (t != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t), duration: const Duration(seconds: 2)));
    }
  }

  Future<void> _act(String? Function(RuntimeCalc rc) f) async {
    final rc = _withTyped();
    final toast = f(rc);
    _toast(toast);
    _shown = '';
    await _save(rc);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final rc = _calc;
    _syncFields(rc);
    final chain = !rc.multi;
    final rows = _rowsOf(rc);
    final result = secondsToTime(rc.resultSeconds);
    return SectionCard(
      prefKey: 'extras.runtime',
      icon: Icons.more_time_rounded,
      title: 'Runtime Calculator',
      subtitle: 'Add runtimes together, carry totals forward, or sum many rows',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'chain', label: Text('Carry-forward')),
            ButtonSegment(value: 'multi', label: Text('Multi-row')),
          ],
          selected: {chain ? 'chain' : 'multi'},
          onSelectionChanged: (s) => _act((x) {
            x.setMode(s.first);
            return null;
          }),
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < rows.length && i < _fields.length; i++) ...[
          if (i > 0) Center(child: Text('+', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: MF.textDim))),
          Row(children: [
            SizedBox(width: 84, child: Text('Runtime ${i + 1}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
            Expanded(
              child: _TimeFields(
                h: _fields[i][0],
                m: _fields[i][1],
                s: _fields[i][2],
                onChanged: () => _save(_withTyped(), soon: true),
              ),
            ),
            if (!chain)
              IconButton(
                tooltip: 'Remove row',
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: () => _act((x) => x.removeRow(i)),
              ),
          ]),
          const SizedBox(height: 6),
        ],
        if (!chain)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _act((x) {
                x.addRow();
                return null;
              }),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add runtime row'),
            ),
          ),
        Center(child: Text('=', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: MF.textDim))),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: MF.raised, borderRadius: BorderRadius.circular(14)),
          child: Column(children: [
            Text(rc.hasResult ? fmtRuntime(rc.resultSeconds) : '00:00:00',
                style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, fontFeatures: [FontFeature.tabularFigures()])),
            Text(
              rc.hasResult ? '${rc.resultCount} runtime${rc.resultCount == 1 ? '' : 's'} calculated' : 'Waiting for calculation',
              style: TextStyle(color: MF.textDim, fontSize: 12),
            ),
            const SizedBox(height: 4),
            Text('${result['h']} h · ${result['m']} min · ${result['s']} s', style: TextStyle(color: MF.textDim, fontSize: 12)),
          ]),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton(onPressed: () => _act((x) => x.calculate()), child: const Text('Calculate')),
          if (chain) ...[
            OutlinedButton(onPressed: rc.hasResult ? () => _act((x) => x.continueResult()) : null, child: const Text('Continue with result')),
            TextButton(
              onPressed: rc.hasResult && rc.previousSeconds > 0 ? () => _act((x) => x.restorePrevious()) : null,
              child: const Text('Previous total'),
            ),
          ],
          if (_logOpen(account))
            OutlinedButton(
              onPressed: !rc.hasResult
                  ? null
                  : () async {
                      final ok = await useMinutesForOpenLog(account, rc.minutes);
                      _toast(ok ? '${rc.minutes} minutes copied to the current log.' : 'Open a log first.');
                    },
              child: const Text('Use for minutes'),
            ),
          TextButton(
            onPressed: () => _act((x) {
              x.clear();
              return null;
            }),
            child: const Text('Clear'),
          ),
        ]),
        const SizedBox(height: 6),
        Text(
          chain
              ? 'After calculating, Continue with result moves the result into Runtime 1 and clears Runtime 2. '
                  'Previous total restores the accumulator from before the latest addition.'
              : 'Add or remove runtime rows, then calculate their combined duration. Only non-zero rows count toward the “runtimes calculated” total.',
          style: TextStyle(color: MF.textDim, fontSize: 12),
        ),
      ]),
    );
  }
}
