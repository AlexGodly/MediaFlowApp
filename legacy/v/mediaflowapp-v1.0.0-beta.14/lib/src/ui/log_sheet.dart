import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/account_controller.dart';
import '../logic/log_engine.dart';
import '../state/models.dart';
import '../util/js.dart';
import 'theme.dart';
import 'widgets.dart';

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
    builder: (_) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: child,
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
    return ListenableBuilder(
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
                    Flexible(child: Text(cat.name, style: const TextStyle(color: MF.textDim))),
                  ]),
                  const SizedBox(height: 8),
                  Text(statusLabel(title.status),
                      style: TextStyle(color: statusColor(title.status), fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(progressText(title, cat), style: const TextStyle(color: MF.text)),
                  if (title.rating != null && title.rating! > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('Rated ${fmtNumber(title.rating!)}', style: const TextStyle(color: MF.textDim)),
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
                    style: const TextStyle(color: MF.textDim),
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
                  style: const TextStyle(color: MF.textDim),
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
  bool _saving = false;
  String? _error;

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

  Future<void> _save() async {
    final e = _entry();
    final p = _preview();
    if (e == null || p == null) return;
    if (!(p.qty > 0)) {
      setState(() => _error = _reachedMode
          ? 'Enter a number higher than ${fmtNumber(p.start)}.'
          : 'Enter an amount above 0.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final outcome = await widget.account.log(
        [_minutesEdited ? e : LogEntry(libraryId: e.libraryId, reached: e.reached, amount: e.amount, minutes: p.minutes)],
        note: _note.text,
        date: _date == null ? null : isoDay(_date!),
      );
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      final cat = widget.account.view!.category(_title?.categoryId ?? '');
      final done = outcome.completed.isNotEmpty ? ' · Completed!' : '';
      messenger.showSnackBar(SnackBar(
        content: Text('Logged ${fmtNumber(p.qty)} ${unitLabel(cat.unit, p.qty)} of ${outcome.titles.join(', ')}'
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
    final unit = cat.unit;
    final rewatch = title.isCompleted;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Cover(title: title, category: cat, width: 52),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text('${cat.name} · ${progressText(title, cat)}', style: const TextStyle(color: MF.textDim, fontSize: 13)),
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
                helperText: p == null
                    ? null
                    : _reachedMode
                        ? 'From ${fmtNumber(p.start)} → +${fmtNumber(p.qty)} ${unitLabel(unit, p.qty)}'
                        : '${fmtNumber(p.start)} → ${fmtNumber(p.end)}',
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
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _pickDate,
            icon: const Icon(Icons.event_outlined, size: 18),
            label: Text(_date == null ? 'Today' : fmtDay(isoDay(_date!))),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 4),
          Text(_error!, style: const TextStyle(color: MF.bad)),
        ],
        const SizedBox(height: 14),
        FilledButton(
          onPressed: _saving ? null : _save,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          child: _saving
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
              : Text(
                  p == null || !(p.qty > 0)
                      ? 'Save log'
                      : 'Log ${fmtNumber(p.qty)} ${unitLabel(unit, p.qty)} · ${fmtMinutes(p.minutes)}',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        ),
        const SizedBox(height: 8),
        const Text('Saved on this device instantly, then synced to your MediaFlow account.',
            textAlign: TextAlign.center, style: TextStyle(color: MF.textDim, fontSize: 12)),
      ]),
    );
  }

  String _cap(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  Widget _picker(AccountView view) {
    final q = _search.text.trim().toLowerCase();
    final matches = view.library.where((t) => t.status != 'dropped' && (q.isEmpty || t.title.toLowerCase().contains(q))).toList()
      ..sort((a, b) {
        final ar = a.status == 'active' ? 0 : 1, br = b.status == 'active' ? 0 : 1;
        if (ar != br) return ar - br;
        final at = a.modifiedAt > 0 ? a.modifiedAt : a.createdAt, bt = b.modifiedAt > 0 ? b.modifiedAt : b.createdAt;
        return bt.compareTo(at);
      });
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('What did you watch or read?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
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
              ? const Padding(
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
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: MF.textDim)),
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
