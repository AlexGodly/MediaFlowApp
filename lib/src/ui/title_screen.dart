// Title Details and the title editor (add / edit), with online cover and total
// search, seasons, dates, repeats, rating and every quick action.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/account_controller.dart';
import '../data/edit_op.dart';
import '../data/metadata_search.dart';
import '../logic/library_logic.dart';
import '../state/models.dart';
import '../util/js.dart';
import 'log_sheet.dart';
import 'theme.dart';
import 'widgets.dart';

const kStatusChoices = [('planned', 'Planned'), ('active', 'In progress'), ('paused', 'Paused'), ('completed', 'Completed'), ('dropped', 'Dropped')];
const kPriorityChoices = [('high', 'High'), ('medium', 'Medium'), ('low', 'Low')];

String _date(int ms) {
  const mo = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${mo[d.month - 1]} ${d.day}, ${d.year}';
}

void _toast(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 3)));

/// Opens Title Details (and marks the title as seen, like the website).
Future<void> openTitle(BuildContext context, AccountController account, String id) {
  unawaitedSeen(account, id);
  return Navigator.of(context).push(MaterialPageRoute(builder: (_) => TitleScreen(account: account, id: id)));
}

void unawaitedSeen(AccountController account, String id) {
  final item = account.view?.library.where((t) => t.id == id).firstOrNull;
  if (item == null) return;
  final now = DateTime.now().millisecondsSinceEpoch;
  if (now - jsNum(item.raw['lastSeenAt']) < 750) return;
  // One small change (no full-account comparison), uploaded with the next sync.
  account.perform(
    EditOp(id: mediaFlowUid(now), createdAt: now, changes: [Change('set', ['library', '#$id', 'lastSeenAt'], now, item.raw['lastSeenAt'])]),
    delay: const Duration(seconds: 20),
  );
}

class TitleScreen extends StatelessWidget {
  const TitleScreen({super.key, required this.account, required this.id});
  final AccountController account;
  final String id;

  Future<void> _status(BuildContext context, String value) async {
    await account.edit((s, now) => setStatus(s, id, value, now, () => mediaFlowUid(now)), label: 'Change status');
  }

