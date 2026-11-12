// History: every log (search, filters, paging, select and delete, edit any log,
// Undo / Redo, Undo last entry), the XP History journal with CSV/JSON export, and
// Library History with restore for deleted titles — the website's History page.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../data/account_controller.dart';
import '../logic/history_logic.dart';
import '../state/models.dart';
import '../util/js.dart';
import 'history_tabs.dart';
import 'home_shell.dart' show Section;
import 'presence.dart';
import 'title_screen.dart' show TitleEditor, TitleScreen;
import 'theme.dart';
import 'widgets.dart';

/// Saves an export where the user can find it. Returns the file path.
Future<String?> saveExportFile(String name, String content) async {
  try {
    Directory? dir;
    try {
      dir = await getDownloadsDirectory();
    } catch (_) {}
    dir ??= await getApplicationDocumentsDirectory();
    final f = File('${dir.path}${Platform.pathSeparator}$name');
    await f.writeAsString(content, flush: true);
    return f.path;
  } catch (_) {
    return null;
  }
}

const _statusLabels = {'complete': 'Complete', 'partial': 'Partial', 'over': 'Over', 'skipped': 'Skipped', 'logged': 'Logged'};

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, required this.account});
  final AccountController account;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> with SingleTickerProviderStateMixin {
  AccountController get account => widget.account;
  late final TabController _tabs = TabController(length: _tabNames.length, vsync: this)..addListener(_onTab);

  // v565: the website's order (v260 + v348); Consumption history opens first.
  // The old Logs tab's Undo / Redo / Undo last entry are in the History bar.
  static const _tabNames = ['Consumption history', 'Recently viewed', 'Ratings', 'Library History', 'XP History'];

  /// Each tab's Discord status.
  static const _tabPresence = <int, PresenceInfo>{
    0: PresenceInfo(situation: 'consumption', values: {'action': 'Looking back at consumption history'}),
    1: PresenceInfo(situation: 'recent', values: {'action': 'Browsing recently viewed titles'}),
    2: PresenceInfo(situation: 'ratings', values: {'action': 'Looking through ratings'}),
    3: PresenceInfo(situation: 'history', values: {'action': 'Reviewing Library History'}),
    4: PresenceInfo(situation: 'history', values: {'action': 'Reading XP History'}),
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) PresenceHub.instance.section(Section.history, _tabPresence[0]);
    });
  }

  Future<void> _undoLast(AccountView view) async {
    final logs = view.logs;
    if (logs.isEmpty) return;
    final latest = logs.reduce((a, b) => a.timestamp > b.timestamp ? a : b);
    final cat = view.category(latest.categoryId);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Undo last entry?'),
        content: Text('Undo your last logged entry (${cat.name}, ${fmtNumber(latest.amount)} ${latest.unit})? '
            'It will be removed from history and given back to you as the next task.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Undo entry')),
        ],
      ),
    );
    if (ok != true) return;
    await account.edit((s, now) => undoLastEntry(s, now), label: 'Undo last entry', annotateStreaks: true);
  }

  void _onTab() {
    if (_tabs.indexIsChanging) return;
    PresenceHub.instance.section(Section.history, _tabPresence[_tabs.index]);
  }

  @override
  void dispose() {
    PresenceHub.instance.section(Section.history, null);
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        actions: [
          ListenableBuilder(
            listenable: account,
            builder: (context, _) => Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                tooltip: account.undoStack.isEmpty ? 'Nothing to undo' : 'Undo (${account.undoStack.length})',
                icon: const Icon(Icons.undo_rounded),
                onPressed: account.undoStack.isEmpty
                    ? null
                    : () async {
                        final label = await account.undo();
                        if (label != null && context.mounted) _toast(context, 'Undid $label');
                      },
              ),
              IconButton(
                tooltip: 'Redo',
                icon: const Icon(Icons.redo_rounded),
                onPressed: account.redoStack.isEmpty
                    ? null
                    : () async {
                        final label = await account.redo();
                        if (label != null && context.mounted) _toast(context, 'Redid $label');
                      },
              ),
              if (account.view?.logs.isNotEmpty == true)
                IconButton(tooltip: 'Undo last entry', icon: const Icon(Icons.replay_rounded), onPressed: () => _undoLast(account.view!)),
            ]),
          ),
          SyncIndicator(account: account),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [for (final t in _tabNames) Tab(text: t)],
        ),
      ),
      body: LiveBuilder(
        listenable: account,
        builder: (context, _) {
          final view = account.view;
          if (view == null) return const SizedBox.shrink();
          return TabBarView(controller: _tabs, children: [
            ConsumptionHistoryTab(
              account: account,
              view: view,
              onEdit: (log) => editHistoryEntry(context, account, view, log),
              onDelete: (ids, what) => deleteHistoryEntries(context, account, ids, what),
              saveExport: saveExportFile,
            ),
            RecentlyViewedTab(account: account, view: view),
            RatingsHistoryTab(account: account, view: view),
            _LibraryHistoryTab(account: account, view: view),
            _XpTab(view: view),
          ]);
        },
      ),
    );
  }
}

