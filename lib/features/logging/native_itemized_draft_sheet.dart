import 'package:flutter/material.dart';
import '../../data/mediaflow_models.dart';
import '../../services/native_editing_workspace.dart';
import '../../services/native_itemized_parity.dart';
import '../../services/native_logging_parity_preview.dart';

/// Strictly an in-memory preview; never submits History or awards XP.
class NativeItemizedDraftSheet extends StatefulWidget {
  const NativeItemizedDraftSheet({
    super.key, required this.catalog, required this.title,
    required this.workspace,
  });
  final MediaFlowCatalog catalog;
  final MediaFlowTitle title;
  final NativeEditingWorkspace workspace;
  @override
  State<NativeItemizedDraftSheet> createState() => _NativeItemizedDraftSheetState();
}

class _NativeItemizedDraftSheetState extends State<NativeItemizedDraftSheet> {
  late String seasonId;
  late bool repeat;
  late TextEditingController units, duration;
  String? error;

  @override
  void initState() {
    super.initState();
    final existing = widget.workspace.itemizedDraft(widget.title.id);
    seasonId = existing?.seasonId ??
        (widget.title.seasons.isEmpty ? '' : widget.title.seasons.first.id);
    repeat = existing?.repeat ??
        NativeLoggingParityPreview.isCompleted(widget.title);
    final selected = widget.title.seasons.where((s) => s.id == seasonId);
    final start = selected.isEmpty ? widget.title.progress.floor() :
        selected.first.progress.floor();
    units = TextEditingController(
      text: existing == null ? '${start + 1}' : existing.unitNumbers.join(', '),
    );
    duration = TextEditingController(
      text: existing == null || existing.consumed == 0 ? '1200' :
          (existing.elapsedSeconds ~/ existing.consumed).toString(),
    );
  }

  @override
  void dispose() {
    units.dispose();
    duration.dispose();
    super.dispose();
  }

  List<int> _numbers() {
    final pieces = units.text.split(',');
    if (pieces.isEmpty || pieces.length > 10000) {
      throw const FormatException('Enter up to 10,000 unit numbers');
    }
    final result = <int>[];
    for (final part in pieces) {
      final parsed = int.tryParse(part.trim());
      if (parsed == null) {
        throw const FormatException('Use comma-separated whole unit numbers');
      }
      result.add(parsed);
    }
    return result;
  }

  NativeItemizedPreview? _preview() {
    try {
      final seconds = int.tryParse(duration.text.trim());
      if (seconds == null) return null;
      return NativeItemizedParity.calculate(
        title: widget.title, sessions: widget.catalog.sessions,
        seasonId: seasonId, numbers: _numbers(),
        secondsPerUnit: seconds, repeat: repeat,
      );
    } on FormatException {
      return null;
    }
  }

  void _stage() {
    try {
      final seconds = int.tryParse(duration.text.trim());
      if (seconds == null) throw const FormatException('Enter whole seconds');
      widget.workspace.stageItemizedLog(
        catalog: widget.catalog, titleId: widget.title.id,
        seasonId: seasonId, numbers: _numbers(),
        secondsPerUnit: seconds, repeat: repeat,
      );
      Navigator.pop(context);
    } on FormatException catch (e) {
      setState(() => error = e.message);
    } on StateError catch (e) {
      setState(() => error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final seasons = widget.title.seasons;
    final validIds = seasons.isEmpty || (
      seasons.every((s) => s.id.isNotEmpty) &&
      seasons.map((s) => s.id).toSet().length == seasons.length
    );
    return SafeArea(child: Padding(
      padding: EdgeInsets.fromLTRB(
        20, 8, 20, MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: SingleChildScrollView(child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Itemized logging preview',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 7),
          Text(widget.title.title, maxLines: 2,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 8),
          const Text('Read-only v252/v369/v394 preview. A gap in unit numbers '
              'does not advance confirmed progress. No History, XP or '
              'cloud changes are submitted.'),
          const SizedBox(height: 12),
          if (seasons.isNotEmpty && validIds)
            DropdownButtonFormField<String>(
              key: const Key('itemized-season-selector'),
              initialValue: seasonId,
              decoration: const InputDecoration(
                labelText: 'Season', border: OutlineInputBorder(),
              ),
              items: [
                for (final season in seasons)
                  DropdownMenuItem(value: season.id,
                      child: Text(season.name)),
              ],
              onChanged: (value) => setState(() {
                seasonId = value ?? seasonId;
                error = null;
              }),
            ),
          if (!validIds)
            const Text('Missing or duplicated season IDs. Preview blocked.'),
          const SizedBox(height: 10),
          SwitchListTile(
            key: const Key('itemized-repeat-switch'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Repeat / rewatch'),
            subtitle: const Text('Counts hypothetical History units, '
                'but never advances confirmed Library progress.'),
            value: repeat,
            onChanged: NativeLoggingParityPreview.isCompleted(widget.title)
                ? (value) => setState(() { repeat = value; error = null; })
                : null,
          ),
          TextField(
            controller: units,
            key: const Key('itemized-unit-numbers'),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Unit numbers (comma-separated)',
              helperText: 'Example: 4, 5, 7. A gap at 6 stops progress at 5.',
            ),
            onChanged: (_) => setState(() => error = null),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: duration,
            key: const Key('itemized-seconds-per-unit'),
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Seconds per unit',
            ),
            onChanged: (_) => setState(() => error = null),
          ),
          if (_preview() case final preview?) ...[
            const SizedBox(height: 12),
            Card(child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Season: ${preview.seasonName} · '
                      '${preview.consumed} hypothetical units'),
                  Text('Season progress: ${preview.beforeSeasonProgress} '
                      '→ ${preview.afterSeasonProgress}'),
                  Text('Title progress: ${preview.beforeTitleProgress} '
                      '→ ${preview.afterTitleProgress}'),
                  Text('Duration: ${preview.elapsedSeconds} seconds · '
                      'Archived units: ${preview.knownArchivedUnitCount}'),
                  Text('Projected status: ${preview.status}'),
                  const Text('Exact XP unavailable · History submitted: 0'),
                ],
              ),
            )),
          ],
          if (error != null)
            Padding(padding: const EdgeInsets.only(top: 12),
              child: Text(error!, key: const Key('itemized-draft-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: !validIds || widget.workspace.stale ? null : _stage,
            icon: const Icon(Icons.playlist_add_outlined),
            label: const Text('Keep local itemized draft'),
          ),
        ],
      )),
    ));
  }
}
