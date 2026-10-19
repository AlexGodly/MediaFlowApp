import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/mediaflow_models.dart';
import '../../services/native_m36_dashboard_tools.dart';

/// Pure Flutter dashboard tools. Results are local only; never create History
/// entries, logs, progression, category tasks, XP, or cloud state edits.
class NativeM36DashboardToolsPanel extends StatelessWidget {
  const NativeM36DashboardToolsPanel({
    super.key, required this.controller, required this.catalog,
    required this.openLibrary,
  });

  final NativeM36DashboardToolsController controller;
  final MediaFlowCatalog catalog;
  final VoidCallback openLibrary;

  @override
  Widget build(BuildContext context) => Column(children: [
    _StopwatchCard(clock: controller.stopwatch),
    _RuntimeCalculatorCard(calculator: controller.calculator),
    _ReadOnlyTitleQueues(catalog: catalog, openLibrary: openLibrary),
  ]);
}

class _StopwatchCard extends StatefulWidget {
  const _StopwatchCard({required this.clock});
  final NativeM36Stopwatch clock;
  @override
  State<_StopwatchCard> createState() => _StopwatchCardState();
}

class _StopwatchCardState extends State<_StopwatchCard> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    widget.clock.addListener(_reconcile);
    _reconcile();
  }

  @override
  void didUpdateWidget(covariant _StopwatchCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.clock != widget.clock) {
      oldWidget.clock.removeListener(_reconcile);
      _ticker?.cancel();
      _ticker = null;
      widget.clock.addListener(_reconcile);
      _reconcile();
    }
  }

  void _reconcile() {
    if (!mounted) return;
    if (widget.clock.isRunning && _ticker == null) {
      _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (mounted) setState(() {});
      });
    } else if (!widget.clock.isRunning) {
      _ticker?.cancel();
      _ticker = null;
    }
    setState(() {});
  }

  @override
  void dispose() {
    _ticker?.cancel();
    widget.clock.removeListener(_reconcile);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Card(
    child: ExpansionTile(
      key: const Key('m36-stopwatch-expansion'),
      initiallyExpanded: true,
      leading: const Icon(Icons.timer_outlined),
      title: const Text('STOPWATCH'),
      subtitle: const Text('Track elapsed time locally; no automatic logging.'),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: [
        Text(
          NativeM36Duration.fromSeconds(
            widget.clock.elapsed.inSeconds).clock,
          key: const Key('m36-stopwatch-clock'),
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 8),
        Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: widget.clock.isRunning ?
                  widget.clock.pause : widget.clock.start,
              icon: Icon(widget.clock.isRunning
                  ? Icons.pause_outlined : Icons.play_arrow_outlined),
              label: Text(widget.clock.isRunning ? 'Pause' : 'Start'),
            ),
            OutlinedButton.icon(
              onPressed: widget.clock.reset,
              icon: const Icon(Icons.restart_alt_outlined),
              label: const Text('Reset'),
            ),
          ],
        ),
      ],
    ),
  );
}

class _RuntimeCalculatorCard extends StatefulWidget {
  const _RuntimeCalculatorCard({required this.calculator});
  final NativeM36RuntimeCalculator calculator;
  @override
  State<_RuntimeCalculatorCard> createState() => _RuntimeCalculatorCardState();
}

class _RuntimeCalculatorCardState extends State<_RuntimeCalculatorCard> {
  String? notice;
  NativeM36RuntimeCalculator get calc => widget.calculator;

  void _calculate() {
    setState(() => notice = calc.calculate()
        ? null : 'Enter at least one runtime to calculate.');
  }

  void _clear() {
    calc.clear();
    setState(() => notice = null);
  }

