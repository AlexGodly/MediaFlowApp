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
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

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

  // Seconds since the card appeared. Every layer takes its own period from it
  // (waves 9 s / 13 s, aura 6 s, shimmer 3 s, streaks 2.8 s, dot 2.1 s), so
  // nothing jumps when a loop restarts.
  final _clock = ValueNotifier<double>(0);
  late final Ticker _ticker = createTicker((d) => _clock.value = d.inMicroseconds / 1e6);
  ValueListenable<double> get _loop => _clock;
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
      if (_ticker.isActive) _ticker.stop();
    } else if (!_ticker.isActive) {
      _ticker.start();
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
    _ticker.dispose();
    _clock.dispose();
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
    final tint = p.warn ? MF.bad : p.reached ? MF.good : MF.accent;

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
          child: ValueListenableBuilder<double>(
            valueListenable: _loop,
            builder: (context, t, _) => CustomPaint(painter: _AmbientPainter(t, tint, MF.surface)),
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
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5, color: MF.textDim),
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
                        style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900, fontFeatures: [FontFeature.tabularFigures()])),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(_units(p),
                          maxLines: 1,
                          textAlign: TextAlign.end,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: MF.textDim, fontSize: 11, fontWeight: FontWeight.w600)),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  _FlowBar(pct: p.pct / 100, marker: p.marker, tint: tint, loop: _loop, height: MediaQuery.sizeOf(context).width <= 720 ? 20 : 25),
                ]),
              ),
              Container(width: 1, height: 58, margin: const EdgeInsets.only(left: 13, right: 12), color: MF.border),
              Column(mainAxisSize: MainAxisSize.min, children: [
                _Count(
                  value: p.pct,
                  style: TextStyle(
                    fontSize: 34,
                    height: 1,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1.9,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    shadows: [Shadow(color: tint.withValues(alpha: 0.26), blurRadius: 20)],
                  ),
                ),
                const SizedBox(height: 6),
                Text('COMPLETE', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: MF.textDim)),
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
  final ValueListenable<double> loop;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<double>(
        valueListenable: loop,
        builder: (context, t, _) {
          final s = 0.5 + 0.5 * math.sin(t / 2.1 * 2 * math.pi); // 2.1 s breathe (mf397-breathe)
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

/// The flowing progress bar (website .mf397-track / .mf397-fill): a sunken
/// track, the fill easing to its width with a glow, a sliding gradient (3 s),
/// light streaks (2.8 s), a glossy top and the goal marker with its cap.
class _FlowBar extends StatelessWidget {
  const _FlowBar({required this.pct, required this.marker, required this.tint, required this.loop, this.height = 25});
  final double pct;
  final double? marker;
  final Color tint;
  final ValueListenable<double> loop;
  final double height;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(height / 2);
    return SizedBox(
      height: height,
      child: LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth;
        return Container(
          decoration: BoxDecoration(
            color: Color.lerp(MF.surface, MF.background, 0.72),
            borderRadius: radius,
            border: Border.all(color: MF.border),
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: Stack(children: [
              // Inset shadow at the top of the track.
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.black.withValues(alpha: 0.35), Colors.black.withValues(alpha: 0)],
                      stops: const [0, 0.45],
                    ),
                  ),
                ),
              ),
              TweenAnimationBuilder<double>(
                tween: Tween(end: pct.clamp(0, 1).toDouble()),
                duration: const Duration(milliseconds: 850),
                curve: const Cubic(.18, .7, .22, 1),
                builder: (context, v, _) => Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: w * v,
                  child: ValueListenableBuilder<double>(
                    valueListenable: loop,
                    builder: (context, t, _) => CustomPaint(painter: _FillPainter(t, tint, height / 2)),
                  ),
                ),
              ),
              if (marker != null)
                Positioned(
                  left: (w * marker! - 1).clamp(0.0, w - 2).toDouble(),
                  top: 0,
                  bottom: 0,
                  width: 2,
                  child: Stack(clipBehavior: Clip.none, children: [
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.67),
                          boxShadow: [BoxShadow(color: Colors.white.withValues(alpha: 0.53), blurRadius: 5)],
                        ),
                      ),
                    ),
                    Positioned(
                      left: -3,
                      top: 0,
                      child: Container(
                        width: 8,
                        height: 5,
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.53), borderRadius: BorderRadius.circular(3)),
                      ),
                    ),
                  ]),
                ),
            ]),
          ),
        );
      }),
    );
  }
}

