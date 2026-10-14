// ignore_for_file: prefer_interpolation_to_compose_strings
import 'package:flutter/material.dart';

import '../../data/mediaflow_library_repository.dart';
import '../../data/mediaflow_models.dart';
import '../../services/native_action_xp_parity.dart';

/// Read-only diagnostics: never mutate account settings or XP ledgers.
class NativeXpLedgerAuditPanel extends StatefulWidget {
  const NativeXpLedgerAuditPanel({super.key, required this.repository});
  final MediaFlowLibraryRepository repository;

  @override
  State<NativeXpLedgerAuditPanel> createState() =>
      _NativeXpLedgerAuditPanelState();
}

class _NativeXpLedgerAuditPanelState extends State<NativeXpLedgerAuditPanel> {
  late Future<MediaFlowCatalog> _catalog;
  String kind = 'collectionAddTitleXP';
  int streak = 2;

  @override
  void initState() {
    super.initState();
    _catalog = widget.repository.load();
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: FutureBuilder<MediaFlowCatalog>(
        future: _catalog,
        builder: (context, snapshot) {
          final evidence = snapshot.data?.xpEvidence;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Native XP & ledger audit',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              const Text('Reads the existing MediaFlow snapshot. '
                  'Does not award, modify, or synchronize XP.'),
              if (snapshot.hasError)
                const Text('XP diagnostics unavailable. No data modified.'),
              if (!snapshot.hasData && !snapshot.hasError)
                const LinearProgressIndicator(),
              if (evidence != null) ...[
                const SizedBox(height: 10),
                Text('Leveling: ' +
                    (evidence.levelingEnabled ? 'enabled' : 'disabled') +
                    ' · Universal streak: ' +
                    (evidence.globalStreakEnabled ? 'enabled' : 'disabled')),
                if (!evidence.settingsPresent)
                  const Text('Leveling settings were not present. Website '
                      'defaults are assumed for the hypothetical example.'),
                if (!evidence.ledgerPresent)
                  const Text('XP ledger unavailable; account totals incomplete.'),
                const SizedBox(height: 8),
                Text(
                  'Known v348 bonus ledger total: ' +
                    evidence.knownExtraXp.toStringAsFixed(1) + ' XP',
                  key: const Key('native-xp-known-extra'),
                ),
                Text('Action events: ' +
                  evidence.actionEventCount.toString() +
                  ' · Logged completion ledger entries: ' +
                  (evidence.ledgerCounts['logCompletions'] ?? 0).toString()),
                if (evidence.invalidLedgerValues > 0)
                  Text('Unverifiable ledger values: ' +
                      evidence.invalidLedgerValues.toString(),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      )),
                const SizedBox(height: 10),
                Text('Source-grounded action XP example',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  key: const Key('native-xp-action'),
                  initialValue: kind,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(), labelText: 'Action',
                  ),
                  items: [
                    for (final name in NativeActionXpParity.defaultRates.keys)
                      DropdownMenuItem(
                        value: name,
                        child: Text(name, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (value) => setState(() => kind = value ?? kind),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<int>(
                  key: const Key('native-xp-streak'),
                  initialValue: streak,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Hypothetical day streak',
                  ),
                  items: const [
                    DropdownMenuItem(value: 1, child: Text('1 day')),
                    DropdownMenuItem(value: 2, child: Text('2 days')),
                    DropdownMenuItem(value: 7, child: Text('7 days')),
                    DropdownMenuItem(value: 30, child: Text('30 days')),
                  ],
                  onChanged: (value) =>
                      setState(() => streak = value ?? streak),
                ),
                const SizedBox(height: 8),
                Builder(builder: (context) {
                  final demo = NativeActionXpParity.action(
                    settings: evidence, kind: kind, amount: 1, streak: streak,
                  );
                  return Text('One hypothetical action: ' +
                      demo.provisionalXp.toString() + ' XP (base ' +
                      demo.baseXp.toStringAsFixed(1) + ', streak ×' +
                      demo.streakMultiplier.toStringAsFixed(2) + ')',
                      key: const Key('native-xp-hypothetical'));
                }),
                const SizedBox(height: 8),
                const Text('Diagnostic only: NOT total account XP, a '
                    'guaranteed reward, full v410 parity, or a cloud write. '
                    'Other XP ledgers and rewards are excluded.'),
              ],
            ],
          );
        },
      ),
    ),
  );
}
