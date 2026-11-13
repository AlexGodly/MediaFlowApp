import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/account_controller.dart';
import '../logic/log_engine.dart';
import '../state/models.dart';
import '../util/js.dart';
import 'presence.dart';
import 'theme.dart';
import 'widgets.dart';
import '../logic/title_units.dart';
import '../logic/title_names.dart' show nameMatches;

Future<void> _openSheet(BuildContext context, Widget child) {
  final wide = MediaQuery.sizeOf(context).width >= 700;
  if (wide) {
    return showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: MF.surface,
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 560, maxHeight: 760), child: child),
      ),
    );
  }
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: MF.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (_) => PresenceScope(
      info: const PresenceInfo(situation: 'batch'),
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: child,
      ),
    ),
  );
}

/// Title details with a Log button.
Future<void> showTitleSheet(BuildContext context, AccountController account, String libraryId) =>
    _openSheet(context, _TitleSheet(account: account, libraryId: libraryId));

/// The log form; pick a title first when [libraryId] is null.
Future<void> showLogSheet(BuildContext context, AccountController account, {String? libraryId}) =>
    _openSheet(context, LogForm(account: account, libraryId: libraryId));

class _TitleSheet extends StatelessWidget {
  const _TitleSheet({required this.account, required this.libraryId});
  final AccountController account;
  final String libraryId;

  @override
  Widget build(BuildContext context) {
    return LiveBuilder(
      listenable: account,
      builder: (context, _) {
        final view = account.view;
        final title = view?.library.where((t) => t.id == libraryId).firstOrNull;
        if (view == null || title == null) {
          return const SizedBox(height: 200, child: EmptyState(icon: Icons.search_off, title: 'Title not found'));
        }
        final cat = view.category(title.categoryId);
        final logs = view.logs
            .where((l) => l.titles.any((t) => t['libraryId'] == title.id))
            .toList()
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
        final seasons = title.seasons.map((s) => s is Map ? s : null).whereType<Map>().toList();
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Cover(title: title, category: cat, width: 84),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Row(children: [
                    CategoryBadge(cat, size: 22),
                    const SizedBox(width: 6),
                    Flexible(child: Text(cat.name, style: TextStyle(color: MF.textDim))),
                  ]),
                  const SizedBox(height: 8),
                  Text(statusLabel(title.status),
                      style: TextStyle(color: statusColor(title.status), fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(progressText(title, cat), style: TextStyle(color: MF.text)),
                  if (title.rating != null && title.rating! > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('Rated ${fmtNumber(title.rating!)}', style: TextStyle(color: MF.textDim)),
                    ),
                ]),
              ),
            ]),
            if (seasons.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text('Seasons', style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              for (final s in seasons)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    '${jsStr(s['name']).isEmpty ? 'Season' : jsStr(s['name'])} · ${fmtNumber(jsNum(s['progress']))}'
                    '${jsNum(s['total']) > 0 ? ' / ${fmtNumber(jsNum(s['total']))}' : ''}',
                    style: TextStyle(color: MF.textDim),
                  ),
                ),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              icon: const Icon(Icons.add_rounded),
              label: Text(title.isCompleted ? 'Log a rewatch / reread' : 'Log progress',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              onPressed: () {
                // Use the navigator's own context: this sheet's context goes away on pop.
                final navigator = Navigator.of(context);
                navigator.pop();
                showLogSheet(navigator.context, account, libraryId: title.id);
              },
            ),
            const SizedBox(height: 20),
            Text(logs.isEmpty ? 'No logs yet' : 'Recent logs',
                style: const TextStyle(fontWeight: FontWeight.w800)),
            for (final l in logs.take(8))
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '${fmtDay(l.date)} · ${fmtNumber(l.amount)} ${unitLabel(l.unit.isEmpty ? cat.unit : l.unit, l.amount)}'
                  ' · ${fmtMinutes(l.minutes)} · +${fmtNumber(l.xp)} XP',
                  style: TextStyle(color: MF.textDim),
                ),
              ),
          ]),
        );
      },
    );
  }
}

