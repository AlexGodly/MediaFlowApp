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
import '../logic/log_arrange.dart';
import '../logic/log_draft.dart';
import '../logic/rec_submit.dart';
import '../logic/recommend.dart';
import '../logic/resume.dart';
import '../logic/xp_preview.dart';
import '../state/models.dart';
import '../util/js.dart';
import 'log_sheet.dart';
import 'logging_library.dart';
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

  PickerState _picker = PickerState();
  XpPreview? _xp;
  bool _xpBusy = false;
  int _xpGen = 0;
  Timer? _xpTimer;
  bool _fabOpen = false;

  bool _busy = false;
  String? _error;
  final _note = TextEditingController();
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
    _xpTimer?.cancel();
    _note.dispose();
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
    _picker = PickerState.fromUi(logging['ui']);
    final task = asMap(logging['currentTask']);
    if (logging['active'] == true && task != null) {
      _task = task;
      _logDraft = asMap(logging['logDraft']) ?? <String, dynamic>{};
      _entryDraft = asMap(logging['entryDraft']) ?? <String, dynamic>{'title': '', 'qty': 1};
      _note.text = jsStr(_logDraft!['note']);
      _scheduleXp();
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
    _error = null;
    _xp = null;
    _xpKey = '';
    _xpGen++;
    _fabOpen = false;
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

  void _saveDraft({bool xp = true}) {
    final task = _task, draft = _logDraft;
    if (task == null || draft == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    _draftAt = now > _draftAt ? now : _draftAt + 1;
    _ui = {...?asMap(_ui), ..._picker.toUi()};
    unawaited(account.saveDraft(
      activeLogging(task: task, logDraft: draft, entryDraft: _entryDraft, modifiedAt: _draftAt, ui: _ui),
    ));
    if (xp) _scheduleXp();
  }

  /// Recomputes "XP for this log" shortly after the draft stops changing.
  /// The trial save runs in the background, one at a time; changes made while
  /// it runs are picked up by one more run.
  String _xpKey = '';
  bool _xpRunning = false;
  bool _xpAgain = false;

  String _currentXpKey() => '${jsStr(_task?['id'])}|${jsonEncode(_logDraft)}';

  void _scheduleXp() {
    // Nothing that affects XP changed (e.g. a filter or collapse toggle).
    if (_currentXpKey() == _xpKey && _xp != null) return;
    _xpTimer?.cancel();
    _xpTimer = Timer(const Duration(milliseconds: 650), _runXp);
  }

  void _runXp() {
    if (!mounted) return;
    if (_xpRunning) {
      _xpAgain = true;
      return;
    }
    final task = _task, draft = _logDraft;
    if (account.view == null || task == null || draft == null) return;
    final key = _currentXpKey();
    if (key == _xpKey && _xp != null) return;
    final gen = ++_xpGen;
    _xpRunning = true;
    setState(() => _xpBusy = true);
    account.previewXp(task, draft).then((xp) {
      if (!mounted || gen != _xpGen) return;
      _xpKey = key;
      setState(() {
        _xp = xp;
        _xpBusy = false;
      });
    }, onError: (Object e) {
      if (mounted && gen == _xpGen) setState(() => _xpBusy = false);
    }).whenComplete(() {
      _xpRunning = false;
      if (_xpAgain && mounted) {
        _xpAgain = false;
        _runXp();
      }
    });
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
      _xp = null;
    });
    // Like the website, the recommended title is one tap away ("Add
    // recommended title") rather than added for you, so Quick / Advanced can
    // still be switched before any title is in the log.
    _saveDraft();
  }

  /// Adds Library titles to the log (`v378QuickAdd` / bulk add).
  int _quickAdd(List<String> ids) {
    final view = account.view;
    final ed = view == null ? null : _editor(view);
    if (ed == null) return 0;
    var n = 0;
    for (final id in ids) {
      if (ed.quickAdd(id, defer: true) == null) n++;
    }
    if (n > 0) ed.syncAfterAdd();
    setState(() {});
    if (n > 0) _saveDraft();
    return n;
  }

  void _addNewTitle(String title) => _edit((ed) => ed.addNewTitle(title));

  /// "Add recommended title": adds it, or opens it if it's already in the log.
  void _addRecommended() {
    final id = jsStr(_task?['libraryId']);
    if (id.isEmpty || _logDraft == null) return;
    _logDraft!['v379HideAddedTitles'] = false;
    final existing = asList(_logDraft!['entries']).map(asMap).whereType<Map<String, dynamic>>()
        .where((e) => jsStr(e['libraryId']) == id).firstOrNull;
    if (existing != null) {
      existing['v369Collapsed'] = false;
      existing['v379QuickCollapsed'] = false;
      setState(() {});
      _saveDraft();
      _snack('The recommended title is already in this log.');
      return;
    }
    _quickAdd([id]);
  }

  Future<void> _submit() async {
    // Apply a number that is still being typed (fields apply when you leave them).
    FocusManager.instance.primaryFocus?.unfocus();
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
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
      floatingActionButton: _fab(view, task, active),
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
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 104), // room for the + button
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

  bool get _workspaceCollapsed => asMap(account.view?.state['settings'])?['v419LoggingCollapsed'] == true;

  List<Widget> _form(AccountView view) {
    final ed = _editor(view)!;
    final task = _task!;
    final cat = view.category(jsStr(task['categoryId']));
    final unit = jsStr(task['unit']).isEmpty ? cat.unit : jsStr(task['unit']);
    final entries = ed.entries;
    final collapsed = _workspaceCollapsed;
    // The website's count: Advanced units, or each Quick title's amount.
    final staged = entries.fold<double>(
        0, (n, e) => n + (e['v369Units'] is List ? (e['v369Units'] as List).length.toDouble() : (jsNum(e['qty']) > 0 ? jsNum(e['qty']).floorToDouble() : 0.0)));
    return [
      _formHeader(view, ed, task, cat, unit),
      _libraryPanel(view, ed),
      _workspaceBar(entries.length, staged, collapsed),
      if (!collapsed) ...[
        _titlesPanel(view, ed, unit),
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
        ]),
        _xpCard(),
      ],
      _savePanel(collapsed),
    ];
  }

  /// The recommendation (its own cover), the Quick / Advanced switch and the Quick mode.
  Widget _formHeader(AccountView view, LogDraftEditor ed, Map<String, dynamic> task, Category cat, String unit) {
    final low = jsNum(task['low']), high = jsNum(task['high']);
    final amount = low == high ? '${_num(low)} ${unitLabel(unit, low)}' : '${_num(low)}–${_num(high)} ${unitLabel(unit, high)}';
    final title = _recommendedTitle(view, task);
    final added = title != null && ed.addedIds.contains(title.id);
    return _panel(padding: const EdgeInsets.fromLTRB(16, 14, 16, 14), children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (title != null) Cover(title: title, category: cat, width: 52) else CategoryBadge(cat, size: 44),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (title != null) ...[
              const Text('RECOMMENDED TITLE',
                  style: TextStyle(color: MF.accent, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 0.6)),
              const SizedBox(height: 2),
              Text(title.title, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
              const SizedBox(height: 2),
              Text('${cat.name} · Consume $amount', style: const TextStyle(color: MF.textDim, fontSize: 13)),
            ] else ...[
              Text(cat.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              Text('Consume $amount', style: const TextStyle(color: MF.textDim, fontSize: 13)),
            ],
          ]),
        ),
      ]),
      if (title != null) ...[
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: added
              ? OutlinedButton.icon(
                  onPressed: _addRecommended,
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: const Text('Added · show it'),
                )
              : FilledButton.tonalIcon(
                  onPressed: _addRecommended,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Add recommended title'),
                ),
        ),
      ],
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
    ]);
  }

  // ---- Logging Library ---------------------------------------------------------------

  Widget _library(AccountView view, LogDraftEditor ed, {bool scrollable = false, VoidCallback? changed}) {
    return LoggingLibrary(
      key: ValueKey('library-$_formGen-$scrollable'),
      view: view,
      draft: _logDraft!,
      picker: _picker,
      scrollable: scrollable,
      onPicker: (p) {
        _picker = p;
        _saveDraft(xp: false);
        changed?.call();
      },
      onAdd: (ids) {
        final n = _quickAdd(ids);
        changed?.call();
        return n;
      },
      onAddNew: ed.itemized
          ? null
          : (t) {
              _addNewTitle(t);
              changed?.call();
            },
      recommendedId: jsStr(_task?['libraryId']).isEmpty ? null : jsStr(_task!['libraryId']),
      onAddRecommended: () {
        _addRecommended();
        changed?.call();
      },
      onPageSize: (n) => account.setSetting(['v175PageSizes', 'loggingLibrary'], n),
    );
  }

  Widget _libraryPanel(AccountView view, LogDraftEditor ed) {
    return _panel(padding: const EdgeInsets.fromLTRB(16, 4, 16, 8), children: [
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.local_library_rounded, color: MF.accent),
        title: const Text('Logging Library', style: TextStyle(fontWeight: FontWeight.w800)),
        subtitle: const Text('Search, filter and add titles from your Library', style: TextStyle(color: MF.textDim, fontSize: 12)),
        trailing: Icon(_picker.open ? Icons.expand_less_rounded : Icons.expand_more_rounded),
        onTap: () {
          setState(() => _picker.open = !_picker.open);
          _saveDraft(xp: false);
        },
      ),
      if (_picker.open) ...[
        _library(view, ed),
        const SizedBox(height: 8),
      ],
    ]);
  }

  /// The "+" button's Add titles: the same Logging Library in a sheet.
  Future<void> _openLibrarySheet() async {
    if (_logDraft == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: MF.surface,
      builder: (c) => SizedBox(
        height: MediaQuery.sizeOf(c).height * 0.9,
        child: LiveBuilder(
          listenable: account,
          builder: (c, _) => StatefulBuilder(builder: (c, set) {
            final view = account.view;
            final ed = view == null ? null : _editor(view);
            if (view == null || ed == null) {
              return const Center(child: Text('Logging was closed.', style: TextStyle(color: MF.textDim)));
            }
            final n = ed.entries.length;
            return Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Add titles', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                      Text('$n title${n == 1 ? '' : 's'} in this log', style: const TextStyle(color: MF.textDim, fontSize: 12)),
                    ]),
                  ),
                  FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Done')),
                ]),
              ),
              Expanded(child: _library(view, ed, scrollable: true, changed: () => set(() {}))),
            ]);
          }),
        ),
      ),
    );
  }

  // ---- Logging Workspace -------------------------------------------------------------

  Widget _workspaceBar(int titles, double units, bool collapsed) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: MF.raised,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: MF.border)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => account.setSetting(['v419LoggingCollapsed'], !collapsed),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
            child: Row(children: [
              const Icon(Icons.space_dashboard_rounded, color: MF.accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Logging Workspace', style: TextStyle(fontWeight: FontWeight.w800)),
                  Text(
                    '$titles title${titles == 1 ? '' : 's'} · ${fmtNumber(units)} unit${units == 1 ? '' : 's'} staged',
                    style: const TextStyle(color: MF.textDim, fontSize: 12),
                  ),
                ]),
              ),
              Text(collapsed ? 'Expand' : 'Collapse', style: const TextStyle(color: MF.textDim, fontSize: 13)),
              Icon(collapsed ? Icons.expand_more_rounded : Icons.expand_less_rounded, color: MF.textDim),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _titlesPanel(AccountView view, LogDraftEditor ed, String unit) {
    final draft = _logDraft!;
    final entries = ed.entries;
    final hidden = draft['v379HideAddedTitles'] == true;
    final order = entries.isEmpty ? const <int>[] : orderedEntries(draft, view.state);
    final sort = entries.isEmpty ? 'logAdded' : jsStr(orderState(draft)['sort']);
    final dir = entries.isEmpty ? 'desc' : jsStr(orderState(draft)['dir']);
    return _panel(children: [
      Row(children: [
        const Expanded(child: Text('Titles', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
        if (entries.isNotEmpty)
          TextButton.icon(
            onPressed: () {
              draft['v379HideAddedTitles'] = !hidden;
              setState(() {});
              _saveDraft(xp: false);
            },
            icon: Icon(hidden ? Icons.visibility_rounded : Icons.visibility_off_rounded, size: 18),
            label: Text(hidden ? 'Show Added Titles' : 'Hide Added Titles'),
          ),
      ]),
      if (entries.isEmpty) ...[
        const SizedBox(height: 4),
        Text(
          ed.itemized
              ? 'No titles yet. Add titles from the Logging Library, then log each unit.'
              : 'No titles yet. Add titles from the Logging Library, or type a new title in its search.',
          style: const TextStyle(color: MF.textDim),
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: _openLibrarySheet,
            icon: const Icon(Icons.library_add_rounded),
            label: const Text('Add titles'),
          ),
        ),
      ] else if (hidden) ...[
        const SizedBox(height: 4),
        Text('${entries.length} added title${entries.length == 1 ? '' : 's'} hidden.', style: const TextStyle(color: MF.textDim)),
      ] else ...[
        const SizedBox(height: 6),
        // "Arrange your session" (v373).
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          CompactDropdown<String>(
            value: sort,
            items: kArrangeSorts,
            onChanged: (v) {
              setArrangeSort(draft, view.state, v);
              setState(() {});
              _saveDraft(xp: false);
            },
          ),
          if (sort != 'custom' && sort != 'random')
            ActionChip(
              avatar: Icon(dir == 'asc' ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, size: 16),
              label: Text(dir == 'asc' ? 'Ascending' : 'Descending'),
              onPressed: () {
                toggleArrangeDirection(draft);
                setState(() {});
                _saveDraft(xp: false);
              },
            ),
          ActionChip(
            avatar: const Icon(Icons.shuffle_rounded, size: 16),
            label: const Text('Reshuffle'),
            onPressed: () {
              reshuffle(draft, DateTime.now().millisecondsSinceEpoch);
              setState(() {});
              _saveDraft(xp: false);
            },
          ),
          TextButton.icon(
            onPressed: () => _confirm(
              'Clear all added titles?',
              'Remove ${entries.length} added title${entries.length == 1 ? '' : 's'} and all their unsaved logging entries? '
                  'Saved Library data, History and XP will not be changed. This cannot be undone.',
              'Clear titles',
              () {
                var n = 0;
                _edit((x) {
                  n = x.clearAll();
                  return null;
                });
                _snack('$n added title${n == 1 ? '' : 's'} cleared.');
              },
            ),
            icon: const Icon(Icons.clear_all_rounded, size: 18, color: MF.bad),
            label: const Text('Clear all titles', style: TextStyle(color: MF.bad)),
          ),
        ]),
        const SizedBox(height: 10),
        for (var p = 0; p < order.length; p++)
          ed.itemized
              ? _unitEntry(view, ed, order[p], entries[order[p]], p, order.length)
              : _quickEntry(view, ed, order[p], entries[order[p]], p, order.length),
      ],
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
    ]);
  }

  /// Move up / down / top / bottom (switches the arrangement to Custom order) and Remove.
  Widget _entryMenu(AccountView view, int index, int pos, int count, String title) {
    void move(int target) {
      moveEntry(_logDraft!, view.state, index, target);
      setState(() {});
      _saveDraft(xp: false);
    }

    return PopupMenuButton<String>(
      tooltip: 'More',
      onSelected: (v) {
        switch (v) {
          case 'top':
            move(0);
          case 'up':
            move(pos - 1);
          case 'down':
            move(pos + 1);
          case 'bottom':
            move(count - 1);
          case 'remove':
            _edit((x) {
              x.removeEntry(index);
              return null;
            });
        }
      },
      itemBuilder: (_) => [
        if (pos > 0) const PopupMenuItem(value: 'top', child: Text('Move to top')),
        if (pos > 0) const PopupMenuItem(value: 'up', child: Text('Move up')),
        if (pos < count - 1) const PopupMenuItem(value: 'down', child: Text('Move down')),
        if (pos < count - 1) const PopupMenuItem(value: 'bottom', child: Text('Move to bottom')),
        PopupMenuItem(value: 'remove', child: Text('Remove $title', maxLines: 1, overflow: TextOverflow.ellipsis)),
      ],
    );
  }

  /// A cover for an added title (a stand-in tile for a typed new title).
  Widget _entryCover(AccountView view, Map<String, dynamic>? item, Map<String, dynamic> e, Category cat, double width) {
    final title = item != null ? LibraryTitle(item) : LibraryTitle(<String, dynamic>{'title': e['title'], 'categoryId': cat.id});
    return Cover(title: title, category: cat, width: width);
  }

  Widget _collapseButton(bool collapsed, VoidCallback onTap) => IconButton(
        tooltip: collapsed ? 'Expand' : 'Collapse',
        visualDensity: VisualDensity.compact,
        icon: Icon(collapsed ? Icons.unfold_more_rounded : Icons.unfold_less_rounded),
        onPressed: onTap,
      );

  void _toggleFlag(Map<String, dynamic> e, String key) {
    e[key] = !(e[key] == true);
    setState(() {});
    _saveDraft(xp: false);
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

  // ---- XP for this log ----------------------------------------------------------------

  Widget _xpRow(String label, num xp, {bool strong = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(child: Text(label, style: TextStyle(color: strong ? null : MF.textDim, fontWeight: strong ? FontWeight.w800 : null))),
          Text('+${fmtNumber(jsRound(xp.toDouble()))} XP', style: const TextStyle(fontWeight: FontWeight.w800)),
        ]),
      );

  Widget _xpCard() {
    final xp = _xp;
    final attention = xp?.error;
    return _panel(children: [
      Row(children: [
        const Icon(Icons.bolt_rounded, color: MF.accent),
        const SizedBox(width: 8),
        const Expanded(child: Text('XP for this log', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
        if (_xpBusy) ...[
          const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 10),
        ],
        Text(xp == null || attention != null ? '—' : '+${fmtNumber(xp.total)} XP',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: MF.accent)),
      ]),
      if (xp == null)
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text('Calculating…', style: TextStyle(color: MF.textDim, fontSize: 13)),
        )
      else if (attention != null) ...[
        const SizedBox(height: 8),
        const Text('Draft needs attention', style: TextStyle(color: MF.bad, fontWeight: FontWeight.w800)),
        Text(attention, style: const TextStyle(color: MF.textDim, fontSize: 13)),
      ] else if (!xp.eligible)
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text('Add titles and what you consumed to see the XP this log earns.', style: TextStyle(color: MF.textDim, fontSize: 13)),
        )
      else ...[
        const SizedBox(height: 4),
        Text(
          '${xp.respected ? 'Recommended category respected' : 'Recommendation not followed'}'
          ' · Day ${fmtNumber(xp.streakDay)} ×${fmtNumber(xp.dayMultiplier)}',
          style: TextStyle(color: xp.respected ? MF.good : MF.textDim, fontSize: 13, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        _xpRow('Consumption', xp.consumption),
        _xpRow('System Respect', xp.respect),
        _xpRow('Day-streak bonus', xp.streakBonus),
        for (final e in xp.extras) _xpRow(jsStr(e['label']), jsNum(e['xp'])),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 6),
            title: const Text('Full breakdown', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            children: [
              for (final c in xp.categories)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${jsStr(c['name'])}${jsStr(c['status']).isEmpty ? '' : ' · ${_cap(jsStr(c['status']))}'}',
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                        Text(
                          '${fmtNumber(jsNum(c['amount']))} ${unitLabel(jsStr(c['unit']), jsNum(c['amount']))}'
                          ' · ${fmtMinutes(jsNum(c['minutes']))}'
                          ' · ${fmtNumber(jsRound(jsNum(c['base'])))} × ${fmtNumber(jsNum(c['rotation']))}',
                          style: const TextStyle(color: MF.textDim, fontSize: 12),
                        ),
                      ]),
                    ),
                    Text('+${fmtNumber(jsRound(jsNum(c['xp'])))}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  ]),
                ),
              if (xp.respectDetails.isNotEmpty) ...[
                const Divider(),
                _detail('Recommended category XP', xp.respectDetails['categoryXP']),
                _detail('Recommended title XP', xp.respectDetails['titleXP']),
                _detail('Recommended titles matched', '${_num(xp.respectDetails['matched'])} of ${_num(xp.respectDetails['slots'])}'),
                _detail('No-skip streak', '${_num(xp.respectDetails['noSkip'])} · ×${_num(xp.respectDetails['noSkipMultiplier'])}'),
                _detail('No-reroll streak', '${_num(xp.respectDetails['noReroll'])} · ×${_num(xp.respectDetails['noRerollMultiplier'])}'),
              ],
              if (xp.rawTotal > 0) _detail('Before day-streak multiplier', '${fmtNumber(jsRound(xp.rawTotal.toDouble()))} XP'),
            ],
          ),
        ),
      ],
    ]);
  }

  Widget _detail(String label, Object? value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Expanded(child: Text(label, style: const TextStyle(color: MF.textDim, fontSize: 12))),
          Text(value is num ? fmtNumber(jsRound(value.toDouble())) : '$value', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        ]),
      );

  Widget _savePanel(bool collapsed) {
    final xp = _xp;
    return _panel(children: [
      if (collapsed && xp != null && xp.error == null && xp.eligible)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text('XP for this log: +${fmtNumber(xp.total)} XP',
              textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, color: MF.accent)),
        ),
      if (_error != null) ...[
        Text(_error!, style: const TextStyle(color: MF.bad)),
        const SizedBox(height: 10),
      ],
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
    ]);
  }

  // ---- the "+" button -------------------------------------------------------------------

  Widget? _fab(AccountView view, Map<String, dynamic>? task, bool active) {
    // The website's "Show the floating + button" setting (v405).
    if (asMap(view.state['settings'])?['v405ShowFloatingAdd'] == false) return null;
    if (!active || task == null) {
      return FloatingActionButton(
        heroTag: null,
        tooltip: 'Log any title (Batch Log)',
        onPressed: () => showLogSheet(context, account),
        child: const Icon(Icons.add_rounded),
      );
    }
    final formOpen = _task != null && _logDraft != null;
    Widget item(String label, IconData icon, VoidCallback onTap) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: FloatingActionButton.extended(
            heroTag: null,
            onPressed: _busy ? null : onTap,
            icon: Icon(icon),
            label: Text(label),
          ),
        );
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
      if (_fabOpen) ...[
        item('Add titles', Icons.library_add_rounded, () {
          setState(() => _fabOpen = false);
          if (_task == null) _openForm(task);
          _openLibrarySheet();
        }),
        if (formOpen)
          item('Save & get next task', Icons.task_alt_rounded, () {
            setState(() => _fabOpen = false);
            _quickSave();
          }),
      ],
      FloatingActionButton(
        heroTag: null,
        tooltip: _fabOpen ? 'Close' : 'Add titles or save',
        onPressed: () => setState(() => _fabOpen = !_fabOpen),
        child: AnimatedRotation(
          turns: _fabOpen ? 0.125 : 0,
          duration: const Duration(milliseconds: 150),
          child: const Icon(Icons.add_rounded),
        ),
      ),
    ]);
  }

  /// "Save & get next task" from the "+" button: one confirm showing the XP.
  Future<void> _quickSave() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await Future<void>.delayed(Duration.zero);
    final view = account.view;
    final task = _task, draft = _logDraft;
    if (view == null || task == null || draft == null || !mounted) return;
    final problem = _editor(view)!.validate();
    if (problem != null) {
      setState(() => _error = problem);
      _snack(problem);
      return;
    }
    // Reuse the card's figure when it is for exactly this log.
    XpPreview? xp = _xp != null && !_xpBusy && _xpKey == _currentXpKey() ? _xp : null;
    if (xp == null) {
      setState(() => _busy = true);
      try {
        xp = await account.previewXp(task, draft);
      } catch (_) {
        xp = _xp;
      }
      if (!mounted) return;
      setState(() => _busy = false);
    }
    if (!mounted) return;
    final total = xp != null && xp.error == null && xp.eligible ? xp.total : null;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Save & get next task?'),
        content: Text(total == null ? 'Save this log and get your next task.' : 'This log earns +${fmtNumber(total)} XP.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Not yet')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok == true && mounted) await _submit();
  }

  // ---- Quick entries -------------------------------------------------------------------

  Widget _quickEntry(AccountView view, LogDraftEditor ed, int index, Map<String, dynamic> e, int pos, int count) {
    final item = ed.item(e['libraryId']);
    final cat = item != null ? view.category(jsStr(item['categoryId'])) : view.category(jsStr(_task!['categoryId']));
    final qty = jsNum(e['qty']);
    final collapsed = e['v379QuickCollapsed'] == true;
    final progressMode = ed.mode == 'progress';
    final title = cleanTitle(e['title']);
    final parts = <String>[
      cat.name,
      if (item != null) statusName(jsStr(item['status']).isEmpty ? 'planned' : jsStr(item['status'])),
      if (item != null) jsTruthy(item['total']) ? '${_num(item['progress'])}/${_num(item['total'])}' : 'Progress ${_num(item['progress'])}',
      if (item == null) 'New title',
      if (LogDraftEditor.seasonsOf(item).isNotEmpty) '${LogDraftEditor.seasonsOf(item).length} seasons',
      if (e['isRepeat'] == true) 'Rewatch / reread',
    ];
    final start = jsNum(e['v179StartProgress']);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(10, 10, 4, 10),
      decoration: BoxDecoration(color: MF.raised, borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _entryCover(view, item, e, cat, collapsed ? 30 : 44),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
              Text(
                collapsed ? '+${fmtNumber(qty)} ${unitLabel(cat.unit, qty)}' : parts.join(' · '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: MF.textDim, fontSize: 12),
              ),
            ]),
          ),
          _collapseButton(collapsed, () => _toggleFlag(e, 'v379QuickCollapsed')),
          _entryMenu(view, index, pos, count, title),
        ]),
        if (!collapsed) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              Expanded(
                child: progressMode
                    ? CommitField(
                        key: ValueKey('end-${entryKey(e)}'),
                        value: _plain(e['v179EndProgress']),
                        label: item == null ? '${_cap(unitLabel(cat.unit, 1))} reached' : _progressLabel(item, cat),
                        helper: item == null ? null : 'Saved at ${_num(start)}${jsTruthy(item['total']) ? ' of ${_num(item['total'])}' : ''}',
                        onCommit: (t) => _edit((x) {
                          final v = double.tryParse(t.replaceAll(',', '.')) ?? 0;
                          if (item == null) {
                            x.setNewTitleEnd(index, v);
                          } else {
                            x.setEntryEnd(index, v);
                          }
                          return null;
                        }),
                      )
                    : CommitField(
                        key: ValueKey('qty-${entryKey(e)}'),
                        value: _plain(qty),
                        label: 'Consumed',
                        decimal: false,
                        onCommit: (t) => _edit((x) {
                          x.setEntryQty(index, double.tryParse(t.replaceAll(',', '.')) ?? 0);
                          return null;
                        }),
                      ),
              ),
              const SizedBox(width: 12),
              Text(
                '+${fmtNumber(qty)} ${unitLabel(cat.unit, qty)}',
                style: TextStyle(fontWeight: FontWeight.w800, color: qty > 0 ? MF.accent : MF.textDim),
              ),
            ]),
          ),
        ],
      ]),
    );
  }

  String _progressLabel(Map<String, dynamic> item, Category cat) {
    final noun = _cap(unitLabel(cat.unit, 1));
    return '$noun reached';
  }

  // ---- Advanced entries ------------------------------------------------------------------

  static const _shownUnits = 40;

  Widget _unitEntry(AccountView view, LogDraftEditor ed, int index, Map<String, dynamic> e, int pos, int count) {
    final item = ed.item(e['libraryId']);
    final cat = view.category(jsStr(item?['categoryId'] ?? _task!['categoryId']));
    final units = ed.units(e);
    final method = LogDraftEditor.method(e);
    final seasons = LogDraftEditor.seasonsOf(item);
    final selected = item == null ? null : ed.selectedSeason(e, item);
    final noun = _cap(unitLabel(cat.unit, 1));
    final collapsed = e['v369Collapsed'] == true;
    final showAll = e['v369ShowAll'] == true;
    final title = cleanTitle(e['title']);
    final first = showAll || units.length <= _shownUnits ? 0 : units.length - _shownUnits;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(10, 10, 4, 12),
      decoration: BoxDecoration(color: MF.raised, borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _entryCover(view, item, e, cat, collapsed ? 30 : 44),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
              Text(
                '${units.length} ${unitLabel(cat.unit, units.length)} · ${_hms(ed.runtimeSeconds(e))}'
                '${item != null ? ' · saved ${_num(item['progress'])}${jsTruthy(item['total']) ? '/${_num(item['total'])}' : ''}' : ''}'
                '${e['isRepeat'] == true ? ' · rewatch' : ''}',
                style: const TextStyle(color: MF.textDim, fontSize: 12),
              ),
            ]),
          ),
          _collapseButton(collapsed, () => _toggleFlag(e, 'v369Collapsed')),
          _entryMenu(view, index, pos, count, title),
        ]),
        if (!collapsed) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Wrap(spacing: 6, children: [
                  for (final m in const [('unit', 'Per Unit'), ('last', 'Progress Reached'), ('amount', 'Amount Consumed')])
                    ChoiceChip(
                      label: Text(m.$2),
                      selected: method == m.$1,
                      onSelected: (_) => _edit((x) {
                        x.setMethod(index, m.$1);
                        return null;
                      }),
                    ),
                ]),
              ),
              if (seasons.isNotEmpty) ...[
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  key: ValueKey('season-${entryKey(e)}-${jsStr(selected?['id'])}'),
                  initialValue: jsStr(selected?['id']).isEmpty ? null : jsStr(selected?['id']),
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Season'),
                  items: [
                    for (final s in seasons)
                      DropdownMenuItem(
                        value: jsStr(s['id']),
                        child: Text('${jsStr(s['name'])} · ${_num(s['progress'])}${s['total'] != null ? '/${_num(s['total'])}' : ''}',
                            overflow: TextOverflow.ellipsis),
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
                if (first > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(children: [
                      Expanded(
                        child: Text('Showing the last $_shownUnits of ${units.length}',
                            style: const TextStyle(color: MF.textDim, fontSize: 12)),
                      ),
                      TextButton(onPressed: () => _toggleFlag(e, 'v369ShowAll'), child: const Text('Show all')),
                    ]),
                  ),
                for (var p = first; p < units.length; p++) _unitRow(ed, index, p, units[p], noun),
                if (showAll && units.length > _shownUnits)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(onPressed: () => _toggleFlag(e, 'v369ShowAll'), child: Text('Show the last $_shownUnits')),
                  ),
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
          ),
        ],
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
      CommitField(
        key: ValueKey('bulk-${entryKey(e)}-$method-${jsStr(season?['id'])}'),
        value: '$value',
        label: label,
        decimal: false,
        helper: 'Saved progress: $base · draft: ${rel.units.length}',
        onCommit: (t) => _setQuantity(index, t),
      ),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerLeft,
        child: ActionChip(
          avatar: const Icon(Icons.schedule_rounded, size: 16),
          label: Text('Consumed at ${_when(stamp)}'),
          onPressed: () async {
            final when = await _askWhen(stamp);
            if (when != null && mounted) _edit((x) => x.setWhen(index, when));
          },
        ),
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

  Future<void> _setQuantity(int index, String text) async {
    final view = account.view;
    final ed = view == null ? null : _editor(view);
    if (ed == null) return;
    final n = int.tryParse(text.trim());
    if (n == null || n < 0) {
      _snack('Enter a valid whole unit number.');
      setState(() {});
      return;
    }
    if (ed.quantityReplacesDetail(index)) {
      var ok = false;
      await _confirm(
        'Replace detailed entries?',
        'Changing this number replaces the detailed unit entries (numbers, times, runtimes or rewatch flags) for this season. '
            'Only the unsaved draft changes.',
        'Replace',
        () => ok = true,
      );
      if (!ok || !mounted) {
        if (mounted) setState(() {});
        return;
      }
    }
    _edit((x) => x.setQuantity(index, n));
  }
}