  Future<void> _delete(BuildContext context, LibraryTitle t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Delete ${t.title}?'),
        content: const Text('The title is removed from your Library. History logs stay. You can restore it from Library History.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: MF.bad), onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final nav = Navigator.of(context);
    var n = 0;
    await account.edit((s, now) {
      var k = 0;
      n = deleteTitles(s, {id}, now, () => mediaFlowUid(now + k++));
    }, label: 'Delete title');
    if (n > 0) {
      nav.pop();
      if (nav.context.mounted) _toast(nav.context, 'Library title deleted');
    }
  }

  Future<void> _rate(BuildContext context, LibraryTitle t) async {
    final r = await askRating(context, t.rating ?? 0);
    if (r == null) return;
    var xp = 0.0;
    await account.edit((s, now) {
      var k = 0;
      xp = rateTitle(s, id, r, now, () => mediaFlowUid(now + k++));
    }, label: 'Rate title');
    if (context.mounted) _toast(context, 'Rated ${t.title} ${fmtNumber(r)}/10${xp > 0 ? ' · +${fmtNumber(xp)} XP' : ''} ✓');
  }

  @override
  Widget build(BuildContext context) {
    return LiveBuilder(
      listenable: account,
      builder: (context, _) {
        final view = account.view;
        final t = view?.library.where((x) => x.id == id).firstOrNull;
        if (view == null || t == null) {
          return Scaffold(appBar: AppBar(), body: const EmptyState(icon: Icons.search_off, title: 'Title not found', body: 'It may have been deleted.'));
        }
        final cat = view.category(t.categoryId);
        final raw = t.raw;
        final logs = view.logs.where((l) => l.titles.any((x) => x['libraryId'] == t.id)).toList()
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
        final seasons = asList(raw['seasons']).map(asMap).whereType<Map<String, dynamic>>().toList();
        final total = t.total;
        final pct = total == null || total == 0 ? null : (t.progress / total).clamp(0, 1).toDouble();
        final tags = asList(raw['tags']).map(jsStr).where((x) => x.isNotEmpty).toList();
        final meta = asMap(raw['universalMetadata']);
        final description = jsStr(raw['description']).isNotEmpty ? jsStr(raw['description']) : jsStr(meta?['description']);
        final repeats = jsNum(raw['manualRepeatAmount']);
        return Scaffold(
          appBar: AppBar(
            title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            actions: [
              IconButton(
                tooltip: 'Edit',
                icon: const Icon(Icons.edit_rounded),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TitleEditor(account: account, id: id))),
              ),
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'delete') _delete(context, t);
                  if (v == 'rate') _rate(context, t);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'rate', child: Text('Rate')),
                  PopupMenuItem(value: 'delete', child: Text('Delete title', style: TextStyle(color: MF.bad))),
                ],
              ),
            ],
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 32), children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Cover(title: t, category: cat, width: 110),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(t.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 6),
                      Row(children: [
                        CategoryBadge(cat, size: 22),
                        const SizedBox(width: 6),
                        Flexible(child: Text(cat.name, style: const TextStyle(color: MF.textDim))),
                      ]),
                      const SizedBox(height: 8),
                      Text(progressText(t, cat), style: const TextStyle(fontWeight: FontWeight.w700)),
                      if (pct != null) ...[
                        const SizedBox(height: 6),
                        LinearProgressIndicator(value: pct, minHeight: 6, borderRadius: BorderRadius.circular(4)),
                        const SizedBox(height: 4),
                        Text('${(pct * 100).round()}% · ${fmtNumber(math.max(0, total! - t.progress))} ${unitLabel(cat.unit, 2)} left',
                            style: const TextStyle(color: MF.textDim, fontSize: 12)),
                      ],
                      const SizedBox(height: 6),
                      InkWell(
                        onTap: () => _rate(context, t),
                        child: Text(t.rating != null && t.rating! > 0 ? '★ ${fmtNumber(t.rating!)}/10' : '☆ Not rated · tap to rate',
                            style: TextStyle(color: t.rating != null && t.rating! > 0 ? const Color(0xFFE8A94A) : MF.textDim, fontWeight: FontWeight.w700)),
                      ),
                    ]),
                  ),
                ]),
                const SizedBox(height: 16),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final s in kStatusChoices)
                    ChoiceChip(label: Text(s.$2), selected: t.status == s.$1, onSelected: (_) => _status(context, s.$1)),
                ]),
                const SizedBox(height: 16),
                FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                  icon: const Icon(Icons.add_rounded),
                  label: Text(t.isCompleted ? 'Log a rewatch / reread' : 'Log progress', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  onPressed: () {
                    final navigator = Navigator.of(context);
                    navigator.pop();
                    showLogSheet(navigator.context, account, libraryId: t.id);
                  },
                ),
                const SizedBox(height: 16),
                _info('Priority', '${jsStr(raw['priority']).isEmpty ? 'Medium' : '${jsStr(raw['priority'])[0].toUpperCase()}${jsStr(raw['priority']).substring(1)}'}'),
                if (jsNum(raw['startedAt']) > 0) _info('Started', _date(jsNum(raw['startedAt']).toInt())),
                if (jsNum(raw['completedAt']) > 0) _info('Finished', _date(jsNum(raw['completedAt']).toInt())),
                if (jsNum(raw['createdAt']) > 0) _info('Added', _date(jsNum(raw['createdAt']).toInt())),
                if (jsNum(raw['estimatedMinutes']) > 0) _info('Estimated time', fmtMinutes(jsNum(raw['estimatedMinutes']))),
                if (repeats > 0) _info('Past repeats', '${fmtNumber(repeats)} ${unitLabel(cat.unit, repeats)}'),
                if (tags.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(spacing: 6, runSpacing: 6, children: [for (final x in tags) Chip(label: Text(x), visualDensity: VisualDensity.compact)]),
                ],
                if (seasons.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text('Seasons', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  for (final s in seasons)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(children: [
                        Expanded(child: Text(jsStr(s['name']).isEmpty ? 'Season' : jsStr(s['name']))),
                        Text('${fmtNumber(jsNum(s['progress']))}${jsNum(s['total']) > 0 ? ' / ${fmtNumber(jsNum(s['total']))}' : ''}',
                            style: const TextStyle(color: MF.textDim)),
                      ]),
                    ),
                ],
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text('About', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  const SizedBox(height: 4),
                  Text(description, style: const TextStyle(color: MF.textDim)),
                ],
                const SizedBox(height: 20),
                Text(logs.isEmpty ? 'No logs yet' : 'Logs', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                for (final l in logs.take(30))
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '${fmtDay(l.date)} · ${fmtNumber(l.amount)} ${unitLabel(l.unit.isEmpty ? cat.unit : l.unit, l.amount)}'
                      ' · ${fmtMinutes(l.minutes)} · +${fmtNumber(l.xp)} XP',
                      style: const TextStyle(color: MF.textDim),
                    ),
                  ),
              ]),
            ),
          ),
        );
      },
    );
  }

  Widget _info(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          SizedBox(width: 120, child: Text(k, style: const TextStyle(color: MF.textDim))),
          Expanded(child: Text(v, style: const TextStyle(fontWeight: FontWeight.w700))),
        ]),
      );
}

