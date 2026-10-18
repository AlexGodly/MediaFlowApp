// ignore_for_file: prefer_interpolation_to_compose_strings
import 'dart:async';
import 'package:flutter/material.dart';
import '../../data/mediaflow_models.dart';
import 'r2_advanced_logging_drafts.dart';

/// Native Library picker for Advanced Logging (website v505 reference).
/// UI choices are local; adding titles changes only the in-memory log draft.
enum R3PickerView { list, compact, cards, covers, coversTitles }
enum R3AddedFilter { notAdded, all, alreadyAdded }

class R3LoggingLibraryPicker extends StatefulWidget {
  const R3LoggingLibraryPicker({
    super.key, required this.catalog, required this.drafts,
  });
  final MediaFlowCatalog catalog;
  final R2AdvancedLoggingDrafts drafts;

  @override
  State<R3LoggingLibraryPicker> createState() => _R3LoggingLibraryPickerState();
}

class _R3LoggingLibraryPickerState extends State<R3LoggingLibraryPicker> {
  final search = TextEditingController();
  Timer? debounce;
  final Set<String> chosen = {};
  String query = '', category = 'all', status = 'all', priority = 'all';
  String sort = 'priority-desc';
  R3AddedFilter added = R3AddedFilter.notAdded;
  R3PickerView mode = R3PickerView.list;
  bool toolsOpen = false;
  int page = 0, perPage = 12;
  double coverHeight = 75;

  @override
  void dispose() {
    debounce?.cancel();
    search.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant R3LoggingLibraryPicker old) {
    super.didUpdateWidget(old);
    if (!identical(old.catalog, widget.catalog)) {
      chosen.clear();
      page = 0;
      if (!widget.catalog.categories.any((cat) => cat.id == category)) {
        category = 'all';
      }
    }
  }

  bool _added(MediaFlowTitle title) => widget.drafts.contains(title.id);

  Map<String, int> get _idCounts {
    final counts = <String, int>{};
    for (final title in widget.catalog.library) {
      counts[title.id] = (counts[title.id] ?? 0) + 1;
    }
    return counts;
  }

  int _priority(String value) =>
      const {'low': 0, 'medium': 1, 'high': 2}[value] ?? 1;

  List<MediaFlowTitle> get _results {
    final word = query.toLowerCase().trim();
    final result = widget.catalog.library.where((title) {
      if (title.id.isEmpty) return false;
      if (word.isNotEmpty && !title.searchText.contains(word) &&
          !title.id.toLowerCase().contains(word)) return false;
      if (category != 'all' && title.categoryId != category) return false;
      if (status != 'all' && title.status != status) return false;
      if (priority != 'all' && title.priority != priority) return false;
      if (added == R3AddedFilter.notAdded && _added(title)) return false;
      if (added == R3AddedFilter.alreadyAdded && !_added(title)) return false;
      return true;
    }).toList();
    // A stable secondary title comparison is needed for deterministic paging.
    result.sort((a, b) {
      final dir = sort.endsWith('-asc') ? 1 : -1;
      if (sort.startsWith('title-')) {
        return a.title.toLowerCase().compareTo(b.title.toLowerCase()) * dir;
      }
      int n = 0;
      if (sort.startsWith('priority-')) {
        n = _priority(a.priority).compareTo(_priority(b.priority));
      } else if (sort.startsWith('rating-')) {
        n = (a.rating ?? 0).compareTo(b.rating ?? 0);
      } else if (sort.startsWith('progress-')) {
        n = a.progress.compareTo(b.progress);
      } else if (sort.startsWith('total-')) {
        n = (a.total ?? 0).compareTo(b.total ?? 0);
      } else if (sort.startsWith('added-')) {
        n = (a.addedAt ?? DateTime(1970))
            .compareTo(b.addedAt ?? DateTime(1970));
      }
      return n == 0 ? a.title.toLowerCase().compareTo(b.title.toLowerCase())
          : n * dir;
    });
    return result;
  }

  void _refresh() => setState(() => page = 0);