/// A number field that applies its value when you leave it or press enter
/// (the website's `onchange`), not on every keystroke.
class CommitField extends StatefulWidget {
  const CommitField({super.key, required this.value, required this.onCommit, this.label, this.helper, this.decimal = true});

  final String value;
  final ValueChanged<String> onCommit;
  final String? label;
  final String? helper;
  final bool decimal;

  @override
  State<CommitField> createState() => _CommitFieldState();
}

class _CommitFieldState extends State<CommitField> {
  late final TextEditingController _c = TextEditingController(text: widget.value);
  final FocusNode _focus = FocusNode();
  String? _sent; // the last value handed to onCommit (blur and enter both fire)

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
  }

  @override
  void didUpdateWidget(CommitField old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) _sent = null;
    if (!_focus.hasFocus && _c.text != widget.value) {
      _c.text = widget.value;
      _sent = null;
    }
  }

  void _commit() {
    final t = _c.text.trim();
    if (t == widget.value || t == _sent) return;
    _sent = t;
    widget.onCommit(t);
  }

  @override
  void dispose() {
    _focus.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _c,
      focusNode: _focus,
      keyboardType: TextInputType.numberWithOptions(decimal: widget.decimal),
      inputFormatters: [FilteringTextInputFormatter.allow(widget.decimal ? RegExp(r'[0-9.,]') : RegExp(r'[0-9]'))],
      decoration: InputDecoration(labelText: widget.label, helperText: widget.helper, isDense: true),
      onSubmitted: (_) => _commit(),
      onTapOutside: (_) => _focus.unfocus(),
    );
  }
}