/// Asks for a rating from 0.1 to 10. Returns null when cancelled.
Future<double?> askRating(BuildContext context, double current) async {
  var value = current > 0 ? current : 7.0;
  final controller = TextEditingController(text: current > 0 ? fmtNumber(current) : '');
  final r = await showDialog<double>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => AlertDialog(
        title: const Text('Rate this title'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('${value.toStringAsFixed(1)} / 10', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
          Slider(
            value: value.clamp(0.1, 10).toDouble(),
            min: 0.1,
            max: 10,
            divisions: 99,
            onChanged: (v) => set(() {
              value = (v * 10).round() / 10;
              controller.text = value.toStringAsFixed(1);
            }),
          ),
          TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            decoration: const InputDecoration(labelText: 'Rating (0.1–10)'),
            onChanged: (t) {
              final v = double.tryParse(t.replaceAll(',', '.'));
              if (v != null && v > 0 && v <= 10) set(() => value = v);
            },
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, value), child: const Text('Rate')),
        ],
      ),
    ),
  );
  controller.dispose();
  return r;
}

/// Online search for a title's cover and total. Returns the chosen result.
Future<MetadataResult?> searchOnline(BuildContext context, String query, Category cat) {
  return showModalBottomSheet<MetadataResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: MF.surface,
    builder: (c) => _MetadataSheet(query: query, category: cat),
  );
}

class _MetadataSheet extends StatefulWidget {
  const _MetadataSheet({required this.query, required this.category});
  final String query;
  final Category category;

  @override
  State<_MetadataSheet> createState() => _MetadataSheetState();
}

class _MetadataSheetState extends State<_MetadataSheet> {
  late final _q = TextEditingController(text: widget.query);
  List<MetadataResult>? _results;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (widget.query.trim().isNotEmpty) _run();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    setState(() => _busy = true);
    final r = await searchMetadata(_q.text, unit: widget.category.unit, type: jsStr(widget.category.raw['type']));
    if (mounted) {
      setState(() {
        _results = r;
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.85,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: TextField(
            controller: _q,
            autofocus: widget.query.isEmpty,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _run(),
            decoration: InputDecoration(
              hintText: 'Search covers and details online',
              prefixIcon: const Icon(Icons.travel_explore_rounded),
              suffixIcon: IconButton(icon: const Icon(Icons.search_rounded), onPressed: _run),
            ),
          ),
        ),
        if (_busy) const LinearProgressIndicator(),
        Expanded(
          child: results == null
              ? const SizedBox.shrink()
              : results.isEmpty
                  ? const Center(child: Text('No results. You may be offline, or try another spelling.', style: TextStyle(color: MF.textDim)))
                  : ListView(children: [
                      for (final r in results)
                        ListTile(
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: SizedBox(
                              width: 44,
                              height: 64,
                              child: r.coverUrl.isEmpty
                                  ? const ColoredBox(color: MF.raised)
                                  : Image.network(r.coverUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const ColoredBox(color: MF.raised)),
                            ),
                          ),
                          title: Text(r.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                            [r.source, if (r.year != null) '${r.year}', if (r.total != null) '${r.total} ${unitLabel(widget.category.unit, r.total!)}', if (r.subtitle.isNotEmpty) r.subtitle]
                                .join(' · '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => Navigator.pop(context, r),
                        ),
                    ]),
        ),
      ]),
    );
  }
}