  Widget _timeRow(BuildContext context, String scope, int index,
      NativeM36Duration value) {
    Widget field(String key, String label, int numeric) => SizedBox(
      width: 76,
      child: TextFormField(
        key: Key('m36-$scope-$index-$key-${calc.inputRevision}'),
        initialValue: numeric.toString(),
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.next,
        decoration: InputDecoration(
          isDense: true,
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        onChanged: (input) => calc.edit(scope, index, key, input),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Wrap(
        spacing: 7, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(width: 83,child: Text('Runtime ${index + 1}',
              style: Theme.of(context).textTheme.labelLarge)),
          field('h', 'Hours', value.hours),
          field('m', 'Minutes', value.minutes),
          field('s', 'Seconds', value.seconds),
          if (scope == 'multi')
            IconButton(
              key: Key('m36-remove-row-$index'),
              onPressed: calc.rows.length > 2 ?
                  () { calc.removeRow(index); setState(() {}); } : null,
              tooltip: 'Remove runtime row',
              icon: const Icon(Icons.remove_circle_outline),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Card(
    child: ExpansionTile(
      key: const Key('m36-runtime-expansion'),
      initiallyExpanded: true,
      leading: const Icon(Icons.calculate_outlined),
      title: const Text('RUNTIME CALCULATOR'),
      subtitle: const Text('Add durations, carry totals or sum multiple rows.'),
      childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
      children: [
        AnimatedBuilder(
          animation: calc,
          builder: (context, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(spacing: 8, runSpacing: 8, children: [
                ChoiceChip(
                  key: const Key('m36-chain-mode'),
                  label: const Text('Carry-forward'),
                  selected: calc.mode == NativeM36RuntimeMode.chain,
                  onSelected: (_) => calc.switchMode(NativeM36RuntimeMode.chain),
                ),
                ChoiceChip(
                  key: const Key('m36-multi-mode'),
                  label: const Text('Multi-row'),
                  selected: calc.mode == NativeM36RuntimeMode.multi,
                  onSelected: (_) => calc.switchMode(NativeM36RuntimeMode.multi),
                ),
              ]),
              const SizedBox(height: 6),
              for (var i = 0; i < (calc.mode == NativeM36RuntimeMode.chain
                  ? calc.chain.length : calc.rows.length); i++)
                _timeRow(context,
                    calc.mode == NativeM36RuntimeMode.chain ? 'chain' : 'multi',
                    i, calc.mode == NativeM36RuntimeMode.chain
                      ? calc.chain[i] : calc.rows[i]),
              if (calc.mode == NativeM36RuntimeMode.multi)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: const Key('m36-add-runtime-row'),
                    onPressed: calc.rows.length < 100
                        ? calc.addRow : null,
                    icon: const Icon(Icons.add),
                    label: const Text('Add runtime row'),
                  ),
                ),
              const SizedBox(height: 8),
              Text(calc.hasResult
                  ? NativeM36Duration.fromSeconds(calc.resultSeconds).clock
                  : '00:00:00',
                key: const Key('m36-runtime-result'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium),
              Text(calc.hasResult
                  ? '${calc.resultCount} runtime(s) calculated'
                  : 'Waiting for calculation',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                FilledButton.icon(
                  key: const Key('m36-calculate'),
                  onPressed: _calculate,
                  icon: const Icon(Icons.calculate_outlined),
                  label: const Text('Calculate')),
                if (calc.mode == NativeM36RuntimeMode.chain) ...[
                  OutlinedButton.icon(
                    key: const Key('m36-continue-result'),
                    onPressed: calc.hasResult ? calc.continueResult : null,
                    icon: const Icon(Icons.arrow_forward_outlined),
                    label: const Text('Continue with result')),
                  TextButton.icon(
                    key: const Key('m36-previous-total'),
                    onPressed: calc.hasResult &&
                            calc.previousAccumulatorSeconds > 0
                        ? calc.previousTotal : null,
                    icon: const Icon(Icons.undo_outlined),
                    label: const Text('Previous total')),
                ],
                TextButton.icon(
                  key: const Key('m36-clear'),
                  onPressed: _clear,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Clear')),
              ]),
              if (notice != null) Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(notice!, key: const Key('m36-runtime-notice'))),
              if (calc.hasResult) Padding(
                padding: const EdgeInsets.only(top: 6),
                child: SelectableText(
                  'Rounded logging duration: '
                  '${calc.proposedLoggingMinutes} minutes (preview only)',
                  key: const Key('m36-proposed-minutes')),
              ),
              const SizedBox(height: 6),
              Text('Results stay on this device while the account shell is '
                  'open. Nothing is submitted to Logging, History or XP.',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ],
    ),
  );
}

class _ReadOnlyTitleQueues extends StatefulWidget {
  const _ReadOnlyTitleQueues({
    required this.catalog,
    required this.openLibrary,
  });
  final MediaFlowCatalog catalog;
  final VoidCallback openLibrary;

  @override
  State<_ReadOnlyTitleQueues> createState() => _ReadOnlyTitleQueuesState();
}

class _ReadOnlyTitleQueuesState extends State<_ReadOnlyTitleQueues> {
  final Set<String> _skippedRating = {};
  final Set<String> _skippedCover = {};
  String _filterCategory = 'all';

  @override
  void didUpdateWidget(covariant _ReadOnlyTitleQueues oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.catalog, widget.catalog)) {
      _skippedRating.clear();
      _skippedCover.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final library = widget.catalog.library;
    // Lazy filtering through a bounded display list; titles are never edited.
    final unrated = <MediaFlowTitle>[];
    final missing = <MediaFlowTitle>[];
    var unratedTotal = 0, missingTotal = 0;
    for (final title in library) {
      if (_filterCategory != 'all' &&
          title.categoryId != _filterCategory) {
        continue;
      }
      if (title.rating == null) {
        unratedTotal++;
        if (!_skippedRating.contains(title.id) && unrated.length < 5) {
          unrated.add(title);
        }
      }
      if (title.coverUrl.trim().isEmpty) {
        missingTotal++;
        if (!_skippedCover.contains(title.id) && missing.length < 5) {
          missing.add(title);
        }
      }
    }
    return Column(children: [
      Card(child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('LIBRARY REVIEW QUEUES',
              style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text('Inspect unrated titles and missing covers. '
              'Changes to your Library remain disabled. '
              'Skip only changes what is shown in this preview.',
              style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              key: ValueKey('m36-category-$_filterCategory'),
              initialValue: _filterCategory,
              isExpanded: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Category', isDense: true),
              items: [
                const DropdownMenuItem(
                  value: 'all', child: Text('All categories')),
                for (final cat in widget.catalog.categories)
                  DropdownMenuItem(
                    value: cat.id,
                    child: Text(cat.name, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => _filterCategory = value);
                }
              },
            ),
          ]),
      )),
      _queueCard(context,
        title: 'RATE YOUR LIBRARY',
        count: unratedTotal, emptyLabel: 'No unrated titles to review.',
        list: unrated, skipped: _skippedRating,
        actionLabel: 'Review in Library'),
      _queueCard(context,
        title: 'MISSING COVERS',
        count: missingTotal, emptyLabel: 'No missing covers.',
        list: missing, skipped: _skippedCover,
        actionLabel: 'Browse Library'),
    ]);
  }

  Widget _queueCard(BuildContext context, {
    required String title, required int count,
    required String emptyLabel, required List<MediaFlowTitle> list,
    required Set<String> skipped, required String actionLabel,
  }) => Card(child: Padding(
    padding: const EdgeInsets.all(14),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          Expanded(child: Text(title,
              style: Theme.of(context).textTheme.labelLarge)),
          Text('$count titles'),
        ]),
        const SizedBox(height: 5),
        if (count == 0)
          Text(emptyLabel)
        else if (list.isEmpty)
          const Text('All current suggestions skipped in this view.')
        else
          for (final t in list)
            ListTile(
              dense: true, contentPadding: EdgeInsets.zero,
              leading: Icon(title == 'MISSING COVERS'
                  ? Icons.image_not_supported_outlined
                  : Icons.star_border_outlined),
              title: Text(t.title, maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              subtitle: Text(
                widget.catalog.categoryById[t.categoryId]?.name ??
                    t.categoryId,
                maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: IconButton(
                tooltip: 'Skip suggestion',
                onPressed: () => setState(() => skipped.add(t.id)),
                icon: const Icon(Icons.skip_next_outlined)),
              onTap: widget.openLibrary,
            ),
        const SizedBox(height: 4),
        Align(alignment: Alignment.centerLeft, child:
          TextButton.icon(
            onPressed: widget.openLibrary,
            icon: const Icon(Icons.local_library_outlined),
            label: Text(actionLabel))),
      ],
    ),
  ));
}