class _FillPainter extends CustomPainter {
  _FillPainter(this.t, this.tint, this.radius);
  final double t;
  final Color tint;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0.5) return;
    final rect = Offset.zero & size;
    final r = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    // Glow around the fill.
    canvas.drawRRect(r, Paint()..color = tint.withValues(alpha: 0.34)..maskFilter = const MaskFilter.blur(BlurStyle.outer, 9));
    canvas.save();
    canvas.clipRRect(r);
    // Flowing gradient: 100°, 250 % wide, sliding one full width every 3 s.
    final light1 = Color.lerp(tint, Colors.white, 0.45)!, light2 = Color.lerp(tint, Colors.white, 0.35)!;
    final gw = size.width * 2.5;
    final dx = -gw * ((t / 3) % 1);
    final grad = LinearGradient(
      begin: const Alignment(-1, -0.18),
      end: const Alignment(1, 0.18),
      colors: [tint, light1, tint, light2, tint],
      stops: const [0, .4, .67, .95, 1],
      tileMode: TileMode.repeated,
    );
    canvas.drawRect(rect, Paint()..shader = grad.createShader(Rect.fromLTWH(dx, 0, gw, size.height)));
    // Light streaks (repeating 110° bands every 155 px, sliding over 2.8 s).
    const period = 155.0;
    final offset = ((t / 2.8) % 1) * period;
    final slant = size.height * 0.36; // tan(20°)
    final band = Paint()
      ..shader = const LinearGradient(colors: [Color(0x00FFFFFF), Color(0x33FFFFFF), Color(0x00FFFFFF)]).createShader(const Rect.fromLTWH(0, 0, 20, 1));
    for (var x = -period + offset; x < size.width + period; x += period) {
      for (final start in const [23.0, 23.0 + 51.67, 23.0 + 103.33]) {
        final x0 = x + start;
        final path = Path()
          ..moveTo(x0, size.height)
          ..lineTo(x0 + 20, size.height)
          ..lineTo(x0 + 20 + slant, 0)
          ..lineTo(x0 + slant, 0)
          ..close();
        canvas.save();
        canvas.translate(x0, 0);
        canvas.drawPath(path.shift(Offset(-x0, 0)), band);
        canvas.restore();
      }
    }
    // Gloss on the top half, and the inner top highlight.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height * 0.43),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white.withValues(alpha: 0.3 * 0.47), Colors.white.withValues(alpha: 0)],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height * 0.43)),
    );
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, 2), Paint()..color = Colors.white.withValues(alpha: 0.26));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FillPainter old) => old.t != t || old.tint != tint || old.radius != radius;
}

/// The ambient layer (website .mf397-ambient): a breathing aura (6 s,
/// alternate) and two waves drifting in opposite directions (9 s left, 13 s
/// right), faded from the left by the panel colour.
class _AmbientPainter extends CustomPainter {
  _AmbientPainter(this.t, this.tint, this.panel);
  final double t;
  final Color tint, panel;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    // Aura: 6 s ease-in-out, alternating (0 → 1 → 0 over 12 s).
    final phase = (t / 6) % 2;
    final lin = phase < 1 ? phase : 2 - phase;
    final a = lin < .5 ? 2 * lin * lin : 1 - math.pow(-2 * lin + 2, 2) / 2;
    final box = Rect.fromLTRB(-0.1 * w, -0.3 * h, 1.1 * w, 1.1 * h);
    final scale = 1 + 0.1 * a;
    final center = Offset(box.left + box.width * 0.22 + 0.05 * box.width * a, box.bottom + 0.02 * box.height * a);
    final radius = math.sqrt(math.pow(box.width * 0.78, 2) + math.pow(box.height, 2)) * 0.64 * scale;
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(colors: [
          tint.withValues(alpha: 0.37 * (0.34 + 0.31 * a)),
          tint.withValues(alpha: 0),
        ]).createShader(Rect.fromCircle(center: center, radius: radius)),
    );

    // The website's exact SVG (v565): viewBox 800×180 stretched over a box
    // twice the card's width and 110% of its height, bottom −24% (back) or
    // −12% (front). Each 100-unit segment is a quadratic curve whose control
    // point alternates up/down (`Q50 32 100 62 T200 62 …`). The back wave
    // moves left by half its box in 9 s, the front one right in 13 s.
    void svgWave({required double bottomPct, required double base, required double up, required double offsetX, required Color color}) {
      final boxW = 2 * w, boxH = 1.1 * h;
      final top = h + bottomPct * h - boxH;
      final sx = boxW / 800, sy = boxH / 180;
      final p = Path()..moveTo(offsetX, top + base * sy);
      for (var i = 0; i < 8; i++) {
        final x0 = i * 100.0;
        final cy = i.isEven ? up : 2 * base - up;
        p.quadraticBezierTo(offsetX + (x0 + 50) * sx, top + cy * sy, offsetX + (x0 + 100) * sx, top + base * sy);
      }
      p
        ..lineTo(offsetX + 800 * sx, top + 180 * sy)
        ..lineTo(offsetX, top + 180 * sy)
        ..close();
      canvas.drawPath(p, Paint()..color = color);
    }

    svgWave(bottomPct: 0.24, base: 62, up: 32, offsetX: -w * ((t / 9) % 1), color: tint.withValues(alpha: 0.16));
    svgWave(
      bottomPct: 0.12,
      base: 78,
      up: 49,
      offsetX: -w + w * ((t / 13) % 1),
      color: Color.lerp(panel, tint, 0.74)!.withValues(alpha: 0.12),
    );
    // Fade from the left so the numbers stay readable.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(colors: [panel.withValues(alpha: 0.75), panel.withValues(alpha: 0)], stops: const [0, 0.63])
            .createShader(Offset.zero & size),
    );
  }

  @override
  bool shouldRepaint(_AmbientPainter old) => old.t != t || old.tint != tint || old.panel != panel;
}