void _toast(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 3)));


/// Deletes History entries after asking (Logs and Consumption history).
/// Returns how many were removed, or null when cancelled.
Future<int?> deleteHistoryEntries(BuildContext context, AccountController account, List<String> ids, String what) async {
  final n = ids.length;
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text('Delete $what History ${n == 1 ? 'entry' : 'entries'}?'),
      content: Text('You are about to permanently remove $n ${n == 1 ? 'History entry' : 'History entries'}. '
          'MediaFlow will recalculate History-based statistics and scheduling from what remains. The deletion is one undoable change.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        FilledButton(style: FilledButton.styleFrom(backgroundColor: MF.bad), onPressed: () => Navigator.pop(c, true), child: Text('Delete $n')),
      ],
    ),
  );
  if (ok != true) return null;
  var removed = 0;
  await account.edit((s, now) => removed = deleteSessions(s, ids.toSet(), now), label: 'Delete history', annotateStreaks: true);
  if (context.mounted) _toast(context, '$removed History ${removed == 1 ? 'entry' : 'entries'} deleted · Undo available');
  return removed;
}

/// Opens the History entry editor (Logs and Consumption history).
Future<void> editHistoryEntry(BuildContext context, AccountController account, AccountView view, LogRecord log) async {
  final result = await showModalBottomSheet<_SessionEdit>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: MF.surface,
    builder: (c) => PresenceScope(info: const PresenceInfo(situation: 'history'), child: _SessionEditor(view: view, log: log)),
  );
  if (result == null || !context.mounted) return;
  if (result.delete) {
    await deleteHistoryEntries(context, account, [log.id], 'this');
    return;
  }
  await account.edit(
    (s, now) => editSession(s, log.id, now,
        categoryId: result.categoryId,
        date: result.date,
        status: result.status,
        targetAmount: result.target,
        actualAmount: result.actual,
        minutes: result.minutes,
        note: result.note),
    label: 'Edit history',
    annotateStreaks: true,
  );
  if (context.mounted) _toast(context, 'History entry saved');
}

// ---- Logs --------------------------------------------------------------------------

class _SessionEdit {
  _SessionEdit({this.delete = false, this.categoryId = '', this.date = '', this.status = '', this.target = 0, this.actual = 0, this.minutes = 0, this.note = ''});
  final bool delete;
  final String categoryId, date, status, note;
  final double target, actual, minutes;
}

class _SessionEditor extends StatefulWidget {
  const _SessionEditor({required this.view, required this.log});
  final AccountView view;
  final LogRecord log;

  @override
  State<_SessionEditor> createState() => _SessionEditorState();
}

class _SessionEditorState extends State<_SessionEditor> {
  late String _cat = widget.log.categoryId;
  late String _status = _statusLabels.containsKey(widget.log.status) ? widget.log.status : 'complete';
  late final _date = TextEditingController(text: widget.log.date);
  late final _target = TextEditingController(text: _plain(widget.log.raw['targetAmount']));
  late final _actual = TextEditingController(text: _plain(widget.log.raw['actualAmount']));
  late final _minutes = TextEditingController(text: _plain(widget.log.raw['minutes']));
  late final _note = TextEditingController(text: widget.log.note);

  static String _plain(Object? v) {
    final n = jsNum(v);
    return n == n.truncateToDouble() ? n.toInt().toString() : n.toString();
  }