/// Add or edit a Library title (the website's title editor).
class TitleEditor extends StatefulWidget {
  const TitleEditor({super.key, required this.account, this.id, this.initialTitle = '', this.initialCategory});
  final AccountController account;
  final String? id;
  final String initialTitle;
  final String? initialCategory;

  @override
  State<TitleEditor> createState() => _TitleEditorState();
}

class _TitleEditorState extends State<TitleEditor> {
  late final TitleFields _f;
  final _title = TextEditingController();
  final _progress = TextEditingController();
  final _total = TextEditingController();
  final _rating = TextEditingController();
  final _cover = TextEditingController();
  final _est = TextEditingController();
  final _tags = TextEditingController();
  final _repeatFull = TextEditingController();
  final _repeatExtra = TextEditingController();
  late String _category, _status, _priority;
  int? _startedAt, _completedAt;
  bool _startEdited = false, _coverAuto = false, _busy = false;
  List<Map<String, dynamic>> _seasons = [];
  bool _seasonsTouched = false;
  String? _error;

  AccountController get account => widget.account;

  static String _n(num? v) => v == null ? '' : (v == v.truncateToDouble() ? v.toInt().toString() : v.toString());

  @override
  void initState() {
    super.initState();
    final view = account.view!;
    final item = widget.id == null ? null : view.library.where((t) => t.id == widget.id).firstOrNull?.raw;
    final defaultCat = widget.initialCategory ??
        (view.categories.where((c) => c.enabled).firstOrNull ?? (view.categories.isEmpty ? null : view.categories.first))?.id ??
        '';
    _f = item == null ? TitleFields(title: widget.initialTitle, categoryId: defaultCat) : TitleFields.of(item);
    _title.text = _f.title;
    _progress.text = _n(_f.progress);
    _total.text = _n(_f.total);
    _rating.text = _n(_f.rating);
    _cover.text = _f.coverUrl;
    _est.text = _n(_f.estimatedMinutes);
    _tags.text = _f.tags.join(', ');
    _repeatFull.text = _f.repeatFull == 0 ? '' : '${_f.repeatFull}';
    _repeatExtra.text = _f.repeatExtra == 0 ? '' : '${_f.repeatExtra}';
    _category = _f.categoryId;
    _status = _f.status;
    _priority = _f.priority;
    _startedAt = _f.startedAt;
    _completedAt = _f.completedAt;
    _coverAuto = _f.coverAuto;
    _seasons = [for (final s in asList(item?['seasons'])) if (asMap(s) != null) Map<String, dynamic>.from(asMap(s)!)];
  }

  @override
  void dispose() {
    for (final c in [_title, _progress, _total, _rating, _cover, _est, _tags, _repeatFull, _repeatExtra]) {
      c.dispose();
    }
    super.dispose();
  }

  double? _num(TextEditingController c) => c.text.trim().isEmpty ? null : double.tryParse(c.text.trim().replaceAll(',', '.'));

  Future<void> _pickDate(bool start) async {
    final current = start ? _startedAt : _completedAt;
    final d = await showDatePicker(
      context: context,
      initialDate: current == null ? DateTime.now() : DateTime.fromMillisecondsSinceEpoch(current),
      firstDate: DateTime(1950),
      lastDate: DateTime(2100),
    );
    if (d == null) return;
    // v135ParseDateInput: noon local time on the chosen day.
    final ms = DateTime(d.year, d.month, d.day, 12).millisecondsSinceEpoch;
    setState(() {
      if (start) {
        _startedAt = ms;
        _startEdited = true;
      } else {
        _completedAt = ms;
      }
    });
  }

