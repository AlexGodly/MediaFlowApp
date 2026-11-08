// Old System (website v153 + v173): System · View · Date View · Stats.
// Every change goes through OldSystemOps, which writes `oldSystem` exactly as
// the website does (test/old_system_golden_test.dart). The History replays
// (View, Date View, Stats) run on the worker so a long History never stalls
// the screen.

import 'package:flutter/material.dart';

import '../data/account_controller.dart';
import '../data/background_worker.dart';
import '../logic/old_system.dart';
import '../state/models.dart';
import '../data/records.dart' show jsStringify;
import '../util/js.dart';
import 'presence.dart';
import 'theme.dart';
import 'widgets.dart';

class OldSystemScreen extends StatefulWidget {
  const OldSystemScreen({super.key, required this.account});
  final AccountController account;

  @override
  State<OldSystemScreen> createState() => _OldSystemScreenState();
}

class _OldSystemScreenState extends State<OldSystemScreen> {
  String? _consumeId;
  final _amount = TextEditingController(text: '1');
  final Map<String, TextEditingController> _balanceFields = {};

  // The last replay, kept until History, categories or the Old System change.
  Object? _replayKey;
  Future<OldSystemReplay>? _replay;
  Object? _rangeKey;
  Future<OldSystemReplay>? _range;

  AccountController get account => widget.account;

  @override
  void dispose() {
    _amount.dispose();
    for (final c in _balanceFields.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _toast(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 3)));

  Future<void> _do(String label, String? Function(OldSystemOps ops) action, {String? done}) async {
    String? message;
    await account.edit((s, now) {
      var k = 0;
      message = action(OldSystemOps(s, now, () => mediaFlowUid(now + k++)));
    }, label: label);
    if (!mounted) return;
    if (message != null) {
      _toast(message!);
    } else if (done != null) {
      _toast(done);
    }
  }

  Map<String, dynamic> _os(AccountView v) =>
      normalizeOldSystem(v.state['oldSystem'], [for (final c in v.categories) if (c.id.isNotEmpty) c.id], 0, () => '');

  Future<OldSystemReplay> _replayFor(AccountView v, {required bool range}) {
    final os = v.state['oldSystem'];
    final key = (v.state['sessions'], v.state['categories'], range ? jsStringify(os) : jsStringify(_withoutDates(os)));
    bool same(Object? k) => k is (Object?, Object?, String) && identical(k.$1, key.$1) && identical(k.$2, key.$2) && k.$3 == key.$3;
    if (range) {
      if (_range != null && same(_rangeKey)) return _range!;
      _rangeKey = key;
    } else {
      if (_replay != null && same(_replayKey)) return _replay!;
      _replayKey = key;
    }
    final input = <String, dynamic>{'categories': v.state['categories'], 'sessions': v.state['sessions'], 'oldSystem': os};
    final f = runOnWorker(() => replayOldSystem(input, dateRange: range)).catchError((_) => replayOldSystem(input, dateRange: range));
    return range ? (_range = f) : (_replay = f);
  }

  static Object? _withoutDates(Object? os) {
    final m = asMap(os);
    if (m == null) return os;
    return {...m}
      ..remove('dateFrom')
      ..remove('dateTo')
      ..remove('mode')
      ..remove('modifiedAt')
      ..remove('transactions');
  }

