// ignore_for_file: prefer_interpolation_to_compose_strings
import 'dart:async';
import 'package:flutter/material.dart';

import '../../data/mediaflow_library_repository.dart';
import '../../data/mediaflow_models.dart';
import 'history_filter.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, required this.repository});
  final MediaFlowLibraryRepository repository;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late Future<MediaFlowCatalog> _future;
  final search = TextEditingController();
  Timer? debounce;
  String query = '', categoryId = '', status = '';
  MediaFlowHistoryRange range = MediaFlowHistoryRange.all;
  int page = 0, pageSize = 25;

  @override
  void initState() {
    super.initState();
    _future = widget.repository.load();
  }

  @override
  void dispose() {
    debounce?.cancel();
    search.dispose();
    super.dispose();
  }

  void resetFilters() => setState(() => page = 0);
  void refresh() => setState(() {
    page = 0;
    _future = widget.repository.reload();
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<MediaFlowCatalog>(future: _future, builder: (context, data) {
      if (data.connectionState != ConnectionState.done) {
        return const Center(child: CircularProgressIndicator());
      }
      if (data.hasError) {
        return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Could not read History. No data was modified.'),
          FilledButton(onPressed: refresh, child: const Text('Retry')),
        ]));
      }
      final catalog = data.requireData;
      final items = MediaFlowHistoryFilter(
        categoryId: categoryId, status: status, search: query, range: range,
      ).apply(catalog.sessions);
      final pages = items.isEmpty ? 1 : (items.length + pageSize - 1) ~/ pageSize;
      final current = page.clamp(0, pages - 1);
      final start = current * pageSize;
      final visible = items.skip(start).take(pageSize).toList(growable: false);
      return LayoutBuilder(builder: (context, constraints) {
        final itemWidth = constraints.maxWidth >= 700
            ? (constraints.maxWidth - 16) / 3
            : (constraints.maxWidth - 8) / 2;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('History', style: Theme.of(context).textTheme.headlineMedium),
                Text('Your completed consumption records · Read-only',
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            )),
            IconButton(onPressed: refresh, tooltip: 'Refresh History',
                icon: const Icon(Icons.refresh)),
          ]),
          const SizedBox(height: 10),
          TextField(
            controller: search,
            decoration: const InputDecoration(
              labelText: 'Search logged titles and notes',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(), isDense: true,
            ),
            onChanged: (text) {
              debounce?.cancel();
              debounce = Timer(const Duration(milliseconds: 220), () {
                if (!mounted) return;
                query = text;
                resetFilters();
              });
            },
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _select<String>(itemWidth, 'Category', categoryId, [
              const DropdownMenuItem(value: '', child: Text('All categories')),
              for (final category in catalog.categories)
                DropdownMenuItem(value: category.id,
                    child: Text(category.name, overflow: TextOverflow.ellipsis)),
            ], (v) { categoryId = v; resetFilters(); }),
            _select<String>(itemWidth, 'Result', status, [
              const DropdownMenuItem(value: '', child: Text('All results')),
              for (final value in ['logged','complete','partial','over','skipped'])
                DropdownMenuItem(value: value, child: Text(_capital(value))),
            ], (v) { status = v; resetFilters(); }),
            _select<MediaFlowHistoryRange>(itemWidth, 'Date', range, const [
              DropdownMenuItem(value: MediaFlowHistoryRange.all, child: Text('All time')),
              DropdownMenuItem(value: MediaFlowHistoryRange.today, child: Text('Today')),
              DropdownMenuItem(value: MediaFlowHistoryRange.sevenDays, child: Text('Last 7 days')),
              DropdownMenuItem(value: MediaFlowHistoryRange.thirtyDays, child: Text('Last 30 days')),
            ], (v) { range = v; resetFilters(); }),
          ]),
          const SizedBox(height: 12),
          Text('Showing ${items.isEmpty ? 0 : start + 1}–${start + visible.length}'
              ' of ${items.length} sessions', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          Expanded(child: visible.isEmpty
            ? Center(child: Text(catalog.sessions.isEmpty
                ? 'No consumption sessions yet.'
                : 'No sessions match the current filters.'))
            : ListView.builder(
                itemCount: visible.length,
                itemBuilder: (context, index) => _card(context, visible[index],
                  catalog.categoryById[visible[index].categoryId]),
              )),
          Row(children: [
            IconButton(
              tooltip: 'Previous History page',
              onPressed: current == 0 ? null : () => setState(() => page = current - 1),
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(child: Text('Page ${current + 1} of $pages',
                textAlign: TextAlign.center)),
            IconButton(
              tooltip: 'Next History page',
              onPressed: current + 1 >= pages ? null
                  : () => setState(() => page = current + 1),
              icon: const Icon(Icons.chevron_right),
            ),
            DropdownButton<int>(
              value: pageSize, isDense: true,
              items: const [
                DropdownMenuItem(value: 25, child: Text('25')),
                DropdownMenuItem(value: 50, child: Text('50')),
                DropdownMenuItem(value: 100, child: Text('100')),
              ],
              onChanged: (next) => setState(() {
                pageSize = next ?? 25;
                page = 0;
              }),
            ),
          ]),
        ]);
      });
    });
  }

  Widget _select<T>(double width, String label, T value,
      List<DropdownMenuItem<T>> items, ValueChanged<T> change) {
    return SizedBox(width: width, child: InputDecorator(
      decoration: InputDecoration(
        labelText: label, border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        isDense: true,
      ),
      child: DropdownButtonHideUnderline(child: DropdownButton<T>(
        value: value, isExpanded: true, isDense: true, items: items,
        onChanged: (next) { if (next != null) change(next); },
      )),
    ));
  }

  Widget _card(BuildContext context,
      MediaFlowSession session, MediaFlowCategory? category) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _details(context, session, category),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              CircleAvatar(radius: 18, child: Text(category?.icon ?? '◈')),
              const SizedBox(width: 10),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(category?.name ?? session.categoryId,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text(_date(session),
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              )),
              Chip(label: Text(_capital(session.status))),
            ]),
            const SizedBox(height: 6),
            Text('${_number(session.actualAmount)} ${session.unit} · '
              '${_number(session.minutes)} min · '
              '+${_number(session.xp)} stored XP'),
            if (session.titles.isNotEmpty)
              Text(session.titles.map((entry) =>
                '${entry.title} ×${_number(entry.quantity)}').join(' · '),
                maxLines: 2, overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall),
            if (session.note.isNotEmpty)
              Text(session.note, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
      ),
    );
  }

  void _details(BuildContext context,
      MediaFlowSession session, MediaFlowCategory? category) {
    showModalBottomSheet<void>(
      context: context, showDragHandle: true, isScrollControlled: true,
      builder: (sheet) => SafeArea(
        child: FractionallySizedBox(
          heightFactor: 0.7,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),
            children: [
              Text(category?.name ?? 'Session',
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(_date(session)),
              Text('Result: ${_capital(session.status)}'),
              Text('Consumed: ${_number(session.actualAmount)} ${session.unit}'),
              Text('Duration: ${_number(session.minutes)} minutes'),
              Text('Stored session XP: ${_number(session.xp)}'),
              if (session.note.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('Note', style: Theme.of(context).textTheme.titleMedium),
                Text(session.note),
              ],
              if (session.titles.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('Logged titles', style: Theme.of(context).textTheme.titleMedium),
                for (final entry in session.titles)
                  ListTile(title: Text(entry.title),
                    trailing: Text('×${_number(entry.quantity)}')),
              ],
              const SizedBox(height: 16),
              const Text('Read-only: native History editing is not enabled yet.'),
            ],
          ),
        ),
      ),
    );
  }
}

String _capital(String value) => value.isEmpty ? 'Unknown'
    : value[0].toUpperCase() + value.substring(1);

String _number(double value) => value == value.roundToDouble()
    ? value.toInt().toString() : value.toStringAsFixed(1);

String _date(MediaFlowSession session) {
  final local = session.timestamp?.toLocal();
  if (local == null) return session.date.isEmpty ? 'Unknown date' : session.date;
  return '${local.year}-${local.month.toString().padLeft(2, '0')}'
      '-${local.day.toString().padLeft(2, '0')} '
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}
