import 'package:flutter/material.dart';

import '../../data/mediaflow_library_repository.dart';
import '../../data/mediaflow_models.dart';
import '../../design_system/mediaflow_theme.dart';

/// Read-only Dashboard projection. Scheduler/XP mutations remain owned by
/// the existing website until the native sync contract is validated.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    required this.repository,
    required this.openLibrary,
    required this.openHistory,
  });

  final MediaFlowLibraryRepository repository;
  final VoidCallback openLibrary, openHistory;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late Future<MediaFlowCatalog> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.repository.load();
  }

  void refresh() => setState(() => _future = widget.repository.reload());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<MediaFlowCatalog>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Could not load Dashboard data. No data was modified.'),
            const SizedBox(height: 12),
            FilledButton(onPressed: refresh, child: const Text('Retry')),
          ]));
        }
        return LayoutBuilder(builder: (context, dimensions) =>
            _dashboard(context, snapshot.requireData, dimensions.maxWidth));
      },
    );
  }

  Widget _dashboard(BuildContext context, MediaFlowCatalog data, double width) {
    final today = DateTime.now();
    final todaySessions = data.sessions.where(
      (s) => s.isOnDate(today) && s.status != 'skipped',
    ).toList(growable: false);
    final minutes = todaySessions.fold<double>(0, (sum, s) => sum + s.minutes);
    final logged = todaySessions.fold<double>(
      0, (sum, s) => sum + s.actualAmount,
    );
    final completed = data.library.where(
      (item) => item.status == 'completed',
    ).length;
    final active = data.library.where(
      (item) => item.status == 'active',
    ).length;

    final latest = [...data.sessions]..sort((a, b) {
      final left = a.timestamp?.millisecondsSinceEpoch ?? 0;
      final right = b.timestamp?.millisecondsSinceEpoch ?? 0;
      return right.compareTo(left);
    });
    final cardWidth = width >= 960 ? (width - 36) / 4
        : width >= 540 ? (width - 12) / 2 : width;

    return ListView(
      children: [
        Row(children: [
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Today', style: Theme.of(context).textTheme.headlineMedium),
              Text(_dateLabel(today),
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          )),
          IconButton(
            tooltip: 'Refresh Dashboard from cloud',
            onPressed: refresh,
            icon: const Icon(Icons.refresh),
          ),
        ]),
        const SizedBox(height: 15),
        Wrap(spacing: 12, runSpacing: 12, children: [
          _metric(context, cardWidth, 'Library titles',
              data.library.length.toString(), Icons.local_library_outlined),
          _metric(context, cardWidth, 'In progress',
              active.toString(), Icons.play_circle_outline),
          _metric(context, cardWidth, 'Completed titles',
              completed.toString(), Icons.task_alt_outlined),
          _metric(context, cardWidth, 'Logged today',
              _quantity(logged), Icons.edit_note_outlined),
        ]),
        const SizedBox(height: 14),
        Card(child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('TODAY’S ACTIVITY', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 10),
            Text(
              '${todaySessions.length} logged sessions · '
              '${_quantity(minutes)} minutes',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if ((data.dailyMinutes ?? 0) > 0) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: (minutes / data.dailyMinutes!).clamp(0.0, 1.0),
                minHeight: 8,
              ),
              const SizedBox(height: 6),
              Text('Daily time goal: ${_quantity(data.dailyMinutes!)} minutes'),
            ],
            if ((data.tasksPerDay ?? 0) > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Daily task goal: ${_quantity(data.tasksPerDay!)}'),
              ),
          ]),
        )),
        const SizedBox(height: 8),
        _taskCard(context, data),
        const SizedBox(height: 8),
        Card(child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text('RECENT ACTIVITY',
                style: Theme.of(context).textTheme.labelLarge)),
              TextButton.icon(onPressed: widget.openHistory,
                icon: const Icon(Icons.arrow_forward, size: 18),
                label: const Text('View History')),
            ]),
            if (latest.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(child: Text('No logged sessions yet.')),
              )
            else
              for (final session in latest.take(5))
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.history),
                  title: Text(data.categoryById[session.categoryId]?.name ??
                      session.categoryId),
                  subtitle: Text(
                    session.titles.isNotEmpty
                        ? session.titles.map((entry) => entry.title).join(' · ')
                        : session.date,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Text(_quantity(session.actualAmount) + ' ' + session.unit,
                    style: Theme.of(context).textTheme.bodySmall),
                  onTap: widget.openHistory,
                ),
          ]),
        )),
        const SizedBox(height: 8),
        const Padding(
          padding: EdgeInsets.all(10),
          child: Text(
            'Native Dashboard preview · Activity, goals, and tasks are read '
            'from your existing account. Starting, rerolling, skipping and '
            'submitting tasks will be enabled after cloud-sync parity checks.',
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  Widget _metric(BuildContext context, double width, String label,
      String value, IconData icon) => SizedBox(
    width: width,
    child: Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: MediaFlowColors.accent),
          const SizedBox(height: 10),
          Text(value, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 4),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ]),
      ),
    ),
  );

  Widget _taskCard(BuildContext context, MediaFlowCatalog data) {
    final task = data.currentTask;
    final category = task == null ? null : data.categoryById[task.categoryId];
    return Card(child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('NEXT TASK', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 10),
          if (!data.sessionActive || task == null) ...[
            Text('No active task', style: Theme.of(context).textTheme.titleLarge),
            const Text('Start a session on the original MediaFlow website. '
                'The native view will show the task after cloud synchronization.'),
          ] else ...[
            Text(category?.name ?? task.categoryId,
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text('Target: ${_quantity(task.low)}–${_quantity(task.high)} '
              '${task.unit}', style: Theme.of(context).textTheme.titleMedium),
            if (task.title.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Recommended title: ' + task.title),
            ],
            if (task.reasons.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(task.reasons.join(' · '),
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ],
          const SizedBox(height: 14),
          Align(alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: widget.openLibrary,
              icon: const Icon(Icons.local_library_outlined),
              label: const Text('Browse Library'),
            ),
          ),
        ],
      ),
    ));
  }
}

String _quantity(double number) => number == number.roundToDouble()
    ? number.toInt().toString() : number.toStringAsFixed(1);

String _dateLabel(DateTime now) {
  final month = [
    'January','February','March','April','May','June','July','August',
    'September','October','November','December',
  ][now.month - 1];
  return '$month ${now.day}, ${now.year}';
}