  @override
  Widget build(BuildContext context) {
    return LiveBuilder(
      listenable: account,
      builder: (context, _) {
        final v = account.view;
        if (v == null) return const Center(child: CircularProgressIndicator());
        final os = _os(v);
        final mode = jsStr(os['mode']);
        final tabs = kOldSystemModes;
        return PresenceScope(
          info: PresenceInfo(situation: 'oldSystem', values: {'action': 'Balancing the Old System', 'mode': _modeLabel(mode)}),
          child: DefaultTabController(
            key: ValueKey(mode),
            length: tabs.length,
            initialIndex: tabs.indexOf(mode).clamp(0, tabs.length - 1),
            child: Scaffold(
              appBar: AppBar(
                title: const Text('Old System'),
                actions: [SyncIndicator(account: account)],
                bottom: TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  onTap: (i) {
                    if (tabs[i] != mode) _do('Old System mode', (o) => o.setMode(tabs[i]));
                  },
                  tabs: [for (final m in tabs) Tab(text: _modeLabel(m))],
                ),
              ),
              body: TabBarView(
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _system(v, os),
                  _view(v, os, range: false),
                  _view(v, os, range: true),
                  _stats(v),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  static String _modeLabel(String m) => switch (m) {
        'view' => 'View',
        'date' => 'Date View',
        'stats' => 'Stats',
        _ => 'System',
      };

  Widget _intro() => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(
          "Your original category-conversion system, kept completely separate from MediaFlow's main scheduler. "
          'Use it directly, simulate it from MediaFlow History, or inspect exact category consumption.',
          style: TextStyle(color: MF.textDim),
        ),
      );

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 14, 2, 8),
        child: Text(text, style: TextStyle(color: MF.textDim, fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: .8)),
      );

  Widget _card({required String title, String? sub, required List<Widget> children}) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            if (sub != null) Padding(padding: const EdgeInsets.only(top: 4, bottom: 10), child: Text(sub, style: TextStyle(color: MF.textDim))),
            ...children,
          ]),
        ),
      );

  Color _signColor(num n) => n < 0 ? const Color(0xFFFF6B7A) : (n > 0 ? const Color(0xFF4ADE80) : MF.text);

  Widget _balanceCard(Category cat, num balance, {List<Widget> extra = const []}) => Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              CategoryBadge(cat, size: 30),
              const SizedBox(width: 8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(cat.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text('${unitLabel(cat.unit, 2)} · ${fmtOldSystemQty(cat.minutesPerUnit)}m per unit',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: MF.textDim, fontSize: 12)),
                ]),
              ),
            ]),
            const SizedBox(height: 8),
            Text(fmtOldSystemQty(balance), style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: _signColor(balance))),
            Text('${unitLabel(cat.unit, balance)} balance', style: TextStyle(color: MF.textDim, fontSize: 12)),
            ...extra,
          ]),
        ),
      );

  Widget _statLine(String k, String v) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(children: [
          Expanded(child: Text(k, style: TextStyle(color: MF.textDim, fontSize: 12))),
          Text(v, style: const TextStyle(fontWeight: FontWeight.w800)),
        ]),
      );

  Widget _grid(List<Widget> cards) => LayoutBuilder(builder: (context, c) {
        final cols = (c.maxWidth / 260).floor().clamp(1, 4);
        const gap = 10.0;
        final w = (c.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(spacing: gap, runSpacing: gap, children: [for (final card in cards) SizedBox(width: w, child: card)]);
      });

  List<Category> _enabled(AccountView v, Map<String, dynamic> os) {
    final ids = (os['enabledCategoryIds'] as List).cast<String>();
    return [for (final id in ids) v.category(id)];
  }

  String _ruleSentence(AccountView v, Map<String, dynamic> r) {
    final from = v.category(jsStr(r['fromCategoryId'])), to = v.category(jsStr(r['toCategoryId']));
    final fa = jsNum(r['fromAmount']), ta = jsNum(r['toAmount']);
    return 'Consume ${fmtOldSystemQty(ta)} ${unitLabel(to.unit, ta)} of ${to.name} → subtract ${fmtOldSystemQty(fa)} ${unitLabel(from.unit, fa)} from ${from.name}.';
  }

  List<Map<String, dynamic>> _activeRules(Map<String, dynamic> os) {
    final enabled = (os['enabledCategoryIds'] as List).toSet();
    return [
      for (final r in (os['rules'] as List).cast<Map<String, dynamic>>())
        if (enabled.contains(r['fromCategoryId']) && enabled.contains(r['toCategoryId']) && r['fromCategoryId'] != r['toCategoryId']) r,
    ];
  }

  // ---- System ---------------------------------------------------------------

  Widget _system(AccountView v, Map<String, dynamic> os) {
    final enabled = _enabled(v, os);
    final balances = asMap(os['balances']) ?? const {};
    if (_consumeId == null || !enabled.any((c) => c.id == _consumeId)) _consumeId = enabled.firstOrNull?.id;
    final existing = {for (final c in v.categories) c.id};
    final txs = (os['transactions'] as List).cast<Map<String, dynamic>>();
    final recent = [
      for (final t in txs.reversed)
        if (jsStr(t['categoryId']).isEmpty || existing.contains(jsStr(t['categoryId']))) t,
    ].take(12).toList();
    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 120), children: [
      _intro(),
      if (enabled.isEmpty)
        Padding(padding: const EdgeInsets.only(bottom: 12), child: Text('Add categories below to start building your Old System.', style: TextStyle(color: MF.textDim)))
      else ...[
        _label('CURRENT OLD SYSTEM BALANCES'),
        _grid([
          for (final cat in enabled)
            _balanceCard(cat, jsNum(balances[cat.id]), extra: [
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _balanceField(cat.id, jsNum(balances[cat.id])),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                    decoration: const InputDecoration(labelText: 'Set current balance', isDense: true),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () => _do('Set Old System balance', (o) => o.setBalance(cat.id, _balanceFields[cat.id]!.text)),
                  child: const Text('Set'),
                ),
              ]),
            ]),
        ]),
        const SizedBox(height: 12),
        _useCard(v, os, enabled),
      ],
      _card(
        title: 'Categories in Old System',
        sub: 'Choose which existing MediaFlow categories participate. This does not change whether a category is enabled in the normal MediaFlow scheduler.',
        children: [
          if (v.categories.isEmpty) Text('No MediaFlow categories available.', style: TextStyle(color: MF.textDim)),
          for (final cat in v.categories)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: enabled.any((c) => c.id == cat.id),
              onChanged: (_) => _do('Old System categories', (o) => o.toggleCategory(cat.id)),
              secondary: CategoryBadge(cat, size: 30),
              title: Text(cat.name, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('${unitLabel(cat.unit, 2)} · ${fmtOldSystemQty(cat.minutesPerUnit)}m/unit'),
            ),
        ],
      ),
      _rulesCard(v, os, enabled),
      if (recent.isNotEmpty)
        _card(title: 'Recent Old System Activity', sub: 'Independent from MediaFlow History.', children: [
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: txs.isEmpty ? null : () => _do('Undo Old System', (o) => o.undo()),
              icon: const Icon(Icons.undo_rounded, size: 18),
              label: const Text('Undo last'),
            ),
          ),
          for (final t in recent)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(jsStr(t['label']).isEmpty ? 'Old System change' : jsStr(t['label']), style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(_when(jsNum(t['timestamp']).toInt()), style: TextStyle(color: MF.textDim, fontSize: 12)),
                  ]),
                ),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  for (final d in asList(t['deltas']).map(asMap).whereType<Map<String, dynamic>>())
                    if (existing.contains(jsStr(d['categoryId'])))
                      Text(
                        '${jsNum(d['delta']) >= 0 ? '+' : ''}${fmtOldSystemQty(jsNum(d['delta']))} ${unitLabel(v.category(jsStr(d['categoryId'])).unit, jsNum(d['delta']))}',
                        style: TextStyle(color: jsNum(d['delta']) < 0 ? const Color(0xFFFF6B7A) : const Color(0xFF4ADE80), fontWeight: FontWeight.w700),
                      ),
                ]),
              ]),
            ),
        ]),
    ]);
  }

  final Map<String, String> _balanceSeen = {};
  TextEditingController _balanceField(String id, num value) {
    final text = fmtOldSystemQty(value).replaceAll(',', '');
    final c = _balanceFields.putIfAbsent(id, () => TextEditingController(text: text));
    // Follow saved changes (Undo, another device); leave what's being typed.
    if (_balanceSeen[id] != text) {
      _balanceSeen[id] = text;
      c.text = text;
    }
    return c;
  }

  static String _when(int ms) {
    if (ms <= 0) return '';
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${fmtDay(isoDay(d))} ${two(d.hour)}:${two(d.minute)}';
  }

  Widget _useCard(AccountView v, Map<String, dynamic> os, List<Category> enabled) {
    final id = _consumeId ?? '';
    final qty = jsNumOrNull(_amount.text.trim()) ?? 0;
    final parts = <String>[];
    if (id.isNotEmpty && qty > 0) {
      final cat = v.category(id);
      parts.add('+${fmtOldSystemQty(qty)} ${unitLabel(cat.unit, qty)} to ${cat.name}');
      for (final r in _activeRules(os).where((r) => r['toCategoryId'] == id)) {
        final cost = qty * (jsNum(r['fromAmount']) == 0 ? 1 : jsNum(r['fromAmount'])) / (jsNum(r['toAmount']) == 0 ? 1 : jsNum(r['toAmount']));
        final from = v.category(jsStr(r['fromCategoryId']));
        parts.add('−${fmtOldSystemQty(cost)} ${unitLabel(from.unit, cost)} from ${from.name}');
      }
    }
    return _card(
      title: 'Use Old System',
      sub: 'Record consumption only inside the Old System ledger. This does not create MediaFlow History, change Library progress, or affect recommendations.',
      children: [
        DropdownButtonFormField<String>(
          initialValue: id.isEmpty ? null : id,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Consumed category'),
          items: [for (final c in enabled) DropdownMenuItem(value: c.id, child: Text(c.name, overflow: TextOverflow.ellipsis))],
          onChanged: (x) => setState(() => _consumeId = x),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Amount'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        Text(parts.isEmpty ? 'Enter an amount to preview the balance changes.' : parts.join(' · '), style: TextStyle(color: MF.textDim)),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: id.isEmpty
              ? null
              : () {
                  final cat = v.category(id);
                  final q = jsNumOrNull(_amount.text.trim()) ?? double.nan;
                  _do('Old System consumption', (o) => o.consume(id, q), done: q > 0 ? 'Old System updated · +${fmtOldSystemQty(q)} ${cat.name}' : null);
                },
          icon: const Icon(Icons.check_rounded),
          label: const Text('Apply consumption'),
        ),
      ],
    );
  }

  Widget _rulesCard(AccountView v, Map<String, dynamic> os, List<Category> enabled) {
    final ids = {for (final c in enabled) c.id};
    final rules = [
      for (final r in (os['rules'] as List).cast<Map<String, dynamic>>())
        if (ids.contains(r['fromCategoryId']) && ids.contains(r['toCategoryId'])) r,
    ];
    Widget pick(Map<String, dynamic> r, String key, String label) => DropdownButtonFormField<String>(
          key: ValueKey('${r['id']}$key${r[key]}'),
          initialValue: jsStr(r[key]),
          isExpanded: true,
          decoration: InputDecoration(labelText: label, isDense: true),
          items: [for (final c in enabled) DropdownMenuItem(value: c.id, child: Text(c.name, overflow: TextOverflow.ellipsis))],
          onChanged: (x) => _do('Old System rule', (o) => o.updateRule(jsStr(r['id']), key, x)),
        );
    Widget amount(Map<String, dynamic> r, String key) => _AmountField(
          key: ValueKey('${r['id']}$key${r[key]}'),
          value: jsNum(r[key]),
          onSubmit: (text) => _do('Old System rule', (o) => o.updateRule(jsStr(r['id']), key, text)),
        );
    return _card(
      title: 'Conversion Rules',
      sub: 'Rules are directional. Example: 4 Manga chapters → 2 Seasonal Anime episodes means consuming 2 Seasonal Anime subtracts 4 from Manga and adds 2 to Seasonal Anime.',
      children: [
        if (rules.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text('No conversion rules yet. Add at least two categories, then create a rule.', style: TextStyle(color: MF.textDim)),
          ),
        for (final r in rules)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(border: Border.all(color: MF.border), borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [Expanded(flex: 3, child: pick(r, 'fromCategoryId', 'Subtract from')), const SizedBox(width: 8), Expanded(flex: 2, child: amount(r, 'fromAmount'))]),
              Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Icon(Icons.arrow_downward_rounded, size: 18, color: MF.textDim)),
              Row(children: [Expanded(flex: 3, child: pick(r, 'toCategoryId', 'When consuming')), const SizedBox(width: 8), Expanded(flex: 2, child: amount(r, 'toAmount'))]),
              const SizedBox(height: 8),
              Text(_ruleSentence(v, r), style: TextStyle(color: MF.textDim)),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => _do('Remove Old System rule', (o) => o.removeRule(jsStr(r['id']))),
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: const Text('Remove'),
                ),
              ),
            ]),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.tonalIcon(
            onPressed: enabled.length < 2 ? null : () => _do('Add Old System rule', (o) => o.addRule()),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add conversion rule'),
          ),
        ),
      ],
    );
  }

  // ---- View / Date View ------------------------------------------------------

  Widget _view(AccountView v, Map<String, dynamic> os, {required bool range}) {
    final enabled = _enabled(v, os);
    if (enabled.isEmpty) {
      return ListView(padding: const EdgeInsets.all(16), children: [
        _intro(),
        Text('No categories are configured for the Old System yet. Open System and add the categories you want to simulate.',
            style: TextStyle(color: MF.textDim)),
      ]);
    }
    final rules = _activeRules(os);
    final from = jsStr(os['dateFrom']), to = jsStr(os['dateTo']);
    return FutureBuilder<OldSystemReplay>(
      future: _replayFor(v, range: range),
      builder: (context, snap) {
        final c = snap.data;
        String records(int n) => '${fmtNumber(n)} consumption record${n == 1 ? '' : 's'} analyzed';
        return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 120), children: [
          _intro(),
          _card(
            title: range ? 'Date-range Old System Simulation' : 'Read-only Old System Simulation',
            sub: range
                ? 'Same read-only simulation as View, but only genuine MediaFlow History inside the date range below is replayed through your Old System conversion rules.'
                : 'This replays your genuine non-skipped MediaFlow History from oldest to newest using your Old System conversion rules. Nothing is written back to MediaFlow.',
            children: [
              if (range)
                Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  _DateButton(label: 'From', value: from, onPick: (d) => _do('Old System dates', (o) => o.setDate('dateFrom', d))),
                  _DateButton(label: 'To', value: to, onPick: (d) => _do('Old System dates', (o) => o.setDate('dateTo', d))),
                  TextButton(
                    onPressed: from.isEmpty && to.isEmpty ? null : () => _do('Old System dates', (o) => o.clearDates()),
                    child: const Text('Clear dates'),
                  ),
                ]),
              const SizedBox(height: 6),
              Text(
                c == null
                    ? 'Replaying History…'
                    : range
                        ? '${records(c.activityRows)} · ${from.isEmpty ? 'Beginning' : from} → ${to.isEmpty ? 'Today' : to}'
                        : records(c.activityRows),
                style: TextStyle(color: MF.textDim),
              ),
              if (!range && rules.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final r in rules) Chip(label: Text(_ruleSentence(v, r), style: const TextStyle(fontSize: 12)), visualDensity: VisualDensity.compact),
                ]),
              ],
            ],
          ),
          _label(range ? 'OLD SYSTEM FOR SELECTED DATES' : 'IF YOU HAD USED THE OLD SYSTEM'),
          if (c == null)
            const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
          else
            _grid([
              for (final cat in enabled)
                _balanceCard(cat, c.simulatedBalances[cat.id] ?? 0, extra: [
                  _statLine('MediaFlow consumed', fmtOldSystemQty(c.rawTotals[cat.id] ?? 0)),
                  _statLine('Spent as source', fmtOldSystemQty(c.simulatedSpent[cat.id] ?? 0)),
                ]),
            ]),
        ]);
      },
    );
  }

  // ---- Stats ----------------------------------------------------------------

  Widget _stats(AccountView v) {
    return FutureBuilder<OldSystemReplay>(
      future: _replayFor(v, range: false),
      builder: (context, snap) {
        final c = snap.data;
        final cats = [for (final cat in v.categories) if (cat.id.isNotEmpty) cat];
        return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 120), children: [
          _intro(),
          _card(
            title: 'Exact MediaFlow Consumption',
            sub: 'All-time genuine non-skipped MediaFlow History, grouped by category. No Old System conversion is applied here.',
            children: const [],
          ),
          if (c == null)
            const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
          else if (cats.isEmpty)
            Text('No consumption History yet.', style: TextStyle(color: MF.textDim))
          else
            _grid([
              for (final cat in cats)
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        CategoryBadge(cat, size: 30),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(cat.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                            Text(unitLabel(cat.unit, 2), style: TextStyle(color: MF.textDim, fontSize: 12)),
                          ]),
                        ),
                      ]),
                      const SizedBox(height: 8),
                      Text(fmtOldSystemQty(c.rawTotals[cat.id] ?? 0), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
                      Text('${unitLabel(cat.unit, c.rawTotals[cat.id] ?? 0)} consumed', style: TextStyle(color: MF.textDim, fontSize: 12)),
                      _statLine('History records', fmtNumber(c.sessionCounts[cat.id] ?? 0)),
                      _statLine('Logged time', fmtMinutes(c.minuteTotals[cat.id] ?? 0)),
                    ]),
                  ),
                ),
            ]),
        ]);
      },
    );
  }
}

