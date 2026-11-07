// The website sidebar's Leveling and Day Streak cards, shown at the top of the
// Log tab. They use the app's current theme; the figures update live after
// every log because the Log tab rebuilds when the account changes.

import 'package:flutter/material.dart';

import '../logic/progress_summary.dart';
import '../util/js.dart';
import 'theme.dart';
import 'widgets.dart';

String _xp(num v) => fmtNumber(jsRound(v.toDouble() < 0 ? 0 : v.toDouble()));

class ProgressCards extends StatelessWidget {
  const ProgressCards({super.key, required this.state});
  final Map<String, dynamic> state;

  @override
  Widget build(BuildContext context) {
    final p = cachedProgressSummary(state, DateTime.now().millisecondsSinceEpoch);
    return LayoutBuilder(builder: (context, c) {
      final level = _LevelingCard(p);
      final streak = _StreakCard(p);
      if (c.maxWidth >= 560) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(flex: 3, child: level),
              const SizedBox(width: 12),
              Expanded(flex: 2, child: streak),
            ]),
          ),
        );
      }
      // Phones: one compact card, so the task stays near the top.
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: _LevelingCard(p, compact: true),
      );
    });
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Material(
        color: MF.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: MF.border)),
        child: Padding(padding: const EdgeInsets.fromLTRB(16, 14, 16, 14), child: child),
      );
}

final _label = TextStyle(color: MF.textDim, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.1);

class _LevelingCard extends StatelessWidget {
  const _LevelingCard(this.p, {this.compact = false});
  final ProgressSummary p;

  /// Phones: the Day Streak goes in this card's header.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l = p.level;
    final next = l.level + 1;
    final fraction = l.needed <= 0 ? 1.0 : (l.current / l.needed).clamp(0.0, 1.0).toDouble();
    return Semantics(
      label: 'Level ${l.level}, ${_xp(l.xp)} XP total',
      child: _Card(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(Icons.auto_awesome_rounded, color: MF.accent, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text('LEVELING', maxLines: 1, overflow: TextOverflow.ellipsis, style: _label)),
            Flexible(
              child: Text('Lv. ${l.level}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: MF.accent, fontSize: compact ? 22 : 26, fontWeight: FontWeight.w900)),
            ),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              child: Text('${_xp(l.xp)} XP total',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text('${_xp(l.current)} / ${_xp(l.needed)}',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ]),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: fraction),
              duration: const Duration(milliseconds: 450),
              curve: Curves.easeOutCubic,
              builder: (context, v, child) => LinearProgressIndicator(
                value: v,
                minHeight: 8,
                backgroundColor: MF.raised,
                color: MF.accent,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: Text(
                p.readyForNext ? 'Ready for Level $next' : '${_xp(p.toNext)} XP to Level $next',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: MF.textDim, fontSize: 12),
              ),
            ),
            if (compact) ...[
              const SizedBox(width: 8),
              Semantics(
                label: 'Day streak ${p.streak}, times ${p.multiplier.toStringAsFixed(2)} XP',
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('${p.streak}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                  Icon(Icons.local_fire_department_rounded, color: p.streak > 0 ? MF.warn : MF.textDim, size: 20),
                  const SizedBox(width: 4),
                  Text('×${p.multiplier.toStringAsFixed(2)} XP',
                      style: TextStyle(color: MF.accent, fontSize: 12, fontWeight: FontWeight.w800)),
                ]),
              ),
            ],
          ]),
        ]),
      ),
    );
  }
}

class _StreakCard extends StatelessWidget {
  const _StreakCard(this.p);
  final ProgressSummary p;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Day streak ${p.streak}, times ${p.multiplier.toStringAsFixed(2)} XP',
      child: _Card(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('DAY STREAK', style: _label),
          const SizedBox(height: 8),
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Text('${p.streak}', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
            const SizedBox(width: 6),
            Icon(Icons.local_fire_department_rounded, color: p.streak > 0 ? MF.warn : MF.textDim, size: 26),
            const SizedBox(width: 10),
            Text('×${p.multiplier.toStringAsFixed(2)} XP',
                style: TextStyle(color: MF.accent, fontWeight: FontWeight.w800)),
          ]),
        ]),
      ),
    );
  }
}