  @override
  void dispose() {
    for (final c in [_date, _target, _actual, _minutes, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  double _n(TextEditingController c) => double.tryParse(c.text.trim().replaceAll(',', '.')) ?? 0;

  Widget _num(TextEditingController c, String label) => Expanded(
        child: TextField(
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
          decoration: InputDecoration(labelText: label),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final view = widget.view;
    final cats = view.categories;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Edit History entry', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
          if (widget.log.titleSummary.isNotEmpty)
            Text(widget.log.titleSummary, style: TextStyle(color: MF.textDim)),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            initialValue: cats.any((c) => c.id == _cat) ? _cat : (cats.isEmpty ? null : cats.first.id),
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Category'),
            items: [for (final c in cats) DropdownMenuItem(value: c.id, child: Text(c.name))],
            onChanged: (v) => setState(() => _cat = v ?? _cat),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _date,
                readOnly: true,
                decoration: const InputDecoration(labelText: 'Date', suffixIcon: Icon(Icons.event_rounded)),
                onTap: () async {
                  final initial = DateTime.tryParse(_date.text) ?? DateTime.now();
                  final d = await showDatePicker(context: context, initialDate: initial, firstDate: DateTime(2000), lastDate: DateTime(2100));
                  if (d != null) setState(() => _date.text = isoDay(d));
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _status,
                decoration: const InputDecoration(labelText: 'Status'),
                items: [for (final e in _statusLabels.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                onChanged: (v) => setState(() => _status = v ?? _status),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          Row(children: [_num(_target, 'Target'), const SizedBox(width: 10), _num(_actual, 'Actual'), const SizedBox(width: 10), _num(_minutes, 'Minutes')]),
          const SizedBox(height: 10),
          TextField(controller: _note, maxLines: 3, minLines: 1, decoration: const InputDecoration(labelText: 'Note')),
          const SizedBox(height: 8),
          Text('XP is recalculated from the amount, minutes and the category’s current balance, like on the website.',
              style: TextStyle(color: MF.textDim, fontSize: 12)),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              _SessionEdit(
                categoryId: _cat,
                date: _date.text,
                status: _status,
                target: _n(_target),
                actual: _n(_actual),
                minutes: _n(_minutes),
                note: _note.text,
              ),
            ),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            child: const Text('Save'),
          ),
          const SizedBox(height: 6),
          TextButton(
            onPressed: () => Navigator.pop(context, _SessionEdit(delete: true)),
            child: const Text('Delete entry', style: TextStyle(color: MF.bad)),
          ),
        ]),
      ),
    );
  }
}

// ---- XP History -------------------------------------------------------------------------

class _XpTab extends StatefulWidget {
  const _XpTab({required this.view});
  final AccountView view;