  Future<void> _search() async {
    final cat = account.view!.category(_category);
    final r = await searchOnline(context, _title.text, cat);
    if (r == null || !mounted) return;
    setState(() {
      if (_title.text.trim().isEmpty) _title.text = r.title;
      if (r.coverUrl.isNotEmpty) {
        _cover.text = r.coverUrl;
        _coverAuto = true;
      }
      if (r.total != null && _total.text.trim().isEmpty) _total.text = '${r.total}';
    });
  }

  Future<void> _save() async {
    final view = account.view!;
    if (!view.categories.any((c) => c.id == _category)) {
      setState(() => _error = 'Choose a category.');
      return;
    }
    final fields = TitleFields(
      title: _title.text,
      categoryId: _category,
      progress: _num(_progress) ?? 0,
      total: _num(_total),
      status: _status,
      priority: _priority,
      estimatedMinutes: _num(_est),
      tags: _tags.text.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList(),
      rating: _num(_rating),
      coverUrl: _cover.text,
      coverAuto: _coverAuto,
      repeatFull: (_num(_repeatFull) ?? 0).floor(),
      repeatExtra: (_num(_repeatExtra) ?? 0).floor(),
      startedAt: _startedAt,
      startEdited: _startEdited,
      completedAt: _completedAt,
      seasons: _seasonsTouched ? _seasons : null,
    );
    setState(() {
      _busy = true;
      _error = null;
    });
    String? error;
    var xp = 0.0;
    await account.edit((s, now) {
      var k = 0;
      error = saveTitle(s, widget.id, fields, now, () => mediaFlowUid(now + k++), saved: (_, e) => xp = e);
    }, label: widget.id == null ? 'Add title' : 'Edit title');
    if (!mounted) return;
    setState(() => _busy = false);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.of(context).pop();
    _toast(context, xp > 0 ? 'Saved · +${fmtNumber(xp)} XP' : 'Saved');
  }

  Widget _numField(TextEditingController c, String label, {bool decimal = true}) => TextField(
        controller: c,
        keyboardType: TextInputType.numberWithOptions(decimal: decimal),
        inputFormatters: [FilteringTextInputFormatter.allow(decimal ? RegExp(r'[0-9.,]') : RegExp(r'[0-9]'))],
        decoration: InputDecoration(labelText: label),
      );

