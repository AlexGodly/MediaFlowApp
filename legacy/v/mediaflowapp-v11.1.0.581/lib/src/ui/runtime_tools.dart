// Website v580: "Use stopwatch time" / "Use runtime calculator" under every
// "Customize total runtime" (Advanced logging, Log any title / Batch Log).

import 'package:flutter/material.dart';

import '../logic/extras.dart' show toolTimeSeconds;

class RuntimeToolButtons extends StatelessWidget {
  const RuntimeToolButtons({super.key, required this.state, required this.onSeconds});

  /// The account now (the Stopwatch and Runtime Calculator live in it).
  final Map<String, dynamic>? Function() state;
  final void Function(int seconds) onSeconds;

  void _use(BuildContext context, String source) {
    final s = state();
    if (s == null) return;
    final r = toolTimeSeconds(s, source, DateTime.now().millisecondsSinceEpoch);
    if (r.error != null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(r.error!)));
      return;
    }
    onSeconds(r.seconds);
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(spacing: 8, runSpacing: 6, children: [
      OutlinedButton.icon(
        onPressed: () => _use(context, 'stopwatch'),
        icon: const Icon(Icons.timer_outlined, size: 18),
        label: const Text('Use stopwatch time'),
      ),
      OutlinedButton.icon(
        onPressed: () => _use(context, 'calculator'),
        icon: const Icon(Icons.calculate_outlined, size: 18),
        label: const Text('Use runtime calculator'),
      ),
    ]);
  }
}