  @override
  State<_XpTab> createState() => _XpTabState();
}

class _XpTabState extends State<_XpTab> with AutomaticKeepAliveClientMixin {
  final _search = TextEditingController();
  String _source = 'all';
  int _page = 0, _size = 25;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _export(List<XpEntry> rows, String format) async {
    final stamp = isoDay(DateTime.now());
    final name = 'MediaFlow_v348_XP_History_$stamp.$format';
    final content = format == 'json'
        ? const JsonEncoder.withIndent('  ').convert({
            'type': 'mediaflow-xp-history',
            'exportedAt': DateTime.now().toUtc().toIso8601String(),
            'rows': [
              for (final x in rows)
                {
                  'id': x.id,
                  'source': x.source,
                  'kind': x.kind,
                  'title': x.title,
                  'timestamp': x.timestamp,
                  'baseXP': x.baseXP,
                  'multiplier': x.multiplier,
                  'streak': x.streak,
                  'xp': x.xp,
                  'details': x.details,
                  'legacy': x.legacy,
                },
            ],
          })
        : xpHistoryCsv(rows);
    final path = await saveExportFile(name, content);
    if (mounted) _toast(context, path == null ? 'Could not save the export.' : 'Saved to $path');
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final all = memoFor(widget.view, 'xpHistory', () => xpHistory(widget.view.state));
    final q = _search.text.trim().toLowerCase();
    final rows = all
        .where((x) => (_source == 'all' || x.kind == _source) && (q.isEmpty || '${x.source} ${x.title} ${x.details} ${x.kind}'.toLowerCase().contains(q)))
        .toList();
    final pages = (rows.length / _size).ceil().clamp(1, 1 << 30).toInt();
    if (_page > pages - 1) _page = pages - 1;
    final slice = rows.skip(_page * _size).take(_size).toList();
    final sum = rows.fold<double>(0, (a, r) => a + r.xp);
    final dated = rows.where((r) => r.timestamp > 0).length;
    final sources = all.map((r) => r.kind).toSet().toList()..sort();
    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 96), children: [
      Text('PROGRESSION JOURNAL', style: TextStyle(color: MF.accent, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 0.8)),
      const Text('XP History', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
      Text('Every available award, source and streak multiplier—built from your saved XP records.', style: TextStyle(color: MF.textDim)),
      const SizedBox(height: 10),
      Wrap(spacing: 8, runSpacing: 8, children: [
        _chipStat('Recorded award entries', fmtNumber(rows.length)),
        _chipStat('XP represented', '${fmtNumber(sum.round())} XP'),
        _chipStat('Dated entries', fmtNumber(dated)),
      ]),
      const SizedBox(height: 10),
      TextField(
        controller: _search,
        onChanged: (_) => setState(() => _page = 0),
        decoration: const InputDecoration(hintText: 'Search source, title, reward…', prefixIcon: Icon(Icons.search_rounded)),
      ),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        CompactDropdown<String>(
          value: _source,
          items: [('all', 'All sources'), for (final s in sources) (s, kXpSourceLabels[s] ?? (s == 'consumption' ? 'Consumption' : s == 'activeTime' ? 'Active app time' : s))],
          onChanged: (v) => setState(() {
            _source = v;
            _page = 0;
          }),
          maxWidth: 220,
        ),
        CompactDropdown<int>(
          value: _size,
          items: const [(25, '25 per page'), (50, '50 per page'), (100, '100 per page')],
          onChanged: (v) => setState(() {
            _size = v;
            _page = 0;
          }),
          maxWidth: 150,
        ),
        OutlinedButton.icon(onPressed: () => _export(rows, 'csv'), icon: const Icon(Icons.download_rounded, size: 18), label: const Text('CSV')),
        OutlinedButton.icon(onPressed: () => _export(rows, 'json'), icon: const Icon(Icons.data_object_rounded, size: 18), label: const Text('JSON')),
      ]),
      const SizedBox(height: 8),
      if (slice.isEmpty)
        Padding(padding: EdgeInsets.all(24), child: Text('No XP entries match these filters.', textAlign: TextAlign.center, style: TextStyle(color: MF.textDim))),
      for (final row in slice)
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: MF.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: MF.border)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('✦', style: TextStyle(color: MF.accent, fontSize: 16)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(row.source, style: const TextStyle(fontWeight: FontWeight.w800)),
                Text(row.timestamp > 0 ? _when(row.timestamp) : 'Earlier award · timestamp unavailable', style: TextStyle(color: MF.textDim, fontSize: 12)),
                if (row.title.isNotEmpty) Text(cleanTitle(row.title), maxLines: 2, overflow: TextOverflow.ellipsis),
                if (row.details.isNotEmpty) Text(row.details, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: MF.textDim, fontSize: 12)),
                Text(
                  '${row.baseXP != null ? '${fmtNumber(row.baseXP!.round())} base XP' : 'Base XP unavailable'} · '
                  '${row.multiplier != null ? '×${row.multiplier!.toStringAsFixed(2)}' : 'Not recorded'}',
                  style: TextStyle(color: MF.textDim, fontSize: 12),
                ),
              ]),
            ),
            Text('+${fmtNumber(row.xp.round())} XP', style: TextStyle(fontWeight: FontWeight.w900, color: MF.accent)),
          ]),
        ),
      if (pages > 1)
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          IconButton(icon: const Icon(Icons.chevron_left_rounded), onPressed: _page == 0 ? null : () => setState(() => _page--)),
          Text('Page ${_page + 1} of $pages'),
          IconButton(icon: const Icon(Icons.chevron_right_rounded), onPressed: _page >= pages - 1 ? null : () => setState(() => _page++)),
        ]),
      const SizedBox(height: 8),
      Text('Older XP ledgers did not record every award’s timestamp or multiplier, and Library-count XP is calculated from the current Library '
          'rather than individual dated awards. Missing history details are not fabricated.',
          style: TextStyle(color: MF.textDim, fontSize: 12)),
    ]);
  }

  Widget _chipStat(String label, String value) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: MF.raised, borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, style: const TextStyle(fontWeight: FontWeight.w900)),
          Text(label, style: TextStyle(color: MF.textDim, fontSize: 11)),
        ]),
      );
}

String _when(double ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms.toInt());
  final hh = d.hour.toString().padLeft(2, '0'), mm = d.minute.toString().padLeft(2, '0');
  return '${fmtDay(isoDay(d))} · $hh:$mm';
}

// ---- Library History --------------------------------------------------------------------

class _LibraryHistoryTab extends StatefulWidget {
  const _LibraryHistoryTab({required this.account, required this.view});
  final AccountController account;
  final AccountView view;

  @override
  State<_LibraryHistoryTab> createState() => _LibraryHistoryTabState();
}

