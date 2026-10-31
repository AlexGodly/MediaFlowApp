import 'package:flutter/material.dart';

import '../data/account_controller.dart';
import '../state/models.dart';
import 'theme.dart';
import 'widgets.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, required this.account});
  final AccountController account;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _search = TextEditingController();
  bool _showSkipped = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final view = widget.account.view!;
    final q = _search.text.trim().toLowerCase();
    final logs = view.logs.where((l) {
      if (l.skipped && !_showSkipped) return false;
      if (q.isNotEmpty && !l.titleSummary.toLowerCase().contains(q)) return false;
      return true;
    }).toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    // Flat list of day headers and log rows.
    final rows = <Object>[];
    String? day;
    final todayIso = isoDay(DateTime.now());
    var todayMinutes = 0.0, todayXP = 0.0;
    for (final l in logs) {
      final d = l.date.isNotEmpty ? l.date : isoDay(DateTime.fromMillisecondsSinceEpoch(l.timestamp));
      if (d != day) {
        rows.add(d);
        day = d;
      }
      rows.add(l);
      if (d == todayIso && !l.skipped) {
        todayMinutes += l.minutes;
        todayXP += l.xp;
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('History'), actions: [SyncIndicator(account: widget.account)]),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(hintText: 'Search logs', prefixIcon: Icon(Icons.search_rounded)),
              ),
            ),
            const SizedBox(width: 8),
            FilterChip(
              label: const Text('Skipped'),
              selected: _showSkipped,
              onSelected: (v) => setState(() => _showSkipped = v),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(children: [
            _Stat(label: 'Today', value: fmtMinutes(todayMinutes)),
            const SizedBox(width: 8),
            _Stat(label: 'XP today', value: '+${fmtNumber(todayXP)}'),
            const SizedBox(width: 8),
            _Stat(label: 'All logs', value: fmtNumber(view.logs.where((l) => !l.skipped).length)),
          ]),
        ),
        Expanded(
          child: rows.isEmpty
              ? const EmptyState(icon: Icons.history_rounded, title: 'No logs yet', body: 'Tap Log to record what you watched or read.')
              : RefreshIndicator(
                  onRefresh: widget.account.sync,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 96),
                    itemCount: rows.length,
                    itemBuilder: (context, i) {
                      final row = rows[i];
                      if (row is String) {
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
                          child: Text(fmtDay(row),
                              style: const TextStyle(color: MF.accent, fontWeight: FontWeight.w800, letterSpacing: 0.3)),
                        );
                      }
                      final log = row as LogRecord;
                      return _LogRow(log: log, category: view.category(log.categoryId));
                    },
                  ),
                ),
        ),
      ]),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: MF.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: MF.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          Text(label, style: const TextStyle(color: MF.textDim, fontSize: 12)),
        ]),
      ),
    );
  }
}

class _LogRow extends StatelessWidget {
  const _LogRow({required this.log, required this.category});
  final LogRecord log;
  final Category category;

  @override
  Widget build(BuildContext context) {
    final unit = log.unit.isEmpty ? category.unit : log.unit;
    final dim = log.skipped;
    final detail = log.skipped
        ? 'Skipped'
        : '${fmtNumber(log.amount)} ${unitLabel(unit, log.amount)} · ${fmtMinutes(log.minutes)} · +${fmtNumber(log.xp)} XP';
    final repeat = log.titles.any((t) => t['repeat'] == true);
    return Opacity(
      opacity: dim ? 0.55 : 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CategoryBadge(category, size: 38),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(log.titleSummary.isEmpty ? category.name : log.titleSummary,
                  maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(detail, style: const TextStyle(color: MF.textDim, fontSize: 12.5)),
              if (log.note.isNotEmpty && log.titles.isNotEmpty && log.note != log.titleSummary)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(log.note, maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: MF.textDim, fontSize: 12.5, fontStyle: FontStyle.italic)),
                ),
            ]),
          ),
          if (repeat)
            const Padding(
              padding: EdgeInsets.only(left: 6),
              child: Tooltip(message: 'Rewatch / reread', child: Icon(Icons.replay_rounded, size: 18, color: MF.accent)),
            ),
        ]),
      ),
    );
  }
}
