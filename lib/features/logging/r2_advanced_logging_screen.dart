import 'dart:convert';
import 'package:flutter/material.dart';
import '../../data/mediaflow_library_repository.dart';
import '../../data/mediaflow_models.dart';
import 'r2_advanced_logging_drafts.dart';

/// Native Flutter implementation of the approved R2 Logging design.
/// It reads the signed-in Library through the existing safe repository.
/// All edits stay in the in-memory draft controller. No account writes.
class R2AdvancedLoggingScreen extends StatefulWidget {
  const R2AdvancedLoggingScreen({
    super.key, required this.repository, required this.drafts,
    this.openLegacyBrowser,
  });
  final MediaFlowLibraryRepository repository;
  final R2AdvancedLoggingDrafts drafts;
  final VoidCallback? openLegacyBrowser;

  @override
  State<R2AdvancedLoggingScreen> createState() => _R2AdvancedLoggingScreenState();
}

class _R2AdvancedLoggingScreenState extends State<R2AdvancedLoggingScreen> {
  late Future<MediaFlowCatalog> _future;
  final TextEditingController _search = TextEditingController();
  String _query = '';
  String _category = 'all', _status = 'all', _priority = 'all';
  String _sort = 'priority-desc';
  bool _filters = false;
  int _page = 0;
  static const int _pageSize = 12;

