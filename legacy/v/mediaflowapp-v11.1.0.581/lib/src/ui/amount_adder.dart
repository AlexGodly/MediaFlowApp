// Website v580: the "+ add" bar under an Amount box. Type the next amount and
// press + (or Enter): it is added to the box, and the sum is shown
// ("3 + 4 = 7"), so nobody has to add in their head. The box still holds the
// amount; the bar only adds to it.

import 'package:flutter/material.dart';

import '../logic/title_parts.dart' show fmtN;
import 'theme.dart';

class AmountAdder extends StatefulWidget {
  const AmountAdder({super.key, required this.sumKey, required this.current, required this.onTotal});

  /// Which box this is (stays the same across rebuilds).
  final String sumKey;

  /// The box's amount now.
  final double current;

  /// Sets the box to the new total.
  final void Function(double total) onTotal;

  /// The additions per box, while the app runs.
  static final Map<String, List<double>> sums = {};

  /// "3 + 4 = 7", or null (one amount, or the box was changed by hand).
  static String? sumText(String key, double current) {
    final list = sums[key];
    if (list == null || list.length < 2) return null;
    final total = list.fold(0.0, (a, b) => a + b);
    if (total != current) {
      sums.remove(key);
      return null;
    }
    return '${list.map(fmtN).join(' + ')} = ${fmtN(total)}';
  }

  /// The list after adding [n] to a box at [before].
  static List<double> push(String key, double before, double n) {
    final prev = sums[key];
    final list = prev != null && prev.fold(0.0, (a, b) => a + b) == before
        ? [...prev, n]
        : before > 0
            ? [before, n]
            : [n];
    sums[key] = list;
    return list;
  }

  @override
  State<AmountAdder> createState() => _AmountAdderState();
}

class _AmountAdderState extends State<AmountAdder> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _add() {
    final n = (double.tryParse(_ctrl.text.trim().replaceAll(',', '.')) ?? 0).floorToDouble();
    if (n <= 0) {
      _focus.requestFocus();
      return;
    }
    final before = widget.current < 0 ? 0.0 : widget.current.floorToDouble();
    AmountAdder.push(widget.sumKey, before, n);
    _ctrl.clear();
    widget.onTotal(before + n);
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final sum = AmountAdder.sumText(widget.sumKey, widget.current);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(children: [
        SizedBox(
          width: 104,
          child: TextField(
            controller: _ctrl,
            focusNode: _focus,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(isDense: true, hintText: '+ add'),
            onSubmitted: (_) => _add(),
          ),
        ),
        const SizedBox(width: 6),
        IconButton.filledTonal(
          tooltip: 'Add to the amount',
          visualDensity: VisualDensity.compact,
          onPressed: _add,
          icon: const Icon(Icons.add_rounded, size: 18),
        ),
        if (sum != null) ...[
          const SizedBox(width: 8),
          Flexible(
            child: Text(sum,
                overflow: TextOverflow.ellipsis, style: TextStyle(color: MF.accent, fontSize: 12.5, fontWeight: FontWeight.w800)),
          ),
        ],
      ]),
    );
  }
}
