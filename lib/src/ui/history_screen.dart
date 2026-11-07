// History: every log (search, filters, paging, select and delete, edit any log,
// Undo / Redo, Undo last entry), the XP History journal with CSV/JSON export, and
// Library History with restore for deleted titles — the website's History page.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../data/account_controller.dart';
import '../data/app_prefs.dart';
import '../logic/history_logic.dart';
import '../state/models.dart';
import '../util/js.dart';
import 'presence.dart';
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
const _mediaTypes = [('all', 'All media types'), ('video', 'Watching'), ('reading', 'Reading'), ('playing', 'Playing'), ('listening', 'Listening'), ('other', 'Other')];

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, required this.account});
  final AccountController account;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  AccountController get account => widget.account;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('History'),
          actions: [SyncIndicator(account: account)],
          bottom: const TabBar(tabs: [Tab(text: 'Logs'), Tab(text: 'XP History'), Tab(text: 'Library History')]),
        ),
        body: LiveBuilder(
          listenable: account,
          builder: (context, _) {
            final view = account.view;
            if (view == null) return const SizedBox.shrink();
            return TabBarView(children: [
              _LogsTab(account: account, view: view),
              _XpTab(view: view),
              _LibraryHistoryTab(account: account, view: view),
            ]);
          },
        ),
      ),
    );
  }
}

void _toast(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 3)));

// ---- Logs --------------------------------------------------------------------------

class _LogsTab extends StatefulWidget {
  const _LogsTab({required this.account, required this.view});
  final AccountController account;
  final AccountView view;

  @override
  State<_LogsTab> createState() => _LogsTabState();
}

class _LogsTabState extends State<_LogsTab> with AutomaticKeepAliveClientMixin {
  final _search = TextEditingController();
  final Set<String> _cats = {};
  final Set<String> _selected = {};
  String _media = 'all';
  bool _showSkipped = true;
  int _page = 0;

  AccountController get account => widget.account;
  AccountView get view => widget.view;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  int get _pageSize => AppPrefs.instance.get<int>('historyPageSize', 50);

  List<LogRecord> _filtered() {
    final q = _search.text.trim().toLowerCase();
    final types = {for (final c in view.categories) c.id: jsStr(c.raw['type'])};
    final byTime = memoFor(view, 'logsByTime', () => List<LogRecord>.of(view.logs)..sort((a, b) => b.timestamp.compareTo(a.timestamp)));
    final out = byTime.where((l) {
      if (l.skipped && !_showSkipped) return false;
      if (_cats.isNotEmpty && !_cats.contains(l.categoryId)) return false;
      if (_media != 'all') {
        final t = types[l.categoryId] ?? '';
        final known = const ['video', 'reading', 'playing', 'listening'].contains(t);
        if ((_media == 'other' && known) || (_media != 'other' && t != _media)) return false;
      }
      if (q.isNotEmpty) {
        final hay = '${l.titleSummary} ${l.note} ${view.category(l.categoryId).name}'.toLowerCase();
        if (!hay.contains(q)) return false;
      }
      return true;
    }).toList();
    return out;
  }

  Future<void> _delete(List<String> ids, String what) async {
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
    if (ok != true) return;
    var removed = 0;
    await account.edit((s, now) => removed = deleteSessions(s, ids.toSet(), now),
        label: 'Delete history', annotateStreaks: true);
    setState(() {
      _selected.removeAll(ids);
      _page = 0;
    });
    if (mounted) _toast(context, '$removed History ${removed == 1 ? 'entry' : 'entries'} deleted · Undo available');
  }