  @override
  void initState() {
    super.initState();
    _future = widget.repository.load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _reload() => setState(() {
    _future = widget.repository.reload();
    _page = 0;
  });

  List<MediaFlowTitle> _filtered(MediaFlowCatalog catalog) {
    final rows = catalog.library.where((title) {
      if (_query.isNotEmpty &&
          !(title.searchText.contains(_query.toLowerCase()))) return false;
      if (_category != 'all' && title.categoryId != _category) return false;
      if (_status != 'all' && title.status != _status) return false;
      if (_priority != 'all' && title.priority != _priority) return false;
      return true;
    }).toList();
    int priority(String value) => const {'low': 0, 'medium': 1, 'high': 2}[value] ?? 1;
    int compare(MediaFlowTitle a, MediaFlowTitle b) {
      int cmp = 0;
      switch (_sort) {
        case 'title-asc':
          cmp = a.title.compareTo(b.title);
          break;
        case 'title-desc':
          cmp = b.title.compareTo(a.title);
          break;
        case 'priority-asc':
          cmp = priority(a.priority).compareTo(priority(b.priority));
          break;
        case 'rating-desc':
          cmp = (b.rating ?? 0).compareTo(a.rating ?? 0);
          break;
        case 'rating-asc':
          cmp = (a.rating ?? 0).compareTo(b.rating ?? 0);
          break;
        case 'progress-desc':
          cmp = b.progress.compareTo(a.progress);
          break;
        case 'progress-asc':
          cmp = a.progress.compareTo(b.progress);
          break;
        case 'total-desc':
          cmp = (b.total ?? 0).compareTo(a.total ?? 0);
          break;
        case 'total-asc':
          cmp = (a.total ?? 0).compareTo(b.total ?? 0);
          break;
        case 'added-desc':
          cmp = (b.addedAt ?? DateTime(1970))
              .compareTo(a.addedAt ?? DateTime(1970));
          break;
        case 'added-asc':
          cmp = (a.addedAt ?? DateTime(1970))
              .compareTo(b.addedAt ?? DateTime(1970));
          break;
        default:
          cmp = priority(b.priority).compareTo(priority(a.priority));
          break;
      }
      return cmp != 0 ? cmp : a.title.compareTo(b.title);
    }
    rows.sort(compare);
    return rows;
  }

  Widget _panel(String title, Widget child, {String? subtitle, Widget? action}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              if (subtitle != null) Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              ),
            ])),
            if (action != null) action,
          ]),
          const SizedBox(height: 14),
          child,
        ]),
      ),
    );
  }

  Widget _recommendation(MediaFlowCatalog catalog) {
    final task = catalog.currentTask;
    final matches = catalog.library.where((title) =>
        task != null && task.libraryId.isNotEmpty &&
        title.id == task.libraryId);
    final exact = matches.isEmpty ? null : matches.first;
    return _panel('MediaFlow recommends', Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (task == null)
          const Text('No active recommendation in the current account snapshot.')
        else if (exact == null) ...[
          Text(task.title.isEmpty ? 'Category-only task' : task.title),
          const SizedBox(height: 6),
          const Text('The saved task does not resolve to an exact Library ID. '
              'Choose a title manually; name matches are never assumed.'),
        ] else ...[
          Row(children: [
            _cover(exact, catalog, 68),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(exact.title, maxLines: 3, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(_progressText(exact)),
              const SizedBox(height: 6),
              if (task.reasons.isNotEmpty)
                Text(task.reasons.take(3).join(' · '),
                    style: Theme.of(context).textTheme.bodySmall),
            ])),
          ]),
          const SizedBox(height: 10),
          FilledButton.tonalIcon(
            key: const Key('r2-add-recommended'),
            onPressed: widget.drafts.contains(exact.id) ? null
                : () => widget.drafts.add(exact),
            icon: const Icon(Icons.add),
            label: Text(widget.drafts.contains(exact.id)
                ? 'Already in session' : 'Add recommended title'),
          ),
        ],
      ],
    ), subtitle: 'Only exact saved MediaFlow task IDs are actionable.');
  }

  String _progressText(MediaFlowTitle title) {
    final current = title.progress.toStringAsFixed(0);
    final total = title.total?.toStringAsFixed(0) ?? '?';
    return current + ' / ' + total + ' consumed · ' + title.priority + ' priority';
  }

  Widget _cover(MediaFlowTitle title, MediaFlowCatalog catalog, double size) {
    final category = catalog.categoryById[title.categoryId];
    final url = Uri.tryParse(title.coverUrl);
    final usable = url != null && (url.scheme == 'https' || url.scheme == 'http');
    return ClipRRect(
      borderRadius: BorderRadius.circular(9),
      child: Container(
        width: size * .72, height: size,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: usable
          ? Image.network(title.coverUrl, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Center(
                child: Text(category?.icon ?? '◈',
                  style: TextStyle(fontSize: size * .42))))
          : Center(child: Text(category?.icon ?? '◈',
              style: TextStyle(fontSize: size * .42))),
      ),
    );
  }

  Widget _picker(MediaFlowCatalog catalog) {
    final all = _filtered(catalog);
    final pages = (all.length / _pageSize).ceil();
    final current = _page.clamp(0, pages > 0 ? pages - 1 : 0);
    final start = current * _pageSize;
    final visible = all.skip(start).take(_pageSize).toList();
    return _panel('Choose from your Library', Column(children: [
      TextField(
        key: const Key('r2-library-search'),
        controller: _search,
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.search),
          hintText: 'Search your Library titles or tags',
          border: OutlineInputBorder(),
          isDense: true,
        ),
        onChanged: (value) => setState(() { _query = value.trim(); _page = 0; }),
      ),
      const SizedBox(height: 8),
      Align(alignment: Alignment.centerLeft, child: TextButton.icon(
        onPressed: () => setState(() => _filters = !_filters),
        icon: Icon(_filters ? Icons.tune : Icons.filter_list),
        label: Text(_filters ? 'Hide filters & sorting' : 'Filters & sorting'),
      )),
      if (_filters) ...[
        _select('Category', _category, [
          const DropdownMenuItem(value: 'all', child: Text('All categories')),
          for (final category in catalog.categories)
            DropdownMenuItem(value: category.id, child: Text(category.name)),
        ], (value) => setState(() { _category = value; _page = 0; })),
        _select('Status', _status, [
          for (final choice in const ['all','planned','active','paused','completed','dropped'])
            DropdownMenuItem(value: choice, child: Text(choice == 'all' ? 'All statuses' : choice)),
        ], (value) => setState(() { _status = value; _page = 0; })),
        _select('Priority', _priority, [
          for (final choice in const ['all','high','medium','low'])
            DropdownMenuItem(value: choice, child: Text(choice == 'all' ? 'All priorities' : choice)),
        ], (value) => setState(() { _priority = value; _page = 0; })),
        _select('Sort by', _sort, const [
          DropdownMenuItem(value: 'priority-desc', child: Text('Priority · high first')),
          DropdownMenuItem(value: 'priority-asc', child: Text('Priority · low first')),
          DropdownMenuItem(value: 'title-asc', child: Text('Title · A–Z')),
          DropdownMenuItem(value: 'title-desc', child: Text('Title · Z–A')),
          DropdownMenuItem(value: 'rating-desc', child: Text('Rating · highest')),
          DropdownMenuItem(value: 'rating-asc', child: Text('Rating · lowest')),
          DropdownMenuItem(value: 'progress-desc', child: Text('Progress · most')),
          DropdownMenuItem(value: 'progress-asc', child: Text('Progress · least')),
          DropdownMenuItem(value: 'total-desc', child: Text('Total · highest')),
          DropdownMenuItem(value: 'total-asc', child: Text('Total · lowest')),
          DropdownMenuItem(value: 'added-desc', child: Text('Date added · newest')),
          DropdownMenuItem(value: 'added-asc', child: Text('Date added · oldest')),
        ], (value) => setState(() { _sort = value; _page = 0; })),
        Align(alignment: Alignment.centerRight, child: TextButton(
          onPressed: () => setState(() {
            _category = 'all'; _status = 'all';
            _priority = 'all'; _sort = 'priority-desc'; _page = 0;
          }),
          child: const Text('Reset filters'),
        )),
      ],
      for (final title in visible)
        ListTile(
          key: ValueKey('r2-library-' + title.id),
          contentPadding: EdgeInsets.zero,
          leading: _cover(title, catalog, 52),
          title: Text(title.title, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text(_progressText(title), maxLines: 1,
              overflow: TextOverflow.ellipsis),
          trailing: IconButton(
            tooltip: widget.drafts.contains(title.id) ? 'Added' : 'Add to draft',
            onPressed: widget.drafts.contains(title.id) ? null
              : () => widget.drafts.add(title),
            icon: Icon(widget.drafts.contains(title.id)
                ? Icons.check_circle_outline : Icons.add_circle_outline),
          ),
          onTap: () => widget.drafts.add(title),
        ),
      if (visible.isEmpty) const Padding(
        padding: EdgeInsets.symmetric(vertical: 22),
        child: Text('No titles match these filters.'),
      ),
      if (pages > 1)
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          IconButton(
            tooltip: 'Previous page',
            onPressed: current == 0 ? null
                : () => setState(() => _page = current - 1),
            icon: const Icon(Icons.chevron_left),
          ),
          Text('Page ' + (current + 1).toString() +
              ' / ' + pages.toString() + ' · ' + all.length.toString() + ' titles'),
          IconButton(
            tooltip: 'Next page',
            onPressed: current >= pages - 1 ? null
                : () => setState(() => _page = current + 1),
            icon: const Icon(Icons.chevron_right),
          ),
        ]),
    ]), subtitle: all.length.toString() + ' matching titles · full account Library');
  }

  Widget _select<T>(String label, T value, List<DropdownMenuItem<T>> options,
      ValueChanged<T> changed) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: DropdownButtonFormField<T>(
      value: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label, border: const OutlineInputBorder(), isDense: true),
      items: options,
      onChanged: (next) { if (next != null) changed(next); },
    ),
  );

  Future<void> _chooseTime(R2DraftTitle draft, {int? unit}) async {
    final previous = unit == null
        ? draft.whenWatched : draft.currentUnits[unit] ?? draft.whenWatched;
    if (!mounted) return;
    final date = await showDatePicker(
      context: context, initialDate: previous,
      firstDate: DateTime(1970), lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context, initialTime: TimeOfDay.fromDateTime(previous));
    if (time == null) return;
    final stamp = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    widget.drafts.update(draft.titleId, (entry) {
      if (unit == null) { entry.whenWatched = stamp; }
      else { entry.setUnitTime(unit, stamp); }
    });
  }

  Future<void> _editAmount(R2DraftTitle entry, MediaFlowTitle title,
      {required bool last}) async {
    final current = last ? entry.startFor(title) + entry.currentUnits.length
        : entry.currentUnits.length;
    final field = TextEditingController(text: current.toString());
    final result = await showDialog<int>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(last ? 'Last watched / read unit' : 'Amount consumed'),
        content: TextField(
          key: const Key('r2-quantity-input'),
          controller: field, autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog),
            child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialog, int.tryParse(field.text)),
            child: const Text('Apply')),
        ],
      ),
    );
    field.dispose();
    if (result == null) return;
    widget.drafts.update(entry.titleId, (draft) {
      if (last) { draft.setLastUnit(title, result); }
      else { draft.setAmount(title, result); }
    });
  }

  Widget _stepper(R2DraftTitle draft, MediaFlowTitle title) {
    final last = draft.method == R2LoggingMethod.lastUnit;
    final base = draft.startFor(title);
    final number = draft.currentUnits.length + (last ? base : 0);
    final lower = last ? base : 0;
    final upper = draft.allowedQuantity(title) + (last ? base : 0);
    void set(int value) => widget.drafts.update(draft.titleId, (entry) {
      if (last) { entry.setLastUnit(title, value); }
      else { entry.setAmount(title, value); }
    });
    return Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 7, children: [
      OutlinedButton.icon(
        key: ValueKey('r2-minus-' + draft.titleId),
        onPressed: number <= lower ? null : () => set(number - 1),
        icon: const Icon(Icons.remove, size: 16),
        label: const Text('Less'),
      ),
      OutlinedButton(
        onPressed: () => _editAmount(draft, title, last: last),
        child: Text(number.toString(), style: const TextStyle(
          fontWeight: FontWeight.bold, fontSize: 17)),
      ),
      FilledButton.tonalIcon(
        key: ValueKey('r2-plus-' + draft.titleId),
        onPressed: number >= upper ? null : () => set(number + 1),
        icon: const Icon(Icons.add, size: 16),
        label: const Text('More'),
      ),
    ]);
  }

  Widget _units(R2DraftTitle draft, MediaFlowTitle title) {
    final start = draft.startFor(title);
    final cap = draft.allowedQuantity(title);
    if (cap == 0) return const Text('No remaining units in this season.');
    final selected = draft.currentUnits;
    final highest = selected.isEmpty ? start : selected.lastKey();
    final displayed = (highest - start + 6).clamp(8, 40);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 7, runSpacing: 6, children: [
        for (var offset = 1; offset <= displayed && offset <= cap; offset++)
          InputChip(
            key: ValueKey('r2-unit-' + draft.titleId + '-' + offset.toString()),
            selected: selected.containsKey(start + offset),
            label: Text((start + offset).toString()),
            onPressed: () => widget.drafts.update(draft.titleId,
              (entry) => entry.toggleUnit(title, start + offset)),
            onDeleted: selected.containsKey(start + offset)
                ? () => _chooseTime(draft, unit: start + offset) : null,
            deleteIcon: const Icon(Icons.schedule, size: 16),
            deleteButtonTooltipMessage: 'Edit unit timestamp',
          ),
      ]),
      const SizedBox(height: 7),
      const Text('Tap a unit to select it. Use its clock icon to edit the '
          'individual logged-at timestamp.'),
    ]);
  }

  Widget _editor(R2DraftTitle draft, MediaFlowTitle title,
      MediaFlowCatalog catalog) {
    final start = draft.startFor(title);
    final after = draft.previewProgress(title);
    final total = title.total?.floor();
    final safePercent = total == null || total <= 0
        ? 0.0 : (after / total).clamp(0.0, 1.0).toDouble();
    return _panel(title.title, Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(spacing: 8, runSpacing: 4, children: [
          Chip(label: Text(title.priority + ' priority')),
          Chip(label: Text(title.status)),
          Chip(label: Text(draft.quantity.toString() + ' draft units')),
        ]),
        const SizedBox(height: 7),
        SingleChildScrollView(scrollDirection: Axis.horizontal,
          child: SegmentedButton<R2LoggingMethod>(
          showSelectedIcon: false,
          multiSelectionEnabled: false,
          segments: const [
            ButtonSegment(value: R2LoggingMethod.perUnit, label: Text('Per Unit')),
            ButtonSegment(value: R2LoggingMethod.lastUnit, label: Text('Last Unit')),
            ButtonSegment(value: R2LoggingMethod.amount, label: Text('Amount')),
          ],
          selected: {draft.method},
          onSelectionChanged: (methods) => widget.drafts.update(
            draft.titleId, (entry) => entry.chooseMethod(methods.first)),
        )),
        const SizedBox(height: 12),
        if (title.seasons.isNotEmpty) _select<String>('Season',
          draft.seasonId, [
            const DropdownMenuItem(value: '', child: Text('Entire title')),
            for (var i = 0; i < title.seasons.length; i++)
              DropdownMenuItem(
                value: title.seasons[i].id.isNotEmpty
                  ? title.seasons[i].id : 'season_$i',
                child: Text(title.seasons[i].name),
              ),
          ], (value) => widget.drafts.update(
            draft.titleId, (entry) => entry.chooseSeason(value))),
        if (draft.method == R2LoggingMethod.perUnit) _units(draft, title)
        else ...[
          Text(draft.method == R2LoggingMethod.lastUnit
              ? 'Last watched / read unit · starts at ' + start.toString()
              : 'Amount consumed'),
          const SizedBox(height: 6),
          _stepper(draft, title),
        ],
        const SizedBox(height: 14),
        Text('Progress preview · ' + title.progress.floor().toString() +
            ' → ' + after.toString() +
            (total == null ? '' : ' / ' + total.toString())),
        const SizedBox(height: 6),
        LinearProgressIndicator(value: total == null ? null : safePercent,
          minHeight: 6, borderRadius: BorderRadius.circular(12)),
        const SizedBox(height: 10),
        Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          TextButton.icon(
            onPressed: () => _chooseTime(draft),
            icon: const Icon(Icons.schedule),
            label: Text('When watched: ' +
                draft.whenWatched.toLocal().toString().substring(0, 16)),
          ),
          FilterChip(
            selected: draft.isRepeat,
            label: const Text('Repeat / Rewatch'),
            onSelected: (value) => widget.drafts.update(
              draft.titleId, (entry) => entry.isRepeat = value),
          ),
        ]),
        Row(children: [
          const Text('Runtime (min)'),
          const SizedBox(width: 8),
          IconButton(
            onPressed: draft.runtimeMinutes == 0 ? null
              : () => widget.drafts.update(draft.titleId,
                  (entry) => entry.runtimeMinutes--),
            icon: const Icon(Icons.remove_circle_outline),
          ),
          Text(draft.runtimeMinutes.toString()),
          IconButton(
            onPressed: () => widget.drafts.update(draft.titleId,
                (entry) => entry.runtimeMinutes++),
            icon: const Icon(Icons.add_circle_outline),
          ),
        ]),
        TextFormField(
          key: ValueKey('r2-note-' + title.id),
          initialValue: draft.note,
          decoration: const InputDecoration(
            hintText: 'Optional session note',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          maxLines: 2,
          onChanged: (value) => widget.drafts.setNote(draft.titleId, value),
        ),
        const SizedBox(height: 7),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          IconButton(
            tooltip: 'Move up', onPressed: () => widget.drafts.move(title.id, -1),
            icon: const Icon(Icons.arrow_upward)),
          IconButton(
            tooltip: 'Move down', onPressed: () => widget.drafts.move(title.id, 1),
            icon: const Icon(Icons.arrow_downward)),
          TextButton.icon(
            onPressed: () => widget.drafts.remove(title.id),
            icon: const Icon(Icons.close), label: const Text('Remove')),
        ]),
      ],
    ), subtitle: 'Advanced Logging · local draft');
  }

  Future<void> _review(MediaFlowCatalog catalog) async {
    final byId = {for (final item in catalog.library) item.id: item};
    final valid = widget.drafts.entries.where((entry) =>
      byId.containsKey(entry.titleId) && entry.quantity > 0).toList();
    if (valid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Select at least one unit in your draft first.'),
      ));
      return;
    }
    await showModalBottomSheet<void>(context: context, isScrollControlled: true,
      showDragHandle: true,
      builder: (sheet) => SafeArea(child: FractionallySizedBox(
        heightFactor: .8,
        child: Padding(padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Review Advanced Logging draft',
              style: Theme.of(sheet).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text('This is a local preview, not a completed log. '
              'Live History, XP, task completion and Supabase saves '
              'remain disabled pending source-parity and sync validation.'),
            const SizedBox(height: 12),
            Expanded(child: ListView(children: [
              for (final entry in valid)
                ListTile(
                  title: Text(byId[entry.titleId]!.title),
                  subtitle: Text(entry.quantity.toString() +
                    ' units · ' + entry.method.name),
                ),
              const SizedBox(height: 8),
              SelectableText(
                const JsonEncoder.withIndent('  ').convert(
                  valid.map((entry) => entry.toLocalReview()).toList()),
                style: const TextStyle(fontSize: 11),
              ),
            ])),
            FilledButton(
              onPressed: () => Navigator.pop(sheet),
              child: const Text('Return to draft'),
            ),
          ]),
        ),
      )));
  }

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context, builder: (dialog) => AlertDialog(
        title: const Text('Clear draft titles?'),
        content: const Text('This discards only the current local Advanced '
            'Logging draft. The website and your account are unchanged.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Keep titles')),
          FilledButton(onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Clear draft')),
        ],
      ));
    if (confirmed == true) widget.drafts.clear();
  }

  Widget _session(MediaFlowCatalog catalog) {
    final titles = {for (final title in catalog.library) title.id: title};
    final entries = widget.drafts.entries;
    return _panel('Session editor', Column(
      crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 9, runSpacing: 7, children: [
          Chip(label: Text(entries.length.toString() + ' titles')),
          Chip(label: Text(widget.drafts.totalUnits.toString() + ' units')),
          ActionChip(
            label: Text('Keep titles: ' + (widget.drafts.keepTitles ? 'ON' : 'OFF')),
            onPressed: () => widget.drafts.setKeepTitles(!widget.drafts.keepTitles),
          ),
          ActionChip(label: const Text('Clear titles'),
            onPressed: entries.isEmpty ? null : _clear),
        ]),
        const SizedBox(height: 9),
        if (entries.isEmpty)
          const Padding(padding: EdgeInsets.all(20),
            child: Text('Add a recommended title or choose one from your Library '
                'to begin your Advanced Logging draft.')),
        for (final entry in entries)
          if (titles[entry.titleId] != null)
            _editor(entry, titles[entry.titleId]!, catalog)
          else _panel('Unavailable title', Text('Title ID ' + entry.titleId +
                  ' is no longer in the loaded account snapshot. No changes were made.')),
        if (entries.isNotEmpty)
          FilledButton.icon(
            key: const Key('r2-review-draft'),
            onPressed: () => _review(catalog),
            icon: const Icon(Icons.fact_check_outlined),
            label: const Text('Review draft · no cloud write'),
          ),
      ],
    ), subtitle: 'Per Unit · Last Watched/Read Unit · Amount Consumed');
  }

  Widget _loaded(MediaFlowCatalog catalog) {
    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= 950;
      final left = Column(children: [_recommendation(catalog), _picker(catalog)]);
      final right = _session(catalog);
      return ListView(children: [
        Wrap(alignment: WrapAlignment.spaceBetween, spacing: 8, runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text('Logging Workspace', style: Theme.of(context).textTheme.headlineMedium),
          OutlinedButton.icon(onPressed: _reload,
            icon: const Icon(Icons.refresh), label: const Text('Refresh Library')),
        ]),
        const SizedBox(height: 4),
        Text('Native R2 · based on MediaFlow v504 · Advanced Logging first',
          style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 12),
        Card(color: Theme.of(context).colorScheme.secondaryContainer,
          child: const Padding(padding: EdgeInsets.all(13),
            child: Text('SAFE DRAFT MODE — Your real Library is read-only. '
              'Unit selection, timestamps and quantities are editable locally, '
              'but Confirm Logging and automatic synchronization are not enabled.'))),
        const SizedBox(height: 14),
        if (wide) Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(flex: 4, child: left),
          const SizedBox(width: 14),
          Expanded(flex: 6, child: right),
        ]) else ...[left, right],
        if (widget.openLegacyBrowser != null)
          TextButton.icon(
            onPressed: widget.openLegacyBrowser,
            icon: const Icon(Icons.list_alt_outlined),
            label: const Text('Open previous Logging Library browser')),
        const SizedBox(height: 25),
      ]);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.drafts,
      builder: (context, _) => FutureBuilder<MediaFlowCatalog>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Column(
            mainAxisAlignment: MainAxisAlignment.center, children: [
              const Text('Could not load your MediaFlow Library.'),
              const SizedBox(height: 8),
              OutlinedButton(onPressed: _reload, child: const Text('Retry')),
            ]));
          if (!snapshot.hasData) return const Center(
            child: CircularProgressIndicator());
          return _loaded(snapshot.data!);
        },
      ),
    );
  }
}
