import 'package:flutter/material.dart';
import 'mediaflow_theme.dart';

/// Lightweight, entirely native MediaFlow atmosphere shared by every page.
/// Uses theme tokens, no cover/network dependency and no continuous animation.
/// AMOLED remains truly black to protect contrast and battery life.
class MfAmbientBackdrop extends StatelessWidget {
  const MfAmbientBackdrop({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = MediaFlowTokens.of(context);
    if (tokens.background == Colors.black) {
      return ColoredBox(color: tokens.background, child: child);
    }
    final light = Theme.of(context).brightness == Brightness.light;
    return Stack(fit: StackFit.expand, children: [
      DecoratedBox(
        decoration: BoxDecoration(gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            tokens.background,
            Color.alphaBlend(tokens.accent.withValues(alpha: light ? 0.035 : 0.045),
              tokens.background),
            tokens.background,
          ],
          stops: const [0, 0.43, 1],
        )),
        child: const SizedBox.expand(),
      ),
      Positioned(
        top: -250, right: -180,
        child: IgnorePointer(child: Container(
          width: 550, height: 550,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [tokens.accent.withValues(alpha: light ? 0.08 : 0.13),
                tokens.accent.withValues(alpha: 0)],
            ),
          ),
        )),
      ),
      Positioned(
        bottom: -320, left: -210,
        child: IgnorePointer(child: Container(
          width: 620, height: 620,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [tokens.due.withValues(alpha: light ? 0.055 : 0.095),
                tokens.due.withValues(alpha: 0)],
            ),
          ),
        )),
      ),
      child,
    ]);
  }
}
