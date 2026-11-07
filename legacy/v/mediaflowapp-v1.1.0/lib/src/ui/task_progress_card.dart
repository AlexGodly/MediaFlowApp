// The website's floating Task Progress card (v397, with the v405 setting and
// the v410 phone start). It sits over the Log tab while the logging form is
// open and counts units added to the form before Save. Read-only.

import 'package:flutter/material.dart';

import '../logic/task_progress.dart';
import 'theme.dart';
import 'widgets.dart';

class TaskProgressCard extends StatefulWidget {
  const TaskProgressCard({super.key, required this.progress, required this.taskKey});
  final TaskProgress progress;

  /// Changes when the task changes, so the goal flash belongs to one task.
  final String taskKey;

  @override
  State<TaskProgressCard> createState() => _TaskProgressCardState();
}

// Minimized or not is remembered while the app runs (not saved, like the
// website); phones start minimized so the card doesn't cover the form.
bool? _compactChoice;

class _TaskProgressCardState extends State<TaskProgressCard> with SingleTickerProviderStateMixin {
  late final AnimationController _flash =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  String _previous = '';

  bool _compact(BuildContext context) => _compactChoice ?? MediaQuery.sizeOf(context).width <= 720;

  @override
  void initState() {
    super.initState();
    _previous = _key();
  }

  String _key() => '${widget.taskKey}/${widget.progress.amount}/${widget.progress.low}/${widget.progress.high}';

  @override
  void didUpdateWidget(TaskProgressCard old) {
    super.didUpdateWidget(old);
    final key = _key();
    if (key != _previous) {
      if (widget.progress.amount == widget.progress.low) _flash.forward(from: 0);
      _previous = key;
    }
  }

  @override
  void dispose() {
    _flash.dispose();
    super.dispose();
  }

  void _toggle(BuildContext context) => setState(() => _compactChoice = !_compact(context));

  @override
  Widget build(BuildContext context) {
    final p = widget.progress;
    final compact = _compact(context);
    final tone = p.over ? MF.warn : p.reached ? MF.good : MF.accent;
    final percent = TweenAnimationBuilder<double>(
      tween: Tween(end: p.pct),
      duration: const Duration(milliseconds: 550),
      curve: Curves.easeOutCubic,
      builder: (context, v, child) => Text('${v.round()}%',
          style: TextStyle(fontSize: compact ? 15 : 30, fontWeight: FontWeight.w900, color: compact ? tone : null)),
    );

    if (compact) {
      return Semantics(
        button: true,
        label: 'Task progress ${p.pct.round()} percent. Expand',
        child: Material(
          color: MF.raised,
          elevation: 6,
          shape: StadiumBorder(side: BorderSide(color: tone.withValues(alpha: 0.6))),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: () => _toggle(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.flag_rounded, size: 18, color: tone),
                const SizedBox(width: 8),
                percent,
              ]),
            ),
          ),
        ),
      );
    }

    final track = LayoutBuilder(builder: (context, c) {
      final marker = p.marker;
      return SizedBox(
        height: 14,
        child: Stack(clipBehavior: Clip.none, children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: p.pct / 100),
                duration: const Duration(milliseconds: 550),
                curve: Curves.easeOutCubic,
                builder: (context, v, child) =>
                    LinearProgressIndicator(value: v, minHeight: 14, backgroundColor: MF.background, color: tone),
              ),
            ),
          ),
          if (marker != null)
            Positioned(
              left: (c.maxWidth * marker - 2).clamp(0.0, c.maxWidth - 4).toDouble(),
              top: -3,
              bottom: -3,
              child: Container(
                width: 4,
                decoration: BoxDecoration(color: MF.text, borderRadius: BorderRadius.circular(2)),
              ),
            ),
        ]),
      );
    });

    return AnimatedBuilder(
      animation: _flash,
      builder: (context, child) {
        final glow = _flash.isAnimating ? (1 - (_flash.value - 0.5).abs() * 2) : 0.0;
        return Material(
          color: MF.surface,
          elevation: 8,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: Color.lerp(MF.border, MF.good, glow)!, width: 1 + glow * 1.5),
          ),
          child: child,
        );
      },
      child: Semantics(
        container: true,
        label: 'Task progress',
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 6, 12),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Container(width: 7, height: 7, decoration: BoxDecoration(color: tone, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'TASK PROGRESS · ${p.categoryName.toUpperCase()}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1, color: MF.textDim),
                ),
              ),
              IconButton(
                tooltip: 'Minimize task progress',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.remove_rounded),
                onPressed: () => _toggle(context),
              ),
            ]),
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                      Expanded(
                        child: Text('${fmtNumber(p.amount)} / ${fmtNumber(p.denominator)}',
                            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                      ),
                      Text(p.denominator == 1 ? 'unit' : 'units', style: const TextStyle(color: MF.textDim)),
                    ]),
                    const SizedBox(height: 8),
                    track,
                  ]),
                ),
                Container(width: 1, height: 52, margin: const EdgeInsets.symmetric(horizontal: 14), color: MF.border),
                Column(mainAxisSize: MainAxisSize.min, children: [
                  percent,
                  const Text('COMPLETE',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1, color: MF.textDim)),
                ]),
              ]),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Row(children: [
                Container(width: 7, height: 7, decoration: BoxDecoration(color: tone, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Expanded(child: Text(p.status, style: TextStyle(color: tone, fontWeight: FontWeight.w800, fontSize: 13))),
                Text('GOAL ${p.low}${p.high == p.low ? '' : '–${p.high}'}',
                    style: const TextStyle(color: MF.textDim, fontSize: 11, fontWeight: FontWeight.w700)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
