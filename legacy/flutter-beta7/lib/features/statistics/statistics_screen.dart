import 'package:flutter/material.dart';
import '../../data/mediaflow_library_repository.dart';
import '../../data/mediaflow_models.dart';

class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({super.key, required this.repository});
  final MediaFlowLibraryRepository repository;
  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  late Future<MediaFlowCatalog> future;
  @override
  void initState() {
    super.initState();
    future = widget.repository.load();
  }
  void refresh() => setState(() => future = widget.repository.reload());

  @override
  Widget build(BuildContext context) => FutureBuilder<MediaFlowCatalog>(
    future: future, builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.hasError) {
        return Center(child: FilledButton(onPressed: refresh,
          child: const Text('Could not load Statistics — retry')));
      }
      final data = snapshot.requireData;
      final now = DateTime.now();
      final valid = data.sessions.where((s) => s.status != 'skipped').toList();
      final today = valid.where((s) => s.isOnDate(now)).toList();
      final week = valid.where((s) => _within(s, now, 7)).toList();
      final month = valid.where((s) => _within(s, now, 30)).toList();
      final byCategory = <String, double>{};
      for (final session in week) {
        byCategory.update(session.categoryId, (v) => v + session.minutes,
            ifAbsent: () => session.minutes);
      }
      final ranked = byCategory.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final maxMinutes = ranked.isEmpty ? 1.0 : ranked.first.value;
      final completed = valid.where(
        (s) => s.status == 'complete' || s.status == 'over').length;
      final days = valid.map((s) => s.date).where((d) => d.isNotEmpty).toSet().length;
      final allMinutes = _minutes(valid);
      final completion = valid.isEmpty ? 0.0 : completed / valid.length * 100;
      return ListView(children: [
        Row(children: [
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Statistics', style: Theme.of(context).textTheme.headlineMedium),
              const Text('Your consumption, measured · Read-only'),
            ],
          )),
          IconButton(onPressed: refresh, tooltip: 'Refresh Statistics',
              icon: const Icon(Icons.refresh)),
        ]),
        const SizedBox(height: 12),
        LayoutBuilder(builder: (context, box) {
          final width = box.maxWidth >= 720 ? (box.maxWidth - 24) / 3
              : box.maxWidth >= 440 ? (box.maxWidth - 12) / 2 : box.maxWidth;
          return Wrap(spacing: 12, runSpacing: 12, children: [
            _period(context, width, 'Today', today),
            _period(context, width, 'Last 7 days', week),
            _period(context, width, 'Last 30 days', month),
          ]);
        }),
        const SizedBox(height: 12),
        Card(child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('CATEGORY BALANCE · LAST 7 DAYS',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            if (ranked.isEmpty) const Text('No logged activity in this period.'),
            for (final entry in ranked) ...[
              Row(children: [
                Expanded(child: Text(
                  data.categoryById[entry.key]?.name ?? entry.key,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                )),
                Text('${entry.value.toStringAsFixed(0)} min'),
              ]),
              const SizedBox(height: 5),
              LinearProgressIndicator(
                value: maxMinutes <= 0 ? 0 : (entry.value / maxMinutes).clamp(0, 1),
                minHeight: 7,
              ),
              const SizedBox(height: 12),
            ],
          ]),
        )),
        const SizedBox(height: 12),
        Card(child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('LIFETIME RECORDS',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            _record('Logged sessions', valid.length.toString()),
            _record('Total minutes', allMinutes.toStringAsFixed(0)),
            _record('Average minutes per logged day',
                (days == 0 ? 0 : allMinutes / days).toStringAsFixed(0)),
            _record('Completed or over target', '${completion.toStringAsFixed(0)}%'),
            _record('Library titles', data.library.length.toString()),
            _record('Collections', data.collections.length.toString()),
          ]),
        )),
        const Padding(
          padding: EdgeInsets.all(12),
          child: Text('These statistics are calculated from existing logged '
            'sessions. Advanced v410 analytics, saturation, and XP/streak '
            'calculations are not yet reproduced in this native screen.',
            textAlign: TextAlign.center),
        ),
      ]);
    },
  );

  Widget _period(BuildContext context, double width, String label,
      List<MediaFlowSession> sessions) {
    final units = <String, double>{};
    for (final session in sessions) {
      units.update(session.unit, (v) => v + session.actualAmount,
          ifAbsent: () => session.actualAmount);
    }
    return SizedBox(width: width, child: Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          Text('${_minutes(sessions).toStringAsFixed(0)} min',
              style: Theme.of(context).textTheme.headlineSmall),
          Text('${sessions.length} sessions'),
          const SizedBox(height: 4),
          for (final entry in units.entries)
            Text('${entry.value.toStringAsFixed(0)} ${entry.key}',
                style: Theme.of(context).textTheme.bodySmall),
        ]),
      ),
    ));
  }

  Widget _record(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(children: [
      Expanded(child: Text(label)),
      Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
    ]),
  );
}

double _minutes(List<MediaFlowSession> sessions) =>
    sessions.fold(0.0, (sum, session) => sum + session.minutes);

bool _within(MediaFlowSession session, DateTime now, int days) {
  final date = session.timestamp?.toLocal() ?? DateTime.tryParse(session.date);
  if (date == null) return false;
  final cutoff = DateTime(now.year, now.month, now.day).subtract(Duration(days: days - 1));
  return !date.isBefore(cutoff) && !date.isAfter(now);
}