  Future<void> _undoLast() async {
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

  Future<void> _edit(LogRecord log) async {
    final result = await showModalBottomSheet<_SessionEdit>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: MF.surface,
      builder: (c) => PresenceScope(info: const PresenceInfo(details: 'Editing History'), child: _SessionEditor(view: view, log: log)),
    );
    if (result == null || !mounted) return;
    if (result.delete) {
      await _delete([log.id], 'this');
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
    if (mounted) _toast(context, 'History entry saved');
  }

  Future<void> _pickCategories() async {
    final chosen = {..._cats};
    final res = await showModalBottomSheet<Set<String>>(
      context: context,
      backgroundColor: MF.surface,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(c).height * 0.8),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              ListTile(
                title: const Text('Categories', style: TextStyle(fontWeight: FontWeight.w800)),
                trailing: TextButton(onPressed: () => set(chosen.clear), child: const Text('All')),
              ),
              Flexible(
                child: ListView(shrinkWrap: true, children: [
                  for (final cat in view.categories)
                    CheckboxListTile(
                      value: chosen.contains(cat.id),
                      onChanged: (v) => set(() => v == true ? chosen.add(cat.id) : chosen.remove(cat.id)),
                      secondary: CategoryBadge(cat, size: 26),
                      title: Text(cat.name),
                    ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton(
                  onPressed: () => Navigator.pop(c, chosen),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                  child: const Text('Done'),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
    if (res != null) {
      setState(() {
        _cats
          ..clear()
          ..addAll(res);
        _page = 0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final list = _filtered();
    final size = _pageSize;
    final pages = (list.length / size).ceil().clamp(1, 1 << 30).toInt();
    if (_page > pages - 1) _page = pages - 1;
    final pageItems = list.skip(_page * size).take(size).toList();
    final todayIso = isoDay(DateTime.now());
    var todayMinutes = 0.0, todayXP = 0.0;
    for (final l in view.logs) {
      if (!l.skipped && l.date == todayIso) {
        todayMinutes += l.minutes;
        todayXP += l.xp;
      }
    }
    final rows = <Object>[];
    String? day;
    for (final l in pageItems) {
      final d = l.date.isNotEmpty ? l.date : isoDay(DateTime.fromMillisecondsSinceEpoch(l.timestamp));
      if (d != day) {
        rows.add(d);
        day = d;
      }
      rows.add(l);
    }
    final header = <Widget>[
      Row(children: [
        Expanded(
          child: TextField(
            controller: _search,
            onChanged: (_) => setState(() => _page = 0),
            decoration: const InputDecoration(hintText: 'Search logs, notes, categories', prefixIcon: Icon(Icons.search_rounded)),
          ),
        ),
      ]),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        ActionChip(
          avatar: const Icon(Icons.category_outlined, size: 16),
          label: Text(_cats.isEmpty ? 'All categories' : '${_cats.length} categories'),
          onPressed: _pickCategories,
        ),
        CompactDropdown<String>(value: _media, items: _mediaTypes, onChanged: (v) => setState(() => _media = v), maxWidth: 180),
        FilterChip(label: const Text('Skipped'), selected: _showSkipped, onSelected: (v) => setState(() => _showSkipped = v)),
        CompactDropdown<int>(
          value: size,
          items: const [(25, '25 per page'), (50, '50 per page'), (100, '100 per page'), (250, '250 per page')],
          onChanged: (v) => setState(() {
            AppPrefs.instance.set('historyPageSize', v);
            _page = 0;
          }),
          maxWidth: 150,
        ),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        _Stat(label: 'Today', value: fmtMinutes(todayMinutes)),
        const SizedBox(width: 8),
        _Stat(label: 'XP today', value: '+${fmtNumber(todayXP)}'),
        const SizedBox(width: 8),
        _Stat(label: 'Shown logs', value: fmtNumber(list.length)),
      ]),
      const SizedBox(height: 6),
      Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
        OutlinedButton.icon(
          onPressed: account.undoStack.isEmpty
              ? null
              : () async {
                  final label = await account.undo();
                  if (label != null && context.mounted) _toast(context, 'Undid $label');
                },
          icon: const Icon(Icons.undo_rounded, size: 18),
          label: Text('Undo${account.undoStack.isEmpty ? '' : ' (${account.undoStack.length})'}'),
        ),
        OutlinedButton.icon(
          onPressed: account.redoStack.isEmpty
              ? null
              : () async {
                  final label = await account.redo();
                  if (label != null && context.mounted) _toast(context, 'Redid $label');
                },
          icon: const Icon(Icons.redo_rounded, size: 18),
          label: const Text('Redo'),
        ),
        if (view.logs.isNotEmpty)
          TextButton.icon(onPressed: _undoLast, icon: const Icon(Icons.replay_rounded, size: 18), label: const Text('Undo last entry')),
      ]),
      Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
        TextButton(
          onPressed: pageItems.isEmpty ? null : () => setState(() => _selected.addAll(pageItems.map((l) => l.id))),
          child: const Text('Select visible'),
        ),
        if (_selected.isNotEmpty) TextButton(onPressed: () => setState(_selected.clear), child: const Text('Deselect all')),
        if (_selected.isNotEmpty)
          FilledButton.tonalIcon(
            onPressed: () => _delete(_selected.toList(), 'selected'),
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
            label: Text('Delete selected (${_selected.length})'),
          ),
        TextButton(
          onPressed: pageItems.isEmpty ? null : () => _delete(pageItems.map((l) => l.id).toList(), 'visible'),
          child: const Text('Delete visible', style: TextStyle(color: MF.bad)),
        ),
      ]),
    ];
    return RefreshIndicator(
      onRefresh: account.sync,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
        itemCount: header.length + (rows.isEmpty ? 1 : rows.length) + 1,
        itemBuilder: (context, i) {
          if (i < header.length) return Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: header[i]);
          final k = i - header.length;
          if (rows.isEmpty && k == 0) {
            return Padding(
              padding: EdgeInsets.all(32),
              child: Text('No logs match these filters.', textAlign: TextAlign.center, style: TextStyle(color: MF.textDim)),
            );
          }
          if (k >= (rows.isEmpty ? 1 : rows.length)) {
            return pages <= 1
                ? const SizedBox.shrink()
                : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    IconButton(icon: const Icon(Icons.chevron_left_rounded), onPressed: _page == 0 ? null : () => setState(() => _page--)),
                    Text('Page ${_page + 1} of $pages'),
                    IconButton(icon: const Icon(Icons.chevron_right_rounded), onPressed: _page >= pages - 1 ? null : () => setState(() => _page++)),
                  ]);
          }
          final row = rows[k];
          if (row is String) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
              child: Text(fmtDay(row), style: TextStyle(color: MF.accent, fontWeight: FontWeight.w800, letterSpacing: 0.3)),
            );
          }
          final log = row as LogRecord;
          return _LogRow(
            log: log,
            view: view,
            selected: _selected.contains(log.id),
            onSelect: (v) => setState(() => v ? _selected.add(log.id) : _selected.remove(log.id)),
            onTap: () => _edit(log),
          );
        },
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: MF.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: MF.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          Text(label, style: TextStyle(color: MF.textDim, fontSize: 12)),
        ]),
      ),
    );
  }
}