class _LibraryHistoryTabState extends State<_LibraryHistoryTab> with AutomaticKeepAliveClientMixin {
  int _page = 0;
  final _search = TextEditingController();

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _restore(String activityId, {String? itemId}) async {
    var restored = <String>[];
    await widget.account.edit((s, now) => restored = restoreDeleted(s, activityId, now, itemId: itemId),
        label: itemId == null ? 'Restore deleted titles' : 'Restore title');
    if (!mounted) return;
    _toast(context, restored.isEmpty
        ? 'That title is already restored.'
        : restored.length == 1
            ? 'Restored ${restored.first} ✓'
            : '${restored.length} titles restored ✓');
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final view = widget.view;
    final q = _search.text.trim().toLowerCase();
    final entries = asList(view.state['activityLog']).map(asMap).whereType<Map<String, dynamic>>().where((e) {
      if (q.isEmpty) return true;
      return '${e['action']} ${e['detail']} ${e['titleSnapshot']} ${asList(e['changes']).map((c) => asMap(c)?['title']).join(' ')}'.toLowerCase().contains(q);
    }).toList();
    const size = 50;
    final pages = (entries.length / size).ceil().clamp(1, 1 << 30).toInt();
    if (_page > pages - 1) _page = pages - 1;
    final slice = entries.skip(_page * size).take(size).toList();
    final libraryIds = view.library.map((t) => t.id).toSet();
    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 96), children: [
      Text('LIBRARY CHANGE LOG', style: TextStyle(color: MF.textDim, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
      const SizedBox(height: 8),
      TextField(
        controller: _search,
        onChanged: (_) => setState(() => _page = 0),
        decoration: const InputDecoration(hintText: 'Search Library History', prefixIcon: Icon(Icons.search_rounded)),
      ),
      const SizedBox(height: 8),
      if (slice.isEmpty)
        Padding(padding: EdgeInsets.all(24), child: Text('No library activity recorded yet.', textAlign: TextAlign.center, style: TextStyle(color: MF.textDim))),
      for (final e in slice) _entry(e, libraryIds),
      if (pages > 1)
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          IconButton(icon: const Icon(Icons.chevron_left_rounded), onPressed: _page == 0 ? null : () => setState(() => _page--)),
          Text('Page ${_page + 1} of $pages'),
          IconButton(icon: const Icon(Icons.chevron_right_rounded), onPressed: _page >= pages - 1 ? null : () => setState(() => _page++)),
        ]),
    ]);
  }

  /// A changed title: open it (or offer Restore when it was deleted).
  void _openChange(Map<String, dynamic> c, Map<String, dynamic> e, Set<String> libraryIds) {
    final id = jsStr(c['id']);
    if (libraryIds.contains(id)) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => TitleScreen(account: widget.account, id: id)));
    } else if (asList(e['deletedItems']).any((i) => jsStr(asMap(i)?['id']) == id)) {
      _restore(jsStr(e['id']), itemId: id);
    } else {
      _toast(context, 'That title is no longer in your Library.');
    }
  }

  /// "More · N titles": every title the change touched, with cover, full
  /// title, what changed, Edit or Restore, and a search (website v562).
  Future<void> _showMore(Map<String, dynamic> e, List<Map<String, dynamic>> changes, Set<String> libraryIds) {
    final query = TextEditingController();
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: MF.surface,
      builder: (sheet) => PresenceScope(
        info: const PresenceInfo(situation: 'history', values: {'action': 'Reviewing Library History'}),
        child: StatefulBuilder(builder: (sheet, set) {
          final view = widget.account.view ?? widget.view;
          final byId = {for (final t in view.library) t.id: t};
          final deleted = {for (final i in asList(e['deletedItems']).map(asMap).whereType<Map<String, dynamic>>()) jsStr(i['id']): i};
          final q = query.text.trim().toLowerCase();
          final rows = [for (final c in changes) if (q.isEmpty || cleanTitle(c['title']).toLowerCase().contains(q)) c];
          return SizedBox(
            height: MediaQuery.sizeOf(sheet).height * .85,
            child: Column(children: [
              ListTile(
                title: Text(jsStr(e['action']).isEmpty ? 'Changed titles' : jsStr(e['action']), style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text('${changes.length} titles${jsNum(e['timestamp']) > 0 ? ' · ${_when(jsNum(e['timestamp']))}' : ''}'),
                trailing: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(sheet)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: query,
                  decoration: const InputDecoration(hintText: 'Search these titles', prefixIcon: Icon(Icons.search_rounded), isDense: true),
                  onChanged: (_) => set(() {}),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: rows.length,
                  itemBuilder: (_, i) {
                    final c = rows[i];
                    final id = jsStr(c['id']);
                    final t = byId[id];
                    final snap = deleted[id];
                    final cat = view.category(jsStr(t?.raw['categoryId'] ?? snap?['categoryId'] ?? c['categoryId']));
                    final kind = c['kind'] == 'added' ? 'Added' : c['kind'] == 'deleted' ? 'Deleted' : 'Edited';
                    final fields = asList(c['fields']).map(jsStr).where((x) => x.isNotEmpty).join(' · ');
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        t != null
                            ? Cover(title: t, category: cat, width: 44)
                            : Cover(title: LibraryTitle(snap ?? {'title': c['title'], 'categoryId': cat.id}), category: cat, width: 44),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(cleanTitle(c['title']), style: const TextStyle(fontWeight: FontWeight.w800)),
                            Text('$kind · ${cat.name}${fields.isEmpty ? '' : ' · $fields'}', style: TextStyle(color: MF.textDim, fontSize: 12)),
                          ]),
                        ),
                        if (t != null)
                          TextButton(
                            onPressed: () => Navigator.of(sheet).push(MaterialPageRoute(builder: (_) => TitleEditor(account: widget.account, id: id))),
                            child: const Text('Edit'),
                          )
                        else if (snap != null)
                          TextButton(
                            onPressed: () async {
                              await _restore(jsStr(e['id']), itemId: id);
                              set(() {});
                            },
                            child: const Text('Restore'),
                          )
                        else
                          Padding(padding: const EdgeInsets.only(top: 12), child: Text('Not in Library', style: TextStyle(color: MF.textDim, fontSize: 11))),
                      ]),
                    );
                  },
                ),
              ),
            ]),
          );
        }),
      ),
    ).whenComplete(query.dispose);
  }

  Widget _entry(Map<String, dynamic> e, Set<String> libraryIds) {
    final changes = asList(e['changes']).map(asMap).whereType<Map<String, dynamic>>().toList();
    final deleted = asList(e['deletedItems']).map(asMap).whereType<Map<String, dynamic>>().toList();
    final restorable = deleted.where((i) => !libraryIds.contains(jsStr(i['id']))).toList();
    final xp = jsNum(e['xpEarned']);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: MF.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: MF.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(jsStr(e['action']).isEmpty ? 'Change' : jsStr(e['action']), style: const TextStyle(fontWeight: FontWeight.w800))),
          if (xp > 0) Text('+${fmtNumber(xp)} XP', style: TextStyle(color: MF.accent, fontWeight: FontWeight.w800)),
        ]),
        Text(jsNum(e['timestamp']) > 0 ? _when(jsNum(e['timestamp'])) : '', style: TextStyle(color: MF.textDim, fontSize: 12)),
        if (jsStr(e['detail']).isNotEmpty) Text(jsStr(e['detail']), style: TextStyle(color: MF.textDim, fontSize: 13)),
        if (changes.isNotEmpty) ...[
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final c in changes.take(3))
              ActionChip(
                avatar: Text(c['kind'] == 'added' ? '＋' : c['kind'] == 'deleted' ? '－' : '✎'),
                label: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 220),
                  child: Text(cleanTitle(c['title']), overflow: TextOverflow.ellipsis),
                ),
                onPressed: () => _openChange(c, e, libraryIds),
              ),
            if (changes.length > 1)
              ActionChip(
                avatar: const Icon(Icons.unfold_more_rounded, size: 16),
                label: Text('More · ${changes.length} titles'),
                onPressed: () => _showMore(e, changes, libraryIds),
              ),
          ]),
        ],
        if (restorable.isNotEmpty) ...[
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 4, children: [
            if (restorable.length > 1)
              FilledButton.tonalIcon(
                onPressed: () => _restore(jsStr(e['id'])),
                icon: const Icon(Icons.restore_rounded, size: 18),
                label: Text('Restore all (${restorable.length})'),
              ),
            for (final i in restorable.take(12))
              OutlinedButton.icon(
                onPressed: () => _restore(jsStr(e['id']), itemId: jsStr(i['id'])),
                icon: const Icon(Icons.restore_rounded, size: 16),
                label: Text('Restore ${cleanTitle(i['title'])}', maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
          ]),
        ],
      ]),
    );
  }
}