class _AmountField extends StatefulWidget {
  const _AmountField({super.key, required this.value, required this.onSubmit});
  final num value;
  final ValueChanged<String> onSubmit;

  @override
  State<_AmountField> createState() => _AmountFieldState();
}

class _AmountFieldState extends State<_AmountField> {
  late final _c = TextEditingController(text: fmtOldSystemQty(widget.value).replaceAll(',', ''));
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _submit();
    });
  }

  void _submit() {
    final text = _c.text.trim();
    if (jsNumOrNull(text) != widget.value) widget.onSubmit(text);
  }

  @override
  void dispose() {
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
        controller: _c,
        focusNode: _focus,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(labelText: 'Units', isDense: true),
        onSubmitted: (_) => _submit(),
      );
}

class _DateButton extends StatelessWidget {
  const _DateButton({required this.label, required this.value, required this.onPick});
  final String label;
  final String value;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        icon: const Icon(Icons.event_rounded, size: 18),
        label: Text('$label: ${value.isEmpty ? (label == 'From' ? 'Beginning' : 'Today') : fmtDay(value)}'),
        onPressed: () async {
          final now = DateTime.now();
          final initial = DateTime.tryParse(value) ?? now;
          final d = await showDatePicker(context: context, initialDate: initial, firstDate: DateTime(1970), lastDate: DateTime(now.year + 5));
          if (d != null) onPick(isoDay(d));
        },
      );
}
