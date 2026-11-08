// The website's floating Task Progress card (v397, with the v405 setting and
// the v410 phone start), animated like the website: a frosted panel tinted by
// the task, two drifting waves and a breathing aura behind it, a flowing bar
// with light streaks and the goal marker, a % that counts up, and a glow
// when the goal is reached. Minimised it is a small pill with the %.
// It counts units added to the log form before Save. Read-only.
//
// With the system's "reduce motion" on, the waves, shimmer and glow stop;
// the numbers still update.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/app_prefs.dart';
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

class _TaskProgressCardState extends State<TaskProgressCard> with TickerProviderStateMixin {
  late final AnimationController _flash = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));

  // One slow loop drives the waves, aura and shimmer (13 s, like the website's
  // slowest wave); each layer takes its own speed from it.
  late final AnimationController _loop = AnimationController(vsync: this, duration: const Duration(seconds: 39));
  String _previous = '';

  // Minimised or not is remembered on this device; phones start minimised so
  // the card doesn't cover the form.
  bool _compact(BuildContext context) =>
      AppPrefs.instance.get<bool?>('taskProgressCompact', null) ?? MediaQuery.sizeOf(context).width <= 720;

  @override
  void initState() {
    super.initState();
    _previous = _key();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (still) {
      _loop.stop();
    } else if (!_loop.isAnimating) {
      _loop.repeat();
    }
  }

  String _key() => '${widget.taskKey}/${widget.progress.amount}/${widget.progress.low}/${widget.progress.high}';

  @override
  void didUpdateWidget(TaskProgressCard old) {
    super.didUpdateWidget(old);
    final key = _key();
    if (key != _previous) {
      if (widget.progress.amount == widget.progress.low && !(MediaQuery.maybeDisableAnimationsOf(context) ?? false)) {
        _flash.forward(from: 0);
      }
      _previous = key;
    }
  }

  @override
  void dispose() {
    _flash.dispose();
    _loop.dispose();
    super.dispose();
  }

  void _toggle(BuildContext context) {
    final next = !_compact(context);
    AppPrefs.instance.set('taskProgressCompact', next);
    setState(() {});
  }

  String _units(TaskProgress p) {
    if (p.unit.isEmpty) return p.denominator == 1 ? 'unit' : 'units';
    final u = p.unit;
    return p.denominator == 1 && u.endsWith('s') ? u.substring(0, u.length - 1) : u;
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.progress;
    final compact = _compact(context);
    final tint = p.over ? MF.warn : p.reached ? MF.good : MF.accent;

    if (compact) {
      return Semantics(
        button: true,
        label: 'Task progress ${p.pct.round()} percent. Expand',
        child: Material(
          color: MF.surface.withValues(alpha: 0.94),
          elevation: 6,
          shape: StadiumBorder(side: BorderSide(color: tint.withValues(alpha: 0.55))),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _toggle(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                _Pulse(color: tint, loop: _loop),
                const SizedBox(width: 8),
                Text(p.categoryName.toUpperCase(),
                    style: TextStyle(fontSize: 10, letterSpacing: 1, fontWeight: FontWeight.w900, color: MF.textDim)),
                const SizedBox(width: 8),
                _Count(value: p.pct, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: tint)),
              ]),
            ),
          ),
        ),
      );
    }

    final card = Stack(children: [
      // Ambient layer: aura + two waves, tinted by the task.
      Positioned.fill(
        child: IgnorePointer(
          child: AnimatedBuilder(
            animation: _loop,
            builder: (context, _) => CustomPaint(painter: _AmbientPainter(_loop.value, tint)),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 6, 12),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            _Pulse(color: tint, loop: _loop),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'TASK PROGRESS · ${p.categoryName.toUpperCase()}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1, color: MF.textDim),
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
                    Text('${fmtNumber(p.amount)} / ${fmtNumber(p.denominator)}',
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                    const SizedBox(width: 6),
                    Expanded(child: Text(_units(p), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: MF.textDim))),
                  ]),
                  const SizedBox(height: 8),
                  _FlowBar(pct: p.pct / 100, marker: p.marker, tint: tint, loop: _loop),
                ]),
              ),
              Container(width: 1, height: 52, margin: const EdgeInsets.symmetric(horizontal: 14), color: MF.border),
              Column(mainAxisSize: MainAxisSize.min, children: [
                _Count(value: p.pct, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900)),
                Text('COMPLETE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1, color: MF.textDim)),
              ]),
            ]),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Row(children: [
              _Pulse(color: tint, loop: _loop),
              const SizedBox(width: 8),
              Expanded(child: Text(p.status, style: TextStyle(color: tint, fontWeight: FontWeight.w800, fontSize: 13))),
              Text('GOAL ${p.low}${p.high == p.low ? '' : '–${p.high}'}',
                  style: TextStyle(color: MF.textDim, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
            ]),
          ),
        ]),
      ),
    ]);

    return AnimatedBuilder(
      animation: _flash,
      builder: (context, child) {
        // Goal flash: a glowing ring that rises and fades (website mf397-goal).
        final t = _flash.value;
        final glow = _flash.isAnimating ? (t < 0.3 ? t / 0.3 : (1 - t) / 0.7) : 0.0;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(21),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 40, offset: const Offset(0, 14)),
              if (glow > 0) BoxShadow(color: tint.withValues(alpha: 0.35 * glow), blurRadius: 30, spreadRadius: 7 * glow),
            ],
          ),
          child: Material(
            color: MF.surface.withValues(alpha: 0.94),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(21),
              side: BorderSide(color: Color.lerp(MF.border, tint, 0.4)!),
            ),
            clipBehavior: Clip.antiAlias,
            child: child,
          ),
        );
      },
      child: Semantics(container: true, label: 'Task progress', child: card),
    );
  }
}