class LogForm extends StatefulWidget {
  const LogForm({super.key, required this.account, this.libraryId});
  final AccountController account;
  final String? libraryId;

  @override
  State<LogForm> createState() => _LogFormState();
}

class _LogFormState extends State<LogForm> {
  String? _libraryId;
  bool _reachedMode = true;
  final _reached = TextEditingController();
  final _amount = TextEditingController(text: '1');
  final _minutes = TextEditingController();
  final _note = TextEditingController();
  final _search = TextEditingController();
  bool _minutesEdited = false;
  DateTime? _date; // null = today
  TimeOfDay? _time; // null = now today, midday on other days (website v573)
  bool _saving = false;
  String? _error;
  // 8.2.0: several titles in one log (website Batch Log rows). Each added
  // title waits here; the one being filled in is the form below.
  final List<({LogEntry entry, String id, String text})> _batch = [];
  // XP preview (website v574): worked out on a copy of the account.
  Timer? _xpTimer;
  int _xpGen = 0;
  String _xpKey = '';
  double? _xp;
  String? _xpProblem;
  bool _xpWorking = false;

  @override
  void initState() {
    super.initState();
    _libraryId = widget.libraryId;
    if (_libraryId != null) _selectDefaults();
  }

  @override
  void dispose() {
    for (final c in [_reached, _amount, _minutes, _note, _search]) {
      c.dispose();
    }
    _xpTimer?.cancel();
    super.dispose();
  }

  LibraryTitle? get _title =>
      widget.account.view?.library.where((t) => t.id == _libraryId).firstOrNull;

  void _selectDefaults() {
    final t = _title;
    if (t == null) return;
    // Same default as the website: one unit past where you are.
    var next = t.logStart + 1;
    final total = t.total;
    if (total != null && next > total) next = total;
    _reached.text = fmtPlain(next);
    _amount.text = '1';
    _minutesEdited = false;
    _syncMinutes();
  }

  String fmtPlain(double v) => v == v.roundToDouble() ? v.round().toString() : v.toString();

  double? _parse(TextEditingController c) {
    final t = c.text.trim().replaceAll(',', '.');
    if (t.isEmpty) return null;
    return double.tryParse(t);
  }

  LogEntry? _entry() {
    final id = _libraryId;
    if (id == null) return null;
    final minutes = _parse(_minutes);
    return _reachedMode
        ? LogEntry(libraryId: id, reached: _parse(_reached) ?? 0, minutes: minutes)
        : LogEntry(libraryId: id, amount: _parse(_amount) ?? 0, minutes: minutes);
  }

  ({double qty, double minutes, double start, double end})? _preview() {
    final t = _title;
    final view = widget.account.view;
    final e = _entry();
    if (t == null || view == null || e == null) return null;
    final cat = view.category(t.categoryId);
    final entryForPreview = _minutesEdited ? e : LogEntry(libraryId: e.libraryId, reached: e.reached, amount: e.amount);
    return previewEntry(t, cat, entryForPreview);
  }