  void _addTitle(MediaFlowTitle title, Map<String, int> counts) {
    if (counts[title.id] != 1) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Ambiguous or duplicate Library ID. Cannot select safely.'),
      ));
      return;
    }
    widget.drafts.add(title);
    setState(() => chosen.remove(title.id));
  }

  void _addSelected(List<MediaFlowTitle> titles, Map<String, int> counts) {
    final chosenTitles = titles.where((title) =>
        chosen.contains(title.id) && counts[title.id] == 1).toList();
    for (final title in chosenTitles) {
      widget.drafts.add(title);
    }
    setState(() {
      for (final title in chosenTitles) {
        chosen.remove(title.id);
      }
    });
    if (chosenTitles.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Added ${chosenTitles.length} titles to Advanced Logging.'),
      ));
    }
  }

  Widget _dropdown<T>(String label, T value,
      List<DropdownMenuItem<T>> values, ValueChanged<T> change) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label,
        border: const OutlineInputBorder(), isDense: true),
      items: values,
      onChanged: (v) { if (v != null) change(v); },
    );
  }

  Widget _cover(MediaFlowTitle title, double height) {
    final cat = widget.catalog.categoryById[title.categoryId];
    final raw = title.coverUrl.trim();
    final uri = Uri.tryParse(raw);
    final safe = uri != null && (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty && uri.userInfo.isEmpty;
    final categoryArt = cat?.iconUrl ?? '';
    final iconUri = Uri.tryParse(categoryArt);
    final safeIcon = iconUri != null &&
        (iconUri.scheme == 'http' || iconUri.scheme == 'https') &&
        iconUri.host.isNotEmpty && iconUri.userInfo.isEmpty;
    Widget fallback() => Center(child: safeIcon
        ? Image.network(categoryArt, width: height * .46,
            height: height * .46, fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => Text(cat?.icon ?? '◈',
              style: TextStyle(fontSize: height * .4)))
        : Text(cat?.icon ?? '◈', style: TextStyle(fontSize: height * .4)));
    return ClipRRect(borderRadius: BorderRadius.circular(9),
      child: Container(
        width: height * .72, height: height,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: safe ? Image.network(raw, fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => fallback()) : fallback(),
      ),
    );
  }

  String _subtitle(MediaFlowTitle title) {
    final categoryName = widget.catalog.categoryById[title.categoryId]?.name
        ?? 'Category';
    return '$categoryName · ${title.status} · ${title.priority} · '
        '${title.progress.floor()}/${title.total?.floor() ?? "?"}';
  }

  Widget _item(MediaFlowTitle title, Map<String, int> counts) {
    final duplicate = counts[title.id] != 1;
    final isAdded = _added(title);
    final isSelected = chosen.contains(title.id);
    final enabled = !duplicate && !isAdded;
    final height = mode == R3PickerView.compact ? coverHeight * .65 : coverHeight;
    if (mode == R3PickerView.covers || mode == R3PickerView.coversTitles ||
        mode == R3PickerView.cards) {
      return Card(
        margin: const EdgeInsets.all(2),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('r3-cover-item-${title.id}'),
          onTap: enabled ? () => setState(() =>
              isSelected ? chosen.remove(title.id) : chosen.add(title.id)) : null,
          child: Padding(padding: const EdgeInsets.all(8),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Stack(alignment: Alignment.topRight, children: [
                _cover(title, coverHeight * 1.45),
                if (isAdded) const Icon(Icons.check_circle,
                    color: Colors.green, size: 23)
                else Checkbox(
                  value: isSelected,
                  onChanged: enabled ? (v) => setState(() =>
                    v == true ? chosen.add(title.id) : chosen.remove(title.id))
                    : null,
                ),
              ]),
              if (mode != R3PickerView.covers) ...[
                const SizedBox(height: 6),
                Text(title.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12,
                    fontWeight: FontWeight.w600)),
              ],
              if (mode == R3PickerView.cards) ...[
                const SizedBox(height: 5),
                Text(_subtitle(title), maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall),
              ],
              if (mode == R3PickerView.cards)
                IconButton(
                  icon: Icon(isAdded ? Icons.check_circle : Icons.add_circle),
                  tooltip: 'Add title to Logging',
                  onPressed: enabled ? () => _addTitle(title, counts) : null,
                ),
            ]),
          ),
        ),
      );
    }
    return ListTile(
      key: ValueKey('r3-picker-title-${title.id}'),
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      leading: Row(mainAxisSize: MainAxisSize.min, children: [
        Checkbox(
          value: isSelected || isAdded,
          onChanged: enabled ? (v) => setState(() =>
            v == true ? chosen.add(title.id) : chosen.remove(title.id)) : null,
        ),
        _cover(title, height),
      ]),
      title: Text(title.title, maxLines: mode == R3PickerView.compact ? 1 : 2,
          overflow: TextOverflow.ellipsis),
      subtitle: mode == R3PickerView.compact ? null
          : Text(duplicate ? 'Duplicate ID · blocked' : _subtitle(title),
              maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: IconButton(
        icon: Icon(isAdded ? Icons.check_circle : Icons.add_circle_outline),
        onPressed: enabled ? () => _addTitle(title, counts) : null,
        tooltip: isAdded ? 'Already added' : 'Add to Logging',
      ),
      onTap: enabled ? () => setState(() =>
        isSelected ? chosen.remove(title.id) : chosen.add(title.id)) : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;
    final pages = results.isEmpty ? 1 : (results.length + perPage - 1) ~/ perPage;
    final current = page.clamp(0, pages - 1).toInt();
    final visible = results.skip(current * perPage).take(perPage).toList();
    final countById = _idCounts;
    final eligible = visible.where((title) =>
      !widget.drafts.contains(title.id) && countById[title.id] == 1).toList();
    final allVisibleSelected = eligible.isNotEmpty &&
        eligible.every((title) => chosen.contains(title.id));
    return Card(
      key: const Key('r3-logging-library-picker'),
      child: Padding(padding: const EdgeInsets.all(15),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Find & add Library titles',
            style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text('Same Library, flexible app-first controls · '
            '${results.length} matches',
            style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 13),
          TextField(
            key: const Key('r3-picker-search'),
            controller: search,
            decoration: const InputDecoration(
              border: OutlineInputBorder(), isDense: true,
              hintText: 'Search title, tag or Library ID',
              prefixIcon: Icon(Icons.search)),
            onChanged: (value) {
              debounce?.cancel();
              debounce = Timer(const Duration(milliseconds: 130), () {
                if (mounted) setState(() {
                  query = value;
                  page = 0;
                });
              });
            },
          ),
          const SizedBox(height: 9),
          SingleChildScrollView(scrollDirection: Axis.horizontal,
            child: SegmentedButton<R3AddedFilter>(
            key: const Key('r3-picker-added-filter'),
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: R3AddedFilter.notAdded,
                  label: Text('Not added')),
              ButtonSegment(value: R3AddedFilter.all, label: Text('Show all')),
              ButtonSegment(value: R3AddedFilter.alreadyAdded,
                  label: Text('Added')),
            ],
            selected: {added},
            onSelectionChanged: (v) => setState(() {
              added = v.first; page = 0;
            }),
          )),
          const SizedBox(height: 10),
          Wrap(alignment: WrapAlignment.spaceBetween,
            spacing: 7, runSpacing: 6,
            children: [
              TextButton.icon(
                key: const Key('r3-picker-tools'),
                onPressed: () => setState(() => toolsOpen = !toolsOpen),
                icon: const Icon(Icons.tune),
                label: Text(toolsOpen ? 'Hide tools & filters' : 'Tools & filters'),
              ),
              OutlinedButton.icon(
                onPressed: chosen.isEmpty ? null
                    : () => _addSelected(widget.catalog.library, countById),
                icon: const Icon(Icons.playlist_add),
                label: Text('Add selected (${chosen.length})'),
              ),
            ]),
          if (toolsOpen) ...[
            const SizedBox(height: 10),
            _dropdown<String>('Category', category, [
              const DropdownMenuItem(value: 'all', child: Text('All categories')),
              for (final cat in widget.catalog.categories)
                DropdownMenuItem(value: cat.id, child: Text(cat.name)),
            ], (value) => setState(() {category = value; page = 0;})),
            const SizedBox(height: 8),
            _dropdown<String>('Status', status, [
              const DropdownMenuItem(value: 'all', child: Text('All statuses')),
              for (final x in const ['planned','active','paused','completed','dropped'])
                DropdownMenuItem(value: x, child: Text(x)),
            ], (value) => setState(() {status = value; page = 0;})),
            const SizedBox(height: 8),
            _dropdown<String>('Priority', priority, [
              const DropdownMenuItem(value: 'all', child: Text('All priorities')),
              for (final x in const ['high','medium','low'])
                DropdownMenuItem(value: x, child: Text(x)),
            ], (value) => setState(() {priority = value; page = 0;})),
            const SizedBox(height: 8),
            _dropdown<String>('Sort titles', sort, const [
              DropdownMenuItem(value: 'priority-desc', child: Text('Priority · high first')),
              DropdownMenuItem(value: 'priority-asc', child: Text('Priority · low first')),
              DropdownMenuItem(value: 'title-asc', child: Text('Alphabetical · A-Z')),
              DropdownMenuItem(value: 'title-desc', child: Text('Alphabetical · Z-A')),
              DropdownMenuItem(value: 'rating-desc', child: Text('Rating · highest')),
              DropdownMenuItem(value: 'rating-asc', child: Text('Rating · lowest')),
              DropdownMenuItem(value: 'progress-desc', child: Text('Progress · most')),
              DropdownMenuItem(value: 'progress-asc', child: Text('Progress · least')),
              DropdownMenuItem(value: 'total-desc', child: Text('Total units · highest')),
              DropdownMenuItem(value: 'total-asc', child: Text('Total units · lowest')),
              DropdownMenuItem(value: 'added-desc', child: Text('Recently added to Library')),
              DropdownMenuItem(value: 'added-asc', child: Text('Oldest added to Library')),
            ], (value) => setState(() {sort = value; page = 0;})),
            const SizedBox(height: 10),
            Text('Cover height: ${coverHeight.round()}px'),
            Slider(
              key: const Key('r3-picker-cover-size'),
              value: coverHeight, min: 48, max: 128, divisions: 20,
              onChanged: (value) => setState(() => coverHeight = value),
            ),
            Row(children: [
              const Text('Per page'),
              const SizedBox(width: 12),
              DropdownButton<int>(value: perPage, items: [
                for (final n in const [12, 24, 48])
                  DropdownMenuItem(value: n, child: Text('$n')),
              ], onChanged: (n) => setState(() {
                perPage = n ?? perPage; page = 0;
              })),
              const Spacer(),
              TextButton(
                onPressed: () => setState(() {
                  category = 'all'; status = 'all'; priority = 'all';
                  sort = 'priority-desc'; page = 0; coverHeight = 75;
                }),
                child: const Text('Reset filters'),
              ),
            ]),
          ],
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<R3PickerView>(
              key: const Key('r3-picker-display-mode'),
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: R3PickerView.list, label: Text('List')),
                ButtonSegment(value: R3PickerView.compact, label: Text('Compact')),
                ButtonSegment(value: R3PickerView.cards, label: Text('Cards')),
                ButtonSegment(value: R3PickerView.covers, label: Text('Covers')),
                ButtonSegment(value: R3PickerView.coversTitles,
                  label: Text('Covers + titles')),
              ],
              selected: {mode},
              onSelectionChanged: (v) => setState(() => mode = v.first),
            ),
          ),
          const SizedBox(height: 10),
          Row(children: [
            TextButton(
              onPressed: eligible.isEmpty ? null : () => setState(() {
                if (allVisibleSelected) {
                  for (final title in eligible) { chosen.remove(title.id); }
                } else {
                  for (final title in eligible) { chosen.add(title.id); }
                }
              }),
              child: Text(allVisibleSelected ? 'Deselect visible' : 'Select visible'),
            ),
            TextButton(
              onPressed: chosen.isEmpty ? null : () => setState(chosen.clear),
              child: const Text('Clear selection'),
            ),
          ]),
          if (visible.isEmpty) const Padding(
            padding: EdgeInsets.all(20), child: Text('No matching titles.'))
          else if (mode == R3PickerView.list || mode == R3PickerView.compact)
            for (final title in visible) _item(title, countById)
          else LayoutBuilder(builder: (context, box) {
            final cols = (box.maxWidth / (coverHeight * 1.55 + 35))
                .floor().clamp(2, 5).toInt();
            // Height grows for Cards, preserving readable captions.
            final ratio = mode == R3PickerView.cards ? .58
                : mode == R3PickerView.coversTitles ? .69 : .84;
            return GridView.builder(
              shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols, childAspectRatio: ratio,
                crossAxisSpacing: 6, mainAxisSpacing: 8),
              itemCount: visible.length,
              itemBuilder: (context, i) => _item(visible[i], countById),
            );
          }),
          if (pages > 1) Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              IconButton(
                onPressed: current == 0 ? null : () => setState(() => page = current - 1),
                icon: const Icon(Icons.chevron_left), tooltip: 'Previous page'),
              Text('Page ${current + 1} / $pages'),
              IconButton(
                onPressed: current == pages - 1 ? null
                    : () => setState(() => page = current + 1),
                icon: const Icon(Icons.chevron_right), tooltip: 'Next page'),
            ]),
        ]),
      ),
    );
  }
}