  @override
  Widget build(BuildContext context) {
    final view = account.view!;
    final cat = view.category(_category);
    final unit = cat.unit;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.id == null ? 'Add title' : 'Edit title'),
        actions: [
          TextButton(onPressed: _busy ? null : _save, child: const Text('Save')),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 40), children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Cover(title: LibraryTitle(<String, dynamic>{'title': _title.text, 'categoryId': _category, 'coverUrl': _cover.text}), category: cat, width: 84),
              const SizedBox(width: 14),
              Expanded(
                child: Column(children: [
                  TextField(
                    controller: _title,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Title'),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(onPressed: _search, icon: const Icon(Icons.travel_explore_rounded, size: 18), label: const Text('Search online')),
                  ),
                ]),
              ),
            ]),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: view.categories.any((c) => c.id == _category) ? _category : null,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Category'),
              items: [for (final c in view.categories) DropdownMenuItem(value: c.id, child: Text(c.name))],
              onChanged: (v) => setState(() => _category = v ?? _category),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _status,
                  decoration: const InputDecoration(labelText: 'Status'),
                  items: [for (final s in kStatusChoices) DropdownMenuItem(value: s.$1, child: Text(s.$2))],
                  onChanged: (v) => setState(() => _status = v ?? _status),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _priority,
                  decoration: const InputDecoration(labelText: 'Priority'),
                  items: [for (final s in kPriorityChoices) DropdownMenuItem(value: s.$1, child: Text(s.$2))],
                  onChanged: (v) => setState(() => _priority = v ?? _priority),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: _numField(_progress, '${unitLabel(unit, 2)[0].toUpperCase()}${unitLabel(unit, 2).substring(1)} done')),
              const SizedBox(width: 10),
              Expanded(child: _numField(_total, 'Total (blank = unknown)')),
              const SizedBox(width: 10),
              Expanded(child: _numField(_rating, 'Rating /10')),
            ]),
            const SizedBox(height: 10),
            TextField(
              controller: _cover,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                labelText: 'Cover image URL',
                suffixIcon: _cover.text.isEmpty
                    ? null
                    : IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => setState(() => _cover.clear())),
              ),
              onChanged: (_) => setState(() => _coverAuto = false),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: _numField(_est, 'Estimated minutes')),
              const SizedBox(width: 10),
              Expanded(flex: 2, child: TextField(controller: _tags, decoration: const InputDecoration(labelText: 'Tags (comma separated)'))),
            ]),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickDate(true),
                  icon: const Icon(Icons.play_arrow_rounded, size: 18),
                  label: Text(_startedAt == null ? 'Start date' : 'Started ${_date(_startedAt!)}'),
                ),
              ),
              if (_startedAt != null)
                IconButton(tooltip: 'Clear start date', icon: const Icon(Icons.close_rounded), onPressed: () => setState(() => _startedAt = null)),
            ]),
            if (_status == 'completed')
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickDate(false),
                    icon: const Icon(Icons.flag_rounded, size: 18),
                    label: Text(_completedAt == null ? 'Finish date (today)' : 'Finished ${_date(_completedAt!)}'),
                  ),
                ),
                if (_completedAt != null)
                  IconButton(tooltip: 'Use today', icon: const Icon(Icons.close_rounded), onPressed: () => setState(() => _completedAt = null)),
              ]),
            const SizedBox(height: 14),
            const Text('Past repeats (not logged)', style: TextStyle(fontWeight: FontWeight.w800)),
            const Text('Rewatches or rereads from before MediaFlow. They count in Statistics but add no History, XP or streak.',
                style: TextStyle(color: MF.textDim, fontSize: 12)),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(child: _numField(_repeatFull, 'Full repeats', decimal: false)),
              const SizedBox(width: 10),
              Expanded(child: _numField(_repeatExtra, 'Extra ${unitLabel(unit, 2)}', decimal: false)),
            ]),
            const SizedBox(height: 14),
            Row(children: [
              const Expanded(child: Text('Seasons', style: TextStyle(fontWeight: FontWeight.w800))),
              TextButton.icon(
                onPressed: () => setState(() {
                  _seasonsTouched = true;
                  _seasons.add({'name': 'Season ${_seasons.length + 1}', 'progress': 0, 'total': null});
                }),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add season'),
              ),
            ]),
            for (var i = 0; i < _seasons.length; i++)
              Padding(
                key: ValueKey('season-$i-${_seasons.length}'),
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(children: [
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      initialValue: jsStr(_seasons[i]['name']),
                      decoration: const InputDecoration(labelText: 'Name', isDense: true),
                      onChanged: (v) {
                        _seasonsTouched = true;
                        _seasons[i]['name'] = v;
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      initialValue: _n(jsNumOrNull(_seasons[i]['progress'])),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(labelText: 'Done', isDense: true),
                      onChanged: (v) {
                        _seasonsTouched = true;
                        _seasons[i]['progress'] = int.tryParse(v) ?? 0;
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      initialValue: _seasons[i]['total'] == null ? '' : _n(jsNum(_seasons[i]['total'])),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(labelText: 'Total', isDense: true),
                      onChanged: (v) {
                        _seasonsTouched = true;
                        _seasons[i]['total'] = int.tryParse(v);
                      },
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => setState(() {
                      _seasonsTouched = true;
                      _seasons.removeAt(i);
                    }),
                  ),
                ]),
              ),
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: const TextStyle(color: MF.bad))),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _save,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              child: Text(widget.id == null ? 'Add to Library' : 'Save changes', style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
          ]),
        ),
      ),
    );
  }
}