  void _syncMinutes() {
    if (_minutesEdited) return;
    final p = _preview();
    if (p != null) _minutes.text = fmtPlain(p.minutes);
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      firstDate: DateTime(2000),
      lastDate: now,
    );
    if (picked != null) {
      setState(() => _date = DateUtils.isSameDay(picked, now) ? null : picked);
    }
  }

  /// Recomputes the XP preview a moment after the form stops changing.
  void _scheduleXp() {
    final view = widget.account.view;
    final entries = _allEntries();
    if (view == null || entries.isEmpty) {
      if (_xp != null || _xpKey.isNotEmpty) {
        _xpKey = '';
        _xp = null;
      }
      return;
    }
    final date = _date == null ? null : isoDay(_date!);
    final key = '${identityHashCode(view.state)}|${[for (final x in entries) x.toJson()]}|$date|$_timeText';
    if (key == _xpKey) return;
    _xpKey = key;
    _xpWorking = true;
    _xpTimer?.cancel();
    final gen = ++_xpGen;
    _xpTimer = Timer(const Duration(milliseconds: 350), () async {
      double? xp;
      String? problem;
      try {
        xp = await widget.account.previewLog(entries, date: date, time: _timeText);
        if (xp == null) problem = 'XP preview unavailable for this log';
      } catch (e) {
        problem = 'XP preview unavailable';
        debugPrint('MediaFlow: Log a title XP preview failed: $e');
      }
      if (!mounted || gen != _xpGen) return;
      setState(() {
        _xp = xp;
        _xpProblem = problem;
        _xpWorking = false;
      });
    });
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time ?? TimeOfDay.now());
    if (picked != null) setState(() => _time = picked);
  }

  String? get _timeText =>
      _time == null ? null : '${_time!.hour.toString().padLeft(2, '0')}:${_time!.minute.toString().padLeft(2, '0')}';

  /// The title being filled in, ready to log (null when it isn't complete).
  LogEntry? _currentEntry() {
    final e = _entry();
    final p = _preview();
    if (e == null || p == null || !(p.qty > 0)) return null;
    return _minutesEdited ? e : LogEntry(libraryId: e.libraryId, reached: e.reached, amount: e.amount, minutes: p.minutes);
  }

  /// Everything this log saves: the added titles, then the one being filled in.
  List<LogEntry> _allEntries() => [
        for (final b in _batch) if (b.id != _libraryId) b.entry,
        if (_currentEntry() case final e?) e,
      ];

  /// "Add another title": keeps this title in the log and opens the picker.
  void _addAnother() {
    final e = _currentEntry();
    final p = _preview();
    final t = _title;
    if (e == null || p == null || t == null) {
      setState(() => _error = 'Fill in this title first.');
      return;
    }
    final cat = widget.account.view!.category(t.categoryId);
    final text = '+${fmtNumber(p.qty)} ${unitLabel(titleUnit(t.raw, cat.raw), p.qty)} · ${fmtMinutes(p.minutes)}';
    setState(() {
      _batch.removeWhere((b) => b.id == t.id);
      _batch.add((entry: e, id: t.id, text: '${t.title} · $text'));
      _libraryId = null;
      _search.clear();
      _minutes.clear();
      _minutesEdited = false;
      _error = null;
      _xpKey = '';
    });
  }

  Future<void> _save() async {
    final p = _preview();
    if (_batch.isEmpty && _currentEntry() == null) {
      if (p != null) {
        setState(() => _error = _reachedMode ? 'Enter a number higher than ${fmtNumber(p.start)}.' : 'Enter an amount above 0.');
      }
      return;
    }
    // With other titles added, an open title left unfinished simply isn't included.
    final entries = _allEntries();
    if (entries.isEmpty) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final outcome = await widget.account.log(
        entries,
        note: _note.text,
        date: _date == null ? null : isoDay(_date!),
        time: _timeText,
      );
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      final cat = widget.account.view!.category(_title?.categoryId ?? '');
      final done = outcome.completed.isNotEmpty ? ' · Completed!' : '';
      messenger.showSnackBar(SnackBar(
        content: Text((entries.length == 1 && p != null
                ? 'Logged ${fmtNumber(p.qty)} ${unitLabel(titleUnit(_title?.raw, cat.raw), p.qty)} of ${outcome.titles.join(', ')}'
                : 'Logged ${entries.length} title${entries.length == 1 ? '' : 's'}: ${outcome.titles.join(', ')}') +
            ' · +${fmtNumber(outcome.xp)} XP$done'),
      ));
    } catch (err) {
      setState(() => _error = err.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final view = widget.account.view;
    if (view == null) return const SizedBox(height: 200, child: Center(child: CircularProgressIndicator()));
    final title = _title;
    if (title == null) return _picker(view);
    final cat = view.category(title.categoryId);
    final p = _preview();
    _scheduleXp();
    final unit = titleUnit(title.raw, cat.raw); // v565: the title's own unit
    final rewatch = title.isCompleted;
    final count = _allEntries().length;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (_batch.isNotEmpty) _batchCard(),
        Row(children: [
          Cover(title: title, category: cat, width: 52),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text('${cat.name} · ${progressText(title, cat)}', style: TextStyle(color: MF.textDim, fontSize: 13)),
            ]),
          ),
          if (widget.libraryId == null)
            IconButton(
              tooltip: 'Choose another title',
              icon: const Icon(Icons.swap_horiz_rounded),
              onPressed: () => setState(() => _libraryId = null),
            ),
        ]),
        if (rewatch)
          Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: MF.accentSoft, borderRadius: BorderRadius.circular(10)),
            child: Text('Already completed: this logs a rewatch/reread from ${unitLabel(unit, 1)} 1.',
                style: const TextStyle(fontSize: 13)),
          ),
        const SizedBox(height: 16),
        SegmentedButton<bool>(
          segments: [
            ButtonSegment(value: true, label: Text('${_cap(unitLabel(unit, 1))} reached')),
            const ButtonSegment(value: false, label: Text('Amount')),
          ],
          selected: {_reachedMode},
          onSelectionChanged: (s) => setState(() {
            _reachedMode = s.first;
            _syncMinutes();
          }),
        ),
        const SizedBox(height: 14),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: TextField(
              key: ValueKey(_reachedMode),
              controller: _reachedMode ? _reached : _amount,
              autofocus: widget.libraryId != null,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
              onChanged: (_) => setState(() {
                _error = null;
                _syncMinutes();
              }),
              decoration: InputDecoration(
                labelText: _reachedMode ? '${_cap(unitLabel(unit, 1))} reached' : 'How many ${unitLabel(unit, 2)}',
                // Before → after, like the log form ("Episode 12 → 15 / 28 · +3 episodes").
                helperText: p == null
                    ? null
                    : '${_cap(unitLabel(unit, 1))} ${fmtNumber(p.start)} → '
                        '${(title.total ?? 0) > 0 && p.end >= title.total! ? 'Completed' : '${fmtNumber(p.end)}${(title.total ?? 0) > 0 ? ' / ${fmtNumber(title.total!)}' : ''}'}'
                        ' · +${fmtNumber(p.qty)} ${unitLabel(unit, p.qty)}',
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 120,
            child: TextField(
              controller: _minutes,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
              onChanged: (_) => setState(() => _minutesEdited = true),
              decoration: const InputDecoration(labelText: 'Minutes', helperText: 'Time spent'),
            ),
          ),
        ]),
        const SizedBox(height: 14),
        TextField(
          controller: _note,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Note (optional)', hintText: 'What did you think?'),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 4, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          TextButton.icon(
            onPressed: _pickDate,
            icon: const Icon(Icons.event_outlined, size: 18),
            label: Text(_date == null ? 'Today' : fmtDay(isoDay(_date!))),
          ),
          TextButton.icon(
            onPressed: _pickTime,
            icon: const Icon(Icons.schedule_rounded, size: 18),
            label: Text(_timeText ?? (_date == null ? 'Now' : 'Set a time')),
          ),
          if (_time != null)
            IconButton(
              tooltip: 'Clear the time',
              visualDensity: VisualDensity.compact,
              onPressed: () => setState(() => _time = null),
              icon: const Icon(Icons.close_rounded, size: 16),
            ),
        ]),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _saving ? null : _addAnother,
            icon: const Icon(Icons.playlist_add_rounded, size: 20),
            label: const Text('Add another title'),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 4),
          Text(_error!, style: const TextStyle(color: MF.bad)),
        ],
        if (count > 0) ...[
          const SizedBox(height: 10),
          Row(children: [
            Icon(Icons.auto_awesome_rounded, size: 18, color: MF.accent),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                  _xp != null && !_xpWorking
                      ? '${count > 1 ? 'These $count titles earn' : 'This log earns'} +${fmtNumber(_xp!.round())} XP'
                      : _xpProblem != null && !_xpWorking
                          ? _xpProblem!
                          : 'Working out the XP…',
                  style: TextStyle(fontWeight: FontWeight.w800, color: _xp != null && !_xpWorking ? MF.text : MF.textDim)),
            ),
          ]),
        ],
        const SizedBox(height: 14),
        FilledButton(
          onPressed: _saving ? null : _save,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          child: _saving
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
              : Text(
                  count > 1
                      ? 'Log $count titles'
                      : p == null || !(p.qty > 0)
                          ? (_batch.isNotEmpty ? 'Log ${_batch.length} title${_batch.length == 1 ? '' : 's'}' : 'Save log')
                          : 'Log ${fmtNumber(p.qty)} ${unitLabel(unit, p.qty)} · ${fmtMinutes(p.minutes)}',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        ),
        const SizedBox(height: 8),
        Text('Saved on this device instantly, then synced to your MediaFlow account.',
            textAlign: TextAlign.center, style: TextStyle(color: MF.textDim, fontSize: 12)),
      ]),
    );
  }

  String _cap(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  /// The titles added to this log so far (8.2.0).
  Widget _batchCard() => Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 6),
        decoration: BoxDecoration(color: MF.raised, borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('In this log (${_batch.length})', style: TextStyle(color: MF.textDim, fontSize: 12, fontWeight: FontWeight.w800)),
          for (final b in _batch)
            Row(children: [
              Expanded(child: Text(b.text, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))),
              IconButton(
                tooltip: 'Remove from this log',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: () => setState(() {
                  _batch.remove(b);
                  _xpKey = '';
                }),
              ),
            ]),
        ]),
      );

  Widget _picker(AccountView view) {
    final q = _search.text.trim().toLowerCase();
    final matches = view.library.where((t) => t.status != 'dropped' && (q.isEmpty || nameMatches(t.raw, q))).toList()
      ..sort((a, b) {
        final ar = a.status == 'active' ? 0 : 1, br = b.status == 'active' ? 0 : 1;
        if (ar != br) return ar - br;
        final at = a.modifiedAt > 0 ? a.modifiedAt : a.createdAt, bt = b.modifiedAt > 0 ? b.modifiedAt : b.createdAt;
        return bt.compareTo(at);
      });
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (_batch.isNotEmpty) ...[
          _batchCard(),
          FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            child: Text(_batch.length == 1 ? 'Log this title' : 'Log these ${_batch.length} titles',
                style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
          const SizedBox(height: 14),
        ],
        Text(_batch.isEmpty ? 'What did you watch or read?' : 'Add another title',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        TextField(
          controller: _search,
          autofocus: true,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(hintText: 'Search your Library', prefixIcon: Icon(Icons.search_rounded)),
        ),
        const SizedBox(height: 8),
        Flexible(
          child: matches.isEmpty
              ? Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('No matching titles. Add new titles on the MediaFlow website for now.',
                      textAlign: TextAlign.center, style: TextStyle(color: MF.textDim)),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: matches.length > 60 ? 60 : matches.length,
                  itemBuilder: (context, i) {
                    final t = matches[i];
                    final cat = view.category(t.categoryId);
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                      leading: Cover(title: t, category: cat, width: 34),
                      title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text('${cat.name} · ${progressText(t, cat)}',
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: MF.textDim)),
                      onTap: () => setState(() {
                        _libraryId = t.id;
                        _selectDefaults();
                      }),
                    );
                  },
                ),
        ),
        const SizedBox(height: 12),
      ]),
    );
  }
}