class _LogRow extends StatelessWidget {
  const _LogRow({required this.log, required this.view, required this.selected, required this.onSelect, required this.onTap});
  final LogRecord log;
  final AccountView view;
  final bool selected;
  final ValueChanged<bool> onSelect;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final category = view.category(log.categoryId);
    final unit = log.unit.isEmpty ? category.unit : log.unit;
    final status = _statusLabels[log.status] ?? (log.status.isEmpty ? 'Logged' : log.status);
    final detail = log.skipped
        ? 'Skipped'
        : '${fmtNumber(log.amount)} ${unitLabel(unit, log.amount)} · ${fmtMinutes(log.minutes)} · +${fmtNumber(log.xp)} XP · $status';
    final repeat = log.titles.any((t) => t['repeat'] == true);
    final firstTitle = log.titles.isEmpty ? null : log.titles.first;
    final item = firstTitle == null ? null : view.library.where((t) => t.id == jsStr(firstTitle['libraryId'])).firstOrNull;
    final time = DateTime.fromMillisecondsSinceEpoch(log.timestamp);
    return Opacity(
      opacity: log.skipped ? 0.55 : 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        onLongPress: () => onSelect(!selected),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Checkbox(value: selected, onChanged: (v) => onSelect(v == true), visualDensity: VisualDensity.compact),
            if (item != null) Cover(title: item, category: category, width: 34) else CategoryBadge(category, size: 34),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(log.titleSummary.isEmpty ? category.name : log.titleSummary,
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(detail, style: TextStyle(color: MF.textDim, fontSize: 12.5)),
                Text('${category.name} · ${TimeOfDay.fromDateTime(time).format(context)}${log.source == 'batch' ? ' · Batch Log' : ''}',
                    style: TextStyle(color: MF.textDim, fontSize: 11.5)),
                if (log.note.isNotEmpty && log.note != log.titleSummary)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(log.note, maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: MF.textDim, fontSize: 12.5, fontStyle: FontStyle.italic)),
                  ),
              ]),
            ),
            if (repeat)
              Padding(
                padding: EdgeInsets.only(left: 6),
                child: Tooltip(message: 'Rewatch / reread', child: Icon(Icons.replay_rounded, size: 18, color: MF.accent)),
              ),
          ]),
        ),
      ),
    );
  }
}

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
        for (final c in changes.take(8))
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '${c['kind'] == 'added' ? '＋' : c['kind'] == 'deleted' ? '－' : '✎'} ${cleanTitle(c['title'])}'
              '${asList(c['fields']).isEmpty ? '' : ' · ${asList(c['fields']).map(jsStr).join(' · ')}'}',
              style: const TextStyle(fontSize: 12.5),
            ),
          ),
        if (changes.length > 8) Text('+${changes.length - 8} more', style: TextStyle(color: MF.textDim, fontSize: 12)),
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