/// A percentage that counts to its new value (website `mf397PercentTo`).
class _Count extends StatelessWidget {
  const _Count({required this.value, required this.style});
  final double value;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(end: value),
        duration: const Duration(milliseconds: 550),
        curve: Curves.easeOutCubic,
        builder: (context, v, _) => Text('${v.round()}%', style: style),
      );
}

/// The pulsing status dot.
class _Pulse extends StatelessWidget {
  const _Pulse({required this.color, required this.loop});
  final Color color;
  final Animation<double> loop;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: loop,
        builder: (context, _) {
          final s = 0.5 + 0.5 * math.sin(loop.value * 2 * math.pi * 13); // ~3 s breathe
          return Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: color.withValues(alpha: 0.6 * s), blurRadius: 4 + 4 * s, spreadRadius: s)],
            ),
          );
        },
      );
}

/// The flowing progress bar: eased width, a moving shimmer gradient, light
/// streaks sliding through, a glossy top and the goal marker.
class _FlowBar extends StatelessWidget {
  const _FlowBar({required this.pct, required this.marker, required this.tint, required this.loop});
  final double pct;
  final double? marker;
  final Color tint;
  final Animation<double> loop;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 16,
      child: LayoutBuilder(builder: (context, c) {
        return Stack(clipBehavior: Clip.none, children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(color: MF.background.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(8)),
            ),
          ),
          TweenAnimationBuilder<double>(
            tween: Tween(end: pct.clamp(0, 1).toDouble()),
            duration: const Duration(milliseconds: 850),
            curve: const Cubic(.18, .7, .22, 1),
            builder: (context, v, _) => SizedBox(
              width: c.maxWidth * v,
              child: AnimatedBuilder(
                animation: loop,
                builder: (context, _) => CustomPaint(painter: _FillPainter(loop.value, tint)),
              ),
            ),
          ),
          if (marker != null)
            Positioned(
              left: (c.maxWidth * marker! - 1).clamp(0.0, c.maxWidth - 2).toDouble(),
              top: 0,
              bottom: 0,
              child: Container(
                width: 2,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.67),
                  boxShadow: [BoxShadow(color: Colors.white.withValues(alpha: 0.5), blurRadius: 5)],
                ),
              ),
            ),
        ]);
      }),
    );
  }
}

class _FillPainter extends CustomPainter {
  _FillPainter(this.t, this.tint);
  final double t;
  final Color tint;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0) return;
    final r = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(8));
    canvas.save();
    canvas.clipRRect(r);
    final light = Color.lerp(tint, Colors.white, 0.45)!;
    // Shimmer: a 2.5× wide gradient sliding by (3 s loop).
    final shift = (t * 13) % 1.0;
    final w = size.width * 2.5;
    final dx = -w * shift;
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          colors: [tint, light, tint, Color.lerp(tint, Colors.white, 0.35)!, tint],
          stops: const [0, .2, .4, .7, 1],
          tileMode: TileMode.repeated,
        ).createShader(Rect.fromLTWH(dx, 0, w, size.height)),
    );
    // Light streaks (2.8 s loop).
    final streak = Paint()..color = Colors.white.withValues(alpha: 0.18);
    final period = 155.0, offset = ((t * 14) % 1.0) * period;
    for (var x = -period + offset; x < size.width + period; x += period / 3) {
      final path = Path()
        ..moveTo(x, size.height)
        ..lineTo(x + 6, size.height)
        ..lineTo(x + 6 + size.height * 0.4, 0)
        ..lineTo(x + size.height * 0.4, 0)
        ..close();
      canvas.drawPath(path, streak);
    }
    // Gloss.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height * 0.45),
      Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.white.withValues(alpha: 0.4), Colors.white.withValues(alpha: 0)]).createShader(Rect.fromLTWH(0, 0, size.width, size.height * 0.45)),
    );
    canvas.restore();
    // Glow under the fill.
    canvas.drawRRect(r, Paint()..color = tint.withValues(alpha: 0.25)..maskFilter = const MaskFilter.blur(BlurStyle.outer, 8));
  }

  @override
  bool shouldRepaint(_FillPainter old) => old.t != t || old.tint != tint;
}

/// The aura and two waves drifting in opposite directions (9 s and 13 s).
class _AmbientPainter extends CustomPainter {
  _AmbientPainter(this.t, this.tint);
  final double t;
  final Color tint;

  @override
  void paint(Canvas canvas, Size size) {
    // Aura breathing (6 s, alternate).
    final a = 0.5 + 0.5 * math.sin(t * 2 * math.pi * 6.5);
    final center = Offset(size.width * (0.22 + 0.05 * a), size.height * (1.0 + 0.02 * a));
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          colors: [tint.withValues(alpha: 0.13 + 0.12 * a), tint.withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(center: center, radius: size.width * (0.64 + 0.06 * a))),
    );
    void wave(double baseline, double amp, double phase, double alpha) {
      final p = Path()..moveTo(0, size.height);
      final wl = size.width / 2;
      for (double x = 0; x <= size.width; x += 4) {
        final y = baseline + amp * math.sin((x / wl) * 2 * math.pi + phase);
        p.lineTo(x, y);
      }
      p
        ..lineTo(size.width, size.height)
        ..close();
      canvas.drawPath(p, Paint()..color = tint.withValues(alpha: alpha));
    }

    wave(size.height * 0.80, 6, t * 2 * math.pi * 4.33, 0.10); // back, 9 s to the left
    wave(size.height * 0.88, 5, -t * 2 * math.pi * 3.0, 0.08); // front, 13 s to the right
  }

  @override
  bool shouldRepaint(_AmbientPainter old) => old.t != t || old.tint != tint;
}
