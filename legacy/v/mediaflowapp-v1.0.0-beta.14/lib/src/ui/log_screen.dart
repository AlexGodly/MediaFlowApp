// The Log tab: MediaFlow Recommends plus the website's whole logging form —
// Quick (progress reached / amount) and Advanced (episode by episode, with
// seasons, runtimes and times), multi-title logs and notes. The open form is the
// account's shared draft, so it continues on the website and vice versa.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/account_controller.dart';
import '../data/account_ops.dart';
import '../logic/log_draft.dart';
import '../logic/rec_submit.dart';
import '../logic/recommend.dart';
import '../logic/resume.dart';
import '../state/models.dart';
import '../util/js.dart';
import 'log_sheet.dart';
import 'theme.dart';
import 'widgets.dart';

String _cap(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

String _num(Object? v) => fmtNumber(jsNum(v));

String _hms(num seconds) {
  final s = seconds.round();
  final h = s ~/ 3600, m = s % 3600 ~/ 60, r = s % 60;
  return '$h:${m.toString().padLeft(2, '0')}:${r.toString().padLeft(2, '0')}';
}

String _when(num ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms.toInt());
  return '${fmtDay(isoDay(d))} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

T _clone<T>(T v) => jsonDecode(jsonEncode(v)) as T;

/// Plain number for an editable field (no thousands separators).
String _plain(Object? v) {
  final n = jsNum(v);
  return n == n.truncateToDouble() ? n.toInt().toString() : n.toString();
}

class LogScreen extends StatefulWidget {
  const LogScreen({super.key, required this.account});
  final AccountController account;

  @override
  State<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends State<LogScreen> {
  // The open form (null when closed): a local copy of the shared draft.
  Map<String, dynamic>? _task;
  Map<String, dynamic>? _logDraft;
  Map<String, dynamic> _entryDraft = {};
  Object? _ui;
  int _draftAt = 0;
  int _formGen = 0; // bumps when the form is replaced (opened, or adopted from elsewhere)

  bool _busy = false;
  String? _error;
  final _search = TextEditingController();
  final _note = TextEditingController();
  final _value = TextEditingController(); // end progress / quantity for the next quick entry
  Timer? _noteTimer;

  AccountController get account => widget.account;

  @override
  void initState() {
    super.initState();
    _adopt();
    account.addListener(_onAccount);
  }

  @override
  void dispose() {
    account.removeListener(_onAccount);
    _noteTimer?.cancel();
    for (final c in [_search, _note, _value]) {
      c.dispose();
    }
    super.dispose();
  }

  void _onAccount() {
    if (!mounted) return;
    if (_adopt()) setState(() {});
  }

  /// Takes a newer draft (or a closed form) from the account — e.g. one
  /// continued on the website. Returns true if the local form changed.
  bool _adopt() {
    final view = account.view;
    if (view == null) return false;
    final logging = readLogging(view.state);
    if (logging == null) return false;
    final at = jsNum(logging['modifiedAt']).toInt();
    if (at <= _draftAt) return false;
    _draftAt = at;
    _formGen++;
    _ui = logging['ui'];
    final task = asMap(logging['currentTask']);
    if (logging['active'] == true && task != null) {
      _task = task;
      _logDraft = asMap(logging['logDraft']) ?? <String, dynamic>{};
      _entryDraft = asMap(logging['entryDraft']) ?? <String, dynamic>{'title': '', 'qty': 1};
      _note.text = jsStr(_logDraft!['note']);
    } else {
      _closeLocal();
    }
    return true;
  }

  void _closeLocal() {
    _task = null;
    _logDraft = null;
    _entryDraft = {};
    _note.clear();
    _search.clear();
    _value.clear();
    _error = null;
  }

  LogDraftEditor? _editor(AccountView view) {
    if (_task == null || _logDraft == null) return null;
    return LogDraftEditor(state: view.state, task: _task!, logDraft: _logDraft!, entryDraft: _entryDraft);
  }

  /// Runs a form action, keeps the result and saves the shared draft.
  void _edit(String? Function(LogDraftEditor ed) action) {
    final view = account.view;
    final ed = view == null ? null : _editor(view);
    if (ed == null) return;
    final message = action(ed);
    setState(() {
      _entryDraft = ed.entryDraft;
      _error = message;
    });
    _saveDraft();
  }

  void _saveDraft() {
    final task = _task, draft = _logDraft;
    if (task == null || draft == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    _draftAt = now > _draftAt ? now : _draftAt + 1;
    unawaited(account.saveDraft(
      activeLogging(task: task, logDraft: draft, entryDraft: _entryDraft, modifiedAt: _draftAt, ui: _ui),
    ));
  }

  Future<void> _closeForm() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    _draftAt = now > _draftAt ? now : _draftAt + 1;
    setState(_closeLocal);
    await account.saveDraft(inactiveLogging(_draftAt));
  }

  Future<void> _action(TaskAction action) async {
    setState(() => _busy = true);
    try {
      if (action == TaskAction.reroll || action == TaskAction.skip || action == TaskAction.end) {
        _draftAt = DateTime.now().millisecondsSinceEpoch;
        _closeLocal();
      }
      final done = await account.taskAction(action);
      if (!mounted) return;
      if (!done && action == TaskAction.rerollTitle) {
        _snack('No other eligible Library titles are available in this category.');
      }
      // A title reroll while the form is open keeps the form on the new title.
      if (action == TaskAction.rerollTitle && _task != null) {
        final current = asMap(account.view?.state['currentTask']);
        if (current != null) {
          setState(() => _task = _clone(current));
          _saveDraft();
        }
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openForm(Map<String, dynamic> task) {
    final view = account.view;
    if (view == null) return;
    final ed = LogDraftEditor.open(view.state, _clone(task));
    setState(() {
      _formGen++;
      _task = ed.task;
      _logDraft = ed.logDraft;
      _entryDraft = ed.entryDraft;
      _error = null;
      _note.clear();
      _search.clear();
      _value.clear();
    });
    // Start with the recommended title, like the website's picker does.
    final title = jsStr(task['title']);
    final libraryId = jsStr(task['libraryId']);
    if (libraryId.isNotEmpty && view.library.any((t) => t.id == libraryId)) {
      _pickTitle(libraryId, title, save: false);
    }
    _saveDraft();
  }

  void _pickTitle(String? libraryId, String title, {bool save = true}) {
    final view = account.view;
    final ed = view == null ? null : _editor(view);
    if (ed == null) return;
    if (ed.itemized) {
      ed.entryDraft = {'title': title, 'qty': 1, 'libraryId': libraryId};
      final err = ed.addItemizedEntry();
      setState(() {
        _entryDraft = ed.entryDraft;
        _error = err;
        _search.clear();
      });
    } else {
      ed.chooseTitle(libraryId: libraryId, title: title);
      setState(() {
        _entryDraft = ed.entryDraft;
        _error = null;
        _search.clear();
        _value.text = ed.mode == 'progress'
            ? (jsTruthy(ed.entryDraft['v252SeasonId']) ? _plain(ed.entryDraft['v252SeasonEpisode']) : _plain(ed.entryDraft['endProgress']))
            : '1';
      });
    }
    if (save) _saveDraft();
  }

  Future<void> _submit() async {
    final task = _task, draft = _logDraft;
    final view = account.view;
    if (task == null || draft == null || view == null) return;
    final error = _editor(view)!.validate();
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final outcome = await account.submitRecommendation(task, draft);
      if (!mounted) return;
      if (!outcome.applied) {
        setState(() => _error = outcome.error ?? 'This log was already saved.');
        return;
      }
      _draftAt = DateTime.now().millisecondsSinceEpoch;
      setState(_closeLocal);
      final parts = <String>['Logged · +${fmtNumber(outcome.xp)} XP'];
      if (outcome.respected && outcome.respectXP > 0) parts.add('System respected +${fmtNumber(outcome.respectXP)}');
      if (outcome.completed.isNotEmpty) parts.add('Completed ${outcome.completed.join(', ')}');
      _snack(parts.join(' · '));
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  // ---- build -----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final view = account.view;
    if (view == null) return const SizedBox.shrink();
    final state = view.state;
    final task = asMap(state['currentTask']);
    final active = state['sessionActive'] == true;
    final formOpen = _task != null && _logDraft != null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Log'),
        actions: [
          IconButton(
            tooltip: 'Log any title (Batch Log)',
            icon: const Icon(Icons.playlist_add_rounded),
            onPressed: () => showLogSheet(context, account),
          ),
          SyncIndicator(account: account),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
              children: [
                if (account.lastRejection != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Material(
                      color: MF.bad.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(14),
                      child: ListTile(
                        leading: const Icon(Icons.error_outline_rounded, color: MF.bad),
                        title: Text(account.lastRejection!, style: const TextStyle(fontSize: 13)),
                        trailing: IconButton(icon: const Icon(Icons.close_rounded), onPressed: account.dismissRejection),
                      ),
                    ),
                  ),
                if (formOpen)
                  ..._form(view)
                else if (!active || task == null)
                  _startCard(view)
                else
                  _taskCard(view, task),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---- MediaFlow Recommends ---------------------------------------------------

  Widget _panel({required List<Widget> children, EdgeInsets padding = const EdgeInsets.all(18)}) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Material(
          color: MF.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: MF.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: padding,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
          ),
        ),
      );

  Widget _startCard(AccountView view) {
    final respect = normalizeRespectState(view.state['respectState']);
    return _panel(children: [
      const Row(children: [
        Icon(Icons.auto_awesome_rounded, color: MF.accent),
        SizedBox(width: 10),
        Text('MediaFlow Recommends', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: MF.accent)),
      ]),
      const SizedBox(height: 14),
      const Text('Start a session', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
      const SizedBox(height: 6),
      const Text('MediaFlow will hand you one category at a time — you pick the titles.',
          style: TextStyle(color: MF.textDim)),
      const SizedBox(height: 14),
      _streaks(respect),
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: _busy ? null : () => _action(TaskAction.start),
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
        icon: const Icon(Icons.play_arrow_rounded),
        label: const Text('Start session', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: () => showLogSheet(context, account),
        icon: const Icon(Icons.playlist_add_rounded),
        label: const Text('Log any title instead'),
      ),
    ]);
  }

  Widget _streaks(Map<String, dynamic> respect) {
    Widget chip(IconData icon, String label) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(color: MF.raised, borderRadius: BorderRadius.circular(20)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 15, color: MF.accent),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          ]),
        );
    return Wrap(spacing: 8, runSpacing: 8, children: [
      chip(Icons.local_fire_department_rounded, 'No-skip streak ${respect['noSkipStreak']}'),
      chip(Icons.bolt_rounded, 'First-pick streak ${respect['noRerollStreak']}'),
    ]);
  }

  /// System Respect XP for following this task now (`v180CalculateRespectAward`).
  double _respectPreview(Map<String, dynamic> state, Map<String, dynamic> task) {
    final st = normalizeRespectState(state['respectState']);
    final cfg = normalizeRespectConfig(asMap(state['settings'])?['systemRespectXP']);
    final noSkip = jsNum(st['noSkipStreak']) + 1;
    final noReroll = jsNum(st['currentRerolls']) > 0 ? 0 : jsNum(st['noRerollStreak']) + 1;
    final r = Recommender(state, now: DateTime.now().millisecondsSinceEpoch);
    var base = jsNum(cfg['categoryBaseXP']);
    if (r.exactTitles && jsTruthy(task['libraryId'])) base += jsNum(cfg['exactTitleBaseXP']);
    final m = respectMultipliers(cfg, noSkip, noReroll);
    return jsRound(base * m.noSkip * m.noReroll);
  }

  Widget _taskCard(AccountView view, Map<String, dynamic> task) {
    final cat = view.category(jsStr(task['categoryId']));
    final low = jsNum(task['low']), high = jsNum(task['high']);
    final unit = jsStr(task['unit']).isEmpty ? cat.unit : jsStr(task['unit']);
    final amount = low == high ? '${_num(low)} ${unitLabel(unit, low)}' : '${_num(low)}–${_num(high)} ${unitLabel(unit, high)}';
    final respect = normalizeRespectState(view.state['respectState']);
    final title = _recommendedTitle(view, task);
    final inLibrary = title != null && view.library.any((t) => identical(t.raw, title.raw));
    final exact = Recommender(view.state, now: DateTime.now().millisecondsSinceEpoch).exactTitles;
    final reasons = asList(task['reasons']).map(jsStr).where((x) => x.isNotEmpty).toList();
    final rerolls = asList(task['v180RecommendationHistory']).length - 1;
    final bonus = _respectPreview(view.state, task);
    return _panel(children: [
      const Row(children: [
        Icon(Icons.auto_awesome_rounded, color: MF.accent, size: 18),
        SizedBox(width: 8),
        Text('MediaFlow Recommends', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: MF.accent)),
      ]),
      const SizedBox(height: 14),
      Row(children: [
        CategoryBadge(cat, size: 48),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(cat.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
            const SizedBox(height: 2),
            Text.rich(TextSpan(children: [
              const TextSpan(text: 'Consume ', style: TextStyle(color: MF.textDim)),
              TextSpan(text: amount, style: const TextStyle(fontWeight: FontWeight.w800)),
            ])),
          ]),
        ),
      ]),
      if (title != null) ...[
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: MF.raised, borderRadius: BorderRadius.circular(14)),
          child: Row(children: [
            Cover(title: title, category: cat, width: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Recommended title', style: TextStyle(fontSize: 11, color: MF.textDim, fontWeight: FontWeight.w700)),
                Text(title.title,
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                if (inLibrary) Text(progressText(title, cat), style: const TextStyle(color: MF.textDim, fontSize: 12)),
              ]),
            ),
            if (exact)
              TextButton(
                onPressed: _busy ? null : () => _action(TaskAction.rerollTitle),
                child: Text(rerolls > 0 ? 'Reroll title ($rerolls)' : 'Reroll title'),
              ),
          ]),
        ),
      ],
      if (reasons.isNotEmpty) ...[
        const SizedBox(height: 14),
        for (final r in reasons)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Padding(padding: EdgeInsets.only(top: 6), child: Icon(Icons.circle, size: 6, color: MF.accent)),
              const SizedBox(width: 8),
              Expanded(child: Text(r, style: const TextStyle(color: MF.textDim, fontSize: 13))),
            ]),
          ),
      ],
      const SizedBox(height: 14),
      _streaks(respect),
      if (bonus > 0) ...[
        const SizedBox(height: 8),
        Text('Follow it for a System Respect bonus of +${fmtNumber(bonus)} XP',
            style: const TextStyle(color: MF.good, fontSize: 12, fontWeight: FontWeight.w700)),
      ],
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: _busy ? null : () => _openForm(task),
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
        icon: const Icon(Icons.check_rounded),
        label: const Text('Log & Complete', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: _busy ? null : () => _action(TaskAction.reroll),
        icon: const Icon(Icons.shuffle_rounded),
        label: const Text('Give me something else'),
      ),
      const SizedBox(height: 4),
      Row(children: [
        Expanded(
          child: TextButton(
            onPressed: _busy ? null : () => _confirm('Skip this task?', 'Skipping breaks your no-skip and first-pick streaks.', 'Skip', () => _action(TaskAction.skip)),
            child: const Text('Skip'),
          ),
        ),
        Expanded(
          child: TextButton(
            onPressed: _busy ? null : () => _action(TaskAction.end),
            child: const Text('End session'),
          ),
        ),
      ]),
    ]);
  }

  /// The task's recommended title; a stand-in (showing the category icon) when
  /// it is no longer in the Library.
  LibraryTitle? _recommendedTitle(AccountView view, Map<String, dynamic> task) {
    final id = jsStr(task['libraryId']);
    if (id.isNotEmpty) {
      final found = view.library.where((t) => t.id == id).firstOrNull;
      if (found != null) return found;
    }
    final name = cleanTitle(task['title']);
    if (name.isEmpty) return null;
    return LibraryTitle({'id': id, 'title': name, 'categoryId': task['categoryId']});
  }

  Future<void> _confirm(String title, String body, String yes, VoidCallback action) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(yes)),
        ],
      ),
    );
    if (ok == true) action();
  }

  // ---- the logging form -------------------------------------------------------------

  List<Widget> _form(AccountView view) {
    final ed = _editor(view)!;
    final task = _task!;
    final cat = view.category(jsStr(task['categoryId']));
    final low = jsNum(task['low']), high = jsNum(task['high']);
    final unit = jsStr(task['unit']).isEmpty ? cat.unit : jsStr(task['unit']);
    final amount = low == high ? '${_num(low)} ${unitLabel(unit, low)}' : '${_num(low)}–${_num(high)} ${unitLabel(unit, high)}';
    final entries = ed.entries;
    return [
      _panel(padding: const EdgeInsets.fromLTRB(16, 14, 16, 14), children: [
        Row(children: [
          // The recommended title's own cover (category icon when it has none).
          if (_recommendedTitle(view, task) case final title?)
            Cover(title: title, category: cat, width: 46)
          else
            CategoryBadge(cat, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (_recommendedTitle(view, task) case final title?) ...[
                Text(title.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                const SizedBox(height: 2),
                Text('${cat.name} · Consume $amount',
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: MF.textDim, fontSize: 13)),
              ] else ...[
                Text(cat.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                Text('Consume $amount',
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: MF.textDim, fontSize: 13)),
              ],
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'quick', label: Text('Quick'), icon: Icon(Icons.flash_on_rounded)),
            ButtonSegment(value: 'itemized', label: Text('Advanced'), icon: Icon(Icons.format_list_numbered_rounded)),
          ],
          selected: {ed.itemized ? 'itemized' : 'quick'},
          onSelectionChanged: (s) => _edit((e) => e.switchInterface(s.first)),
        ),
        if (!ed.itemized) ...[
          const SizedBox(height: 10),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'progress', label: Text('Progress reached')),
              ButtonSegment(value: 'amount', label: Text('Amount consumed')),
            ],
            selected: {ed.mode},
            onSelectionChanged: (s) => _edit((e) {
              e.setMode(s.first);
              return null;
            }),
          ),
        ],
      ]),
      _panel(children: [
        Text('Titles', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        for (var i = 0; i < entries.length; i++)
          ed.itemized ? _unitEntry(view, ed, i, entries[i]) : _quickEntry(view, ed, i, entries[i]),
        if (!ed.itemized && jsStr(_entryDraft['title']).isNotEmpty) _quickComposer(view, ed) else _titlePicker(view, ed),
        if (!ed.itemized && ed.mode == 'amount' && entries.isEmpty) ...[
          const SizedBox(height: 10),
          const Text('Or log just an amount for this category:', style: TextStyle(color: MF.textDim, fontSize: 12)),
          const SizedBox(height: 6),
          _numberField(
            label: 'How many ${unitLabel(unit, 2)}',
            value: _plain(_logDraft!['amount']),
            onChanged: (v) {
              _logDraft!['amount'] = jsOut(v);
              _saveDraft();
            },
          ),
        ],
      ]),
      _panel(children: [
        _summary(view, ed, unit),
        const SizedBox(height: 12),
        TextField(
          controller: _note,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Anything else to note? (optional)', hintText: 'e.g. binged the season finale'),
          onChanged: (v) {
            _logDraft!['note'] = v;
            _noteTimer?.cancel();
            _noteTimer = Timer(const Duration(milliseconds: 700), _saveDraft);
          },
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!, style: const TextStyle(color: MF.bad)),
        ],
        const SizedBox(height: 14),
        FilledButton(
          onPressed: _busy ? null : _submit,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          child: _busy
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
              : const Text('Save & get next task', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        ),
        const SizedBox(height: 6),
        TextButton(
          onPressed: _busy ? null : () => _confirm('Discard this log?', 'The draft is removed here and on the website.', 'Discard', _closeForm),
          child: const Text('Cancel'),
        ),
        const Text('Your draft is saved to your account as you go — open it on the website to continue there.',
            textAlign: TextAlign.center, style: TextStyle(color: MF.textDim, fontSize: 12)),
      ]),
    ];
  }

  Widget _summary(AccountView view, LogDraftEditor ed, String unit) {
    final amount = ed.entries.isEmpty ? jsNum(_logDraft!['amount']) : ed.entries.fold<double>(0, (s, e) => s + jsNum(e['qty']));
    final minutes = jsNum(_logDraft!['minutes']);
    final derived = ed.itemized || ed.mode == 'progress';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('This log', style: TextStyle(color: MF.textDim, fontSize: 12, fontWeight: FontWeight.w700)),
            Text('${fmtNumber(amount)} ${unitLabel(unit, amount)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          ]),
        ),
        if (derived)
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            const Text('Time', style: TextStyle(color: MF.textDim, fontSize: 12, fontWeight: FontWeight.w700)),
            Text(ed.itemized ? _hms(jsNum(_logDraft!['v369DurationSeconds'])) : fmtMinutes(minutes),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          ]),
      ]),
      if (!derived) ...[
        const SizedBox(height: 10),
        _numberField(
          label: 'Minutes spent',
          value: _plain(minutes),
          onChanged: (v) {
            _logDraft!['minutes'] = jsOut(v);
            _saveDraft();
          },
        ),
      ],
    ]);
  }

  Widget _numberField({required String label, required String value, required ValueChanged<double> onChanged, String? helper}) {
    return TextFormField(
      key: ValueKey('$label|$_formGen'),
      initialValue: value,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
      decoration: InputDecoration(labelText: label, helperText: helper),
      onChanged: (t) => onChanged(double.tryParse(t.replaceAll(',', '.')) ?? 0),
    );
  }

  // ---- title picker ------------------------------------------------------------------

  Widget _titlePicker(AccountView view, LogDraftEditor ed) {
    final q = _search.text.trim().toLowerCase();
    final taskCat = jsStr(_task!['categoryId']);
    final added = ed.entries.map((e) => jsStr(e['libraryId'])).toSet();
    final matches = view.library
        .where((t) => t.status != 'dropped' && !(ed.itemized && added.contains(t.id)))
        .where((t) => q.isEmpty ? t.categoryId == taskCat && t.status != 'completed' : t.title.toLowerCase().contains(q))
        .toList()
      ..sort((a, b) {
        final ac = a.categoryId == taskCat ? 0 : 1, bc = b.categoryId == taskCat ? 0 : 1;
        if (ac != bc) return ac - bc;
        final ar = a.status == 'active' ? 0 : 1, br = b.status == 'active' ? 0 : 1;
        if (ar != br) return ar - br;
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      });
    final typed = _search.text.trim();
    final exists = view.library.any((t) => t.title.toLowerCase() == typed.toLowerCase());
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (ed.entries.isNotEmpty) const SizedBox(height: 6),
      TextField(
        controller: _search,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          hintText: ed.entries.isEmpty ? 'What did you watch or read?' : 'Add another title',
          prefixIcon: const Icon(Icons.search_rounded),
        ),
      ),
      const SizedBox(height: 4),
      for (final t in matches.take(q.isEmpty ? 6 : 10))
        ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          leading: Cover(title: t, category: view.category(t.categoryId), width: 30),
          title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text('${view.category(t.categoryId).name} · ${progressText(t, view.category(t.categoryId))}',
              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: MF.textDim, fontSize: 12)),
          trailing: const Icon(Icons.add_circle_outline_rounded, color: MF.accent),
          onTap: () => _pickTitle(t.id, t.title),
        ),
      if (typed.isNotEmpty && !exists && !ed.itemized)
        ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          leading: const Icon(Icons.fiber_new_rounded, color: MF.accent),
          title: Text('Add “$typed” as a new title'),
          subtitle: Text('Created in ${view.category(taskCat).name} when you save', style: const TextStyle(color: MF.textDim, fontSize: 12)),
          onTap: () => _pickTitle(null, typed),
        ),
      if (ed.itemized && typed.isNotEmpty && matches.isEmpty)
        const Padding(
          padding: EdgeInsets.all(8),
          child: Text('Per-unit logging uses titles from your Library.', style: TextStyle(color: MF.textDim)),
        ),
    ]);
  }

  // ---- Quick entries -------------------------------------------------------------------

  Widget _quickComposer(AccountView view, LogDraftEditor ed) {
    final item = ed.item(_entryDraft['libraryId']);
    final title = jsStr(_entryDraft['title']);
    final cat = item != null ? view.category(jsStr(item['categoryId'])) : view.category(jsStr(_task!['categoryId']));
    final seasons = LogDraftEditor.seasonsOf(item);
    final useSeasons = item != null && seasons.isNotEmpty && ed.mode == 'progress' && _entryDraft['v252UseSeasonView'] != false;
    final start = LogDraftEditor.startProgress(item);
    String label;
    if (ed.mode == 'progress') {
      label = useSeasons ? '${_cap(unitLabel(cat.unit, 1))} reached in season' : '${_cap(unitLabel(cat.unit, 1))} reached';
    } else {
      label = 'How many ${unitLabel(cat.unit, 2)}';
    }
    final repeat = item != null && LogDraftEditor.isComplete(item);
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: MF.raised, borderRadius: BorderRadius.circular(14), border: Border.all(color: MF.accentSoft)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
          IconButton(
            tooltip: 'Choose another title',
            icon: const Icon(Icons.close_rounded),
            onPressed: () => setState(() => _entryDraft = {'title': '', 'qty': 1, 'libraryId': null}),
          ),
        ]),
        Text(
          item == null
              ? 'New title in ${cat.name}'
              : '${cat.name} · ${repeat ? 'completed — logs a rewatch' : 'at ${_num(start)}${jsTruthy(item['total']) ? ' of ${_num(item['total'])}' : ''}'}',
          style: const TextStyle(color: MF.textDim, fontSize: 12),
        ),
        const SizedBox(height: 10),
        if (useSeasons) ...[
          DropdownButtonFormField<String>(
            initialValue: jsStr(_entryDraft['v252SeasonId']).isEmpty ? jsStr(seasons.first['id']) : jsStr(_entryDraft['v252SeasonId']),
            decoration: const InputDecoration(labelText: 'Season'),
            items: [
              for (final s in seasons)
                DropdownMenuItem(
                  value: jsStr(s['id']),
                  child: Text('${jsStr(s['name'])} · ${_num(s['progress'])}${s['total'] != null ? '/${_num(s['total'])}' : ''}'),
                ),
            ],
            onChanged: (v) => setState(() => _entryDraft = {..._entryDraft, 'v252SeasonId': v}),
          ),
          const SizedBox(height: 8),
        ],
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: TextField(
              controller: _value,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
              decoration: InputDecoration(labelText: label),
              onSubmitted: (_) => _addQuick(),
            ),
          ),
          const SizedBox(width: 10),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: FilledButton(onPressed: _addQuick, child: const Text('Add')),
          ),
        ]),
      ]),
    );
  }

  void _addQuick() {
    final v = double.tryParse(_value.text.trim().replaceAll(',', '.')) ?? 0;
    _edit((ed) {
      if (ed.mode == 'progress') {
        if (jsTruthy(ed.entryDraft['v252SeasonId']) && ed.entryDraft['v252UseSeasonView'] != false) {
          ed.entryDraft['v252SeasonEpisode'] = jsOut(v);
        } else {
          ed.entryDraft['endProgress'] = jsOut(v);
        }
      } else {
        ed.entryDraft['qty'] = jsOut(v);
      }
      final err = ed.addQuickEntry();
      if (err == null) _value.clear();
      return err;
    });
  }

  Widget _quickEntry(AccountView view, LogDraftEditor ed, int index, Map<String, dynamic> e) {
    final item = ed.item(e['libraryId']);
    final cat = item != null ? view.category(jsStr(item['categoryId'])) : view.category(jsStr(_task!['categoryId']));
    final qty = jsNum(e['qty']);
    final progress = ed.mode == 'progress' && item != null;
    final season = jsTruthy(e['v252SeasonId']) && e['v252UseSeasonView'] == true
        ? ' · ${jsStr(e['v252SeasonName'])} ep ${_num(e['v252SeasonEpisode'])}'
        : '';
    final detail = progress
        ? '${_num(e['v179StartProgress'])} → ${_num(e['v179EndProgress'])}$season'
        : (e['isNew'] == true && item == null ? 'new title' : '');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(color: MF.raised, borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(cleanTitle(e['title']), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
            Text(
              '+${fmtNumber(qty)} ${unitLabel(cat.unit, qty)}${detail.isEmpty ? '' : ' · $detail'}${e['isRepeat'] == true ? ' · rewatch' : ''}',
              style: const TextStyle(color: MF.textDim, fontSize: 12),
            ),
          ]),
        ),
        IconButton(
          tooltip: 'Less',
          icon: const Icon(Icons.remove_circle_outline_rounded),
          onPressed: () => _edit((x) {
            if (progress) {
              x.setEntryEnd(index, jsNum(e['v179EndProgress']) - 1);
            } else {
              x.setEntryQty(index, qty - 1 < 1 ? 1 : qty - 1);
            }
            return null;
          }),
        ),
        IconButton(
          tooltip: 'More',
          icon: const Icon(Icons.add_circle_outline_rounded),
          onPressed: () => _edit((x) {
            if (progress) {
              x.setEntryEnd(index, jsNum(e['v179EndProgress']) + 1);
            } else {
              x.setEntryQty(index, qty + 1);
            }
            return null;
          }),
        ),
        IconButton(
          tooltip: 'Remove',
          icon: const Icon(Icons.delete_outline_rounded, color: MF.bad),
          onPressed: () => _edit((x) {
            x.removeEntry(index);
            return null;
          }),
        ),
      ]),
    );
  }

  // ---- Per-unit entries ------------------------------------------------------------------

  Widget _unitEntry(AccountView view, LogDraftEditor ed, int index, Map<String, dynamic> e) {
    final item = ed.item(e['libraryId']);
    final cat = view.category(jsStr(item?['categoryId'] ?? _task!['categoryId']));
    final units = ed.units(e);
    final method = LogDraftEditor.method(e);
    final seasons = LogDraftEditor.seasonsOf(item);
    final selected = item == null ? null : ed.selectedSeason(e, item);
    final noun = _cap(unitLabel(cat.unit, 1));
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 12),
      decoration: BoxDecoration(color: MF.raised, borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(cleanTitle(e['title']), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
              Text(
                '${units.length} ${unitLabel(cat.unit, units.length)} · ${_hms(ed.runtimeSeconds(e))}'
                '${item != null ? ' · saved ${_num(item['progress'])}${jsTruthy(item['total']) ? '/${_num(item['total'])}' : ''}' : ''}'
                '${e['isRepeat'] == true ? ' · rewatch' : ''}',
                style: const TextStyle(color: MF.textDim, fontSize: 12),
              ),
            ]),
          ),
          IconButton(
            tooltip: 'Remove title',
            icon: const Icon(Icons.delete_outline_rounded, color: MF.bad),
            onPressed: () => _edit((x) {
              x.removeEntry(index);
              return null;
            }),
          ),
        ]),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: 'unit', label: Text('Per unit')),
            ButtonSegment(value: 'last', label: Text('Reached')),
            ButtonSegment(value: 'amount', label: Text('Amount')),
          ],
          selected: {method},
          onSelectionChanged: (s) => _edit((x) {
            x.setMethod(index, s.first);
            return null;
          }),
        ),
        if (seasons.isNotEmpty) ...[
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            key: ValueKey('season-$index-${jsStr(selected?['id'])}'),
            initialValue: jsStr(selected?['id']),
            decoration: const InputDecoration(labelText: 'Season'),
            items: [
              for (final s in seasons)
                DropdownMenuItem(
                  value: jsStr(s['id']),
                  child: Text('${jsStr(s['name'])} · ${_num(s['progress'])}${s['total'] != null ? '/${_num(s['total'])}' : ''}'),
                ),
            ],
            onChanged: (v) => _edit((x) {
              if (v != null) x.selectSeason(index, v);
              return null;
            }),
          ),
        ],
        const SizedBox(height: 8),
        if (method == 'unit') ...[
          for (var p = 0; p < units.length; p++) _unitRow(ed, index, p, units[p], noun),
          Row(children: [
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: item == null ? null : () => _edit((x) => x.addUnit(index)),
                icon: const Icon(Icons.add_rounded),
                label: Text(item == null ? 'Add' : 'Add $noun ${ed.nextNumber(e, item)}'),
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'More',
              onSelected: (v) {
                if (v == 'repeat') _edit((x) => x.addUnit(index, forceRepeat: true));
              },
              itemBuilder: (_) => const [PopupMenuItem(value: 'repeat', child: Text('Add a rewatch of an earlier unit'))],
            ),
          ]),
        ] else
          _bulkPanel(ed, index, e, item, selected, cat, method),
      ]),
    );
  }

  Widget _unitRow(LogDraftEditor ed, int index, int pos, Map<String, dynamic> u, String noun) {
    final seconds = LogDraftEditor.unitSeconds(u);
    final season = jsTruthy(u['seasonName']) ? '${jsStr(u['seasonName'])} · ' : '';
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: MF.surface, borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$season$noun ${_num(u['number'])}${u['isRepeat'] == true ? ' · rewatch' : ''}',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            Wrap(spacing: 4, children: [
              ActionChip(
                visualDensity: VisualDensity.compact,
                avatar: const Icon(Icons.timer_outlined, size: 16),
                label: Text(_hms(seconds)),
                onPressed: () => _editDuration(index, pos, seconds),
              ),
              ActionChip(
                visualDensity: VisualDensity.compact,
                avatar: const Icon(Icons.schedule_rounded, size: 16),
                label: Text(_when(jsNum(u['loggedAt']))),
                onPressed: () => _editTime(index, pos, jsNum(u['loggedAt']).toInt()),
              ),
            ]),
          ]),
        ),
        IconButton(
          tooltip: u['isRepeat'] == true ? 'Mark as first watch' : 'Mark as rewatch',
          icon: Icon(Icons.replay_rounded, color: u['isRepeat'] == true ? MF.accent : MF.textDim),
          onPressed: () => _edit((x) => x.toggleUnitRepeat(index, pos)),
        ),
        IconButton(
          tooltip: 'Remove',
          icon: const Icon(Icons.close_rounded),
          onPressed: () => _edit((x) {
            x.removeUnit(index, pos);
            return null;
          }),
        ),
      ]),
    );
  }

  Future<int?> _askDuration(String title, num seconds) {
    final s = seconds.round();
    final h = TextEditingController(text: '${s ~/ 3600}');
    final m = TextEditingController(text: '${s % 3600 ~/ 60}');
    final sec = TextEditingController(text: '${s % 60}');
    InputDecoration d(String l) => InputDecoration(labelText: l);
    final f = [FilteringTextInputFormatter.digitsOnly];
    return showDialog<int>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Row(children: [
          Expanded(child: TextField(controller: h, keyboardType: TextInputType.number, inputFormatters: f, decoration: d('Hours'))),
          const SizedBox(width: 8),
          Expanded(child: TextField(controller: m, keyboardType: TextInputType.number, inputFormatters: f, decoration: d('Minutes'))),
          const SizedBox(width: 8),
          Expanded(child: TextField(controller: sec, keyboardType: TextInputType.number, inputFormatters: f, decoration: d('Seconds'))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final hh = int.tryParse(h.text) ?? 0, mm = (int.tryParse(m.text) ?? 0).clamp(0, 59), ss = (int.tryParse(sec.text) ?? 0).clamp(0, 59);
              Navigator.pop(c, hh * 3600 + mm * 60 + ss);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _editDuration(int index, int pos, num seconds) async {
    final total = await _askDuration('Runtime', seconds);
    if (total == null || !mounted) return;
    _edit((x) {
      // Same as typing h, m and s into the website's three duration boxes.
      x.editUnit(index, pos, 'duration-0', total ~/ 3600);
      x.editUnit(index, pos, 'duration-1', total % 3600 ~/ 60);
      return x.editUnit(index, pos, 'duration-2', total % 60);
    });
  }

  Future<int?> _askWhen(int initialMs) async {
    final initial = DateTime.fromMillisecondsSinceEpoch(initialMs);
    final now = DateTime.now();
    final day = await showDatePicker(
      context: context,
      initialDate: initial.isAfter(now) ? now : initial,
      firstDate: DateTime(2000),
      lastDate: now,
    );
    if (day == null || !mounted) return null;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(initial));
    if (time == null) return null;
    return DateTime(day.year, day.month, day.day, time.hour, time.minute).millisecondsSinceEpoch;
  }

  Future<void> _editTime(int index, int pos, int current) async {
    final when = await _askWhen(current);
    if (when == null || !mounted) return;
    _edit((x) => x.editUnit(index, pos, 'time', when));
  }

  Widget _bulkPanel(LogDraftEditor ed, int index, Map<String, dynamic> e, Map<String, dynamic>? item,
      Map<String, dynamic>? season, Category cat, String method) {
    if (item == null) return const SizedBox.shrink();
    final rel = ed.relevant(e, item);
    final base = LogDraftEditor.bulkBase(e, item, season);
    final highest = rel.units.isEmpty ? base : rel.units.map((u) => jsNum(u['number']).toInt()).reduce((a, b) => a > b ? a : b);
    final value = method == 'last' ? highest : rel.units.length;
    final label = method == 'last' ? '${_cap(unitLabel(cat.unit, 1))} reached' : '${_cap(unitLabel(cat.unit, 2))} consumed';
    final stamp = ed.bulkStamp(e, method);
    final manual = e['v394RuntimeManual'] == true;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextFormField(
        key: ValueKey('bulk-$index-$method-${jsStr(season?['id'])}-$value'),
        initialValue: '$value',
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(labelText: label, helperText: 'Saved progress: $base · draft: ${rel.units.length}'),
        onFieldSubmitted: (t) => _setQuantity(index, t),
        onChanged: (t) => _pendingQuantity = (index, t),
      ),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton(
          onPressed: () {
            final pending = _pendingQuantity;
            if (pending != null && pending.$1 == index) _setQuantity(index, pending.$2);
          },
          child: const Text('Apply'),
        ),
      ),
      ActionChip(
        avatar: const Icon(Icons.schedule_rounded, size: 16),
        label: Text('Consumed at ${_when(stamp)}'),
        onPressed: () async {
          final when = await _askWhen(stamp);
          if (when != null && mounted) _edit((x) => x.setWhen(index, when));
        },
      ),
      const SizedBox(height: 6),
      Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Customize total runtime'),
            Text(manual ? _hms(ed.runtimeSeconds(e)) : 'Automatic: ${_hms(ed.runtimeSeconds(e))}',
                style: const TextStyle(color: MF.textDim, fontSize: 12)),
          ]),
        ),
        Switch(value: manual, onChanged: (v) => _edit((x) => x.toggleRuntime(index, v))),
      ]),
      if (manual)
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.timer_outlined),
            label: const Text('Set total runtime'),
            onPressed: () async {
              final total = await _askDuration('Total runtime', ed.runtimeSeconds(e));
              if (total != null && mounted) {
                _edit((x) {
                  x.setRuntime(index, total);
                  return null;
                });
              }
            },
          ),
        ),
    ]);
  }

  (int, String)? _pendingQuantity;

  Future<void> _setQuantity(int index, String text) async {
    final view = account.view;
    final ed = view == null ? null : _editor(view);
    if (ed == null) return;
    _pendingQuantity = null;
    if (ed.quantityReplacesDetail(index)) {
      var ok = false;
      await _confirm(
        'Replace detailed entries?',
        'Changing this number replaces the detailed unit entries (numbers, times, runtimes or rewatch flags) for this season. '
            'Only the unsaved draft changes.',
        'Replace',
        () => ok = true,
      );
      if (!ok || !mounted) return;
    }
    _edit((x) => x.setQuantity(index, int.tryParse(text.trim()) ?? -1));
  }
}
