// ignore_for_file: prefer_interpolation_to_compose_strings, curly_braces_in_flow_control_structures
import 'dart:convert';
import 'package:flutter/material.dart';
import '../../data/mediaflow_library_repository.dart';
import '../../data/mediaflow_models.dart';
import 'r2_advanced_logging_drafts.dart';
import 'r3_logging_library_picker.dart';
import 'native_logging_recommends_card.dart';

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
  final Map<String, int> _unitPages = {};
  String _draftSort = 'custom';
  bool _draftDescending = false;

  @override
  void initState() {
    super.initState();
    _future = widget.repository.load();
  }

  @override
  void dispose() {
    super.dispose();
  }

  void _reload() => setState(() {
    _future = widget.repository.reload();
  });

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

  Widget _select<T>(String label, T value, List<DropdownMenuItem<T>> options,
      ValueChanged<T> changed) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: DropdownButtonFormField<T>(
      initialValue: value,
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

  Future<bool> _confirmDetailedChange(R2DraftTitle draft,
      MediaFlowTitle title, int quantity) async {
    if (!draft.willReplaceDetailedUnits(title, quantity)) return true;
    final approved = await showDialog<bool>(context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Replace detailed unit selection?'),
        content: const Text('These units contain a nonconsecutive selection, '
          'different timestamps, or custom runtimes. Changing the quantity '
          'will rebuild the current season’s unit list. Units in other '
          'seasons remain untouched. Continue?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Keep original units')),
          FilledButton(onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Replace units')),
        ],
      ),
    );
    return approved == true;
  }

  Future<void> _applyQuantity(R2DraftTitle draft, MediaFlowTitle title,
      int value, {required bool last}) async {
    final quantity = last ? value - draft.startFor(title) : value;
    if (quantity < 0 || quantity > draft.allowedQuantity(title)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Value must be between ${last ? draft.startFor(title) : 0} '
          'and ${(last ? draft.startFor(title) : 0) + draft.allowedQuantity(title)}.'),
      ));
      return;
    }
    if (quantity != draft.currentUnits.length &&
        !await _confirmDetailedChange(draft, title, quantity)) return;
    widget.drafts.update(draft.titleId, (entry) {
      if (last) { entry.setLastUnit(title, value); }
      else { entry.setAmount(title, value); }
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
    if (result != null && mounted) {
      await _applyQuantity(entry, title, result, last: last);
    }
  }

  Widget _stepper(R2DraftTitle draft, MediaFlowTitle title) {
    final last = draft.method == R2LoggingMethod.lastUnit;
    final base = draft.startFor(title);
    final number = draft.currentUnits.length + (last ? base : 0);
    final lower = last ? base : 0;
    final upper = draft.allowedQuantity(title) + (last ? base : 0);
    return Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 7, children: [
      OutlinedButton.icon(
        key: ValueKey('r2-minus-' + draft.titleId),
        onPressed: number <= lower ? null
            : () => _applyQuantity(draft, title, number - 1, last: last),
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
        onPressed: number >= upper ? null
            : () => _applyQuantity(draft, title, number + 1, last: last),
        icon: const Icon(Icons.add, size: 16),
        label: const Text('More'),
      ),
    ]);
  }

  Future<void> _editUnitRuntime(R2DraftTitle draft, int unit) async {
    final field = TextEditingController(
        text: draft.secondsForUnit(unit).toString());
    final result = await showDialog<int>(context: context,
      builder: (dialog) => AlertDialog(
        title: Text('Runtime for unit $unit'),
        content: TextField(
          controller: field, keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Seconds', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog),
            child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialog, int.tryParse(field.text)),
            child: const Text('Save')),
        ],
      ));
    field.dispose();
    if (result != null && mounted) {
      widget.drafts.update(draft.titleId,
        (entry) => entry.setUnitSeconds(unit, result));
    }
  }

  Widget _units(R2DraftTitle draft, MediaFlowTitle title) {
    final start = draft.startFor(title);
    final cap = draft.allowedQuantity(title);
    if (cap == 0) return const Text('No units available in this season.');
    final pageKey = '${draft.titleId}:${draft.seasonKey}';
    final pages = (cap + 29) ~/ 30;
    final page = (_unitPages[pageKey] ?? 0).clamp(0, pages - 1).toInt();
    final chosen = draft.currentUnits;
    final firstOffset = page * 30 + 1;
    final lastOffset = (firstOffset + 29).clamp(1, cap).toInt();
    final selected = chosen.keys.toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 6, runSpacing: 5, children: [
        OutlinedButton.icon(
          onPressed: draft.quantityForSeason(draft.seasonKey) >= cap ? null
              : () {
                  final next = chosen.isEmpty ? start + 1
                      : (chosen.lastKey() ?? start) + 1;
                  if (next > start + cap) return;
                  widget.drafts.update(draft.titleId,
                    (entry) => entry.toggleUnit(title, next));
                  setState(() => _unitPages[pageKey] =
                      ((next - start - 1) ~/ 30));
                },
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Next unit'),
        ),
        OutlinedButton.icon(
          onPressed: selected.isEmpty ? null : () => widget.drafts.update(
            draft.titleId, (entry) => entry.toggleUnit(title, selected.last)),
          icon: const Icon(Icons.remove, size: 16),
          label: const Text('Remove last'),
        ),
        TextButton(
          onPressed: () => _applyQuantity(draft, title, 0, last: false),
          child: const Text('Clear season'),
        ),
      ]),
      const SizedBox(height: 6),
      Text('Select individual units · page ${page + 1} of $pages'),
      Wrap(spacing: 7, runSpacing: 6, children: [
        for (var offset = firstOffset; offset <= lastOffset; offset++)
          InputChip(
            key: ValueKey('r2-unit-${draft.titleId}-${start + offset}'),
            selected: chosen.containsKey(start + offset),
            label: Text((start + offset).toString()),
            onPressed: () => widget.drafts.update(draft.titleId,
              (entry) => entry.toggleUnit(title, start + offset)),
            onDeleted: chosen.containsKey(start + offset)
                ? () => _chooseTime(draft, unit: start + offset) : null,
            deleteIcon: const Icon(Icons.schedule, size: 16),
            deleteButtonTooltipMessage: 'Edit unit timestamp',
          ),
      ]),
      if (pages > 1) Row(children: [
        IconButton(
          tooltip: 'Previous 30 units',
          onPressed: page == 0 ? null
              : () => setState(() => _unitPages[pageKey] = page - 1),
          icon: const Icon(Icons.chevron_left),
        ),
        Expanded(child: Text('Units ${start + firstOffset}–${start + lastOffset}',
          textAlign: TextAlign.center)),
        IconButton(
          tooltip: 'Next 30 units',
          onPressed: page >= pages - 1 ? null
              : () => setState(() => _unitPages[pageKey] = page + 1),
          icon: const Icon(Icons.chevron_right),
        ),
      ]),
      if (selected.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text('Selected unit details',
          style: Theme.of(context).textTheme.titleSmall),
        for (final number in selected.reversed.take(5))
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text('Unit $number · ${draft.secondsForUnit(number)} seconds'),
            subtitle: Text(chosen[number]!.toLocal().toString()),
            trailing: Wrap(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                tooltip: 'Edit unit runtime',
                icon: const Icon(Icons.timer_outlined),
                onPressed: () => _editUnitRuntime(draft, number),
              ),
              IconButton(
                tooltip: 'Edit logged-at date',
                icon: const Icon(Icons.event_outlined),
                onPressed: () => _chooseTime(draft, unit: number),
              ),
            ]),
          ),
        if (selected.length > 5)
          Text('Showing 5 newest selections of ${selected.length}. '
            'All selected units remain in your draft.'),
      ],
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
      final left = Column(children: [
        NativeLoggingRecommendsCard(
          key: const Key('beta5-recommendations'),
          catalog: catalog,
          selectedIds: widget.drafts.entries.map((draft) => draft.titleId).toSet(),
          onUse: widget.drafts.add,
        ),
        R3LoggingLibraryPicker(
          key: const Key('beta5-library-picker'),
          catalog: catalog,
          drafts: widget.drafts,
        ),
      ]);
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
