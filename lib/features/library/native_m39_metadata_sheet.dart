import 'package:flutter/material.dart';
import '../../data/mediaflow_models.dart';
import '../../services/native_m37_library_plan.dart';

class _SeasonRow {
  _SeasonRow(MediaFlowSeason season)
      : id = season.id, original = season,
        name = TextEditingController(text: season.name),
        number = TextEditingController(
          text: season.number?.toInt().toString() ?? ''),
        progress = TextEditingController(text: season.progress.toInt().toString()),
        total = TextEditingController(text: season.total?.toInt().toString() ?? '');
  final String id;
  final MediaFlowSeason original;
  final TextEditingController name, number, progress, total;
  void dispose() {
    name.dispose(); number.dispose(); progress.dispose(); total.dispose();
  }
}

/// v377 external IDs / v252 Seasons editor. All changes stay in the existing
/// owner-scoped, RAM-only local M37 plan. Never fetches or verifies providers.
class NativeM39MetadataSheet extends StatefulWidget {
  const NativeM39MetadataSheet({
    super.key, required this.plan, required this.titleId,
  });
  final NativeM37LibraryPlan plan;
  final String titleId;

  @override
  State<NativeM39MetadataSheet> createState() => _NativeM39MetadataSheetState();
}

class _NativeM39MetadataSheetState extends State<NativeM39MetadataSheet> {
  late final NativeM37Fields original;
  final Map<String,TextEditingController> ids = {};
  final List<_SeasonRow> seasons = [];
  String? error;
  int serial = 0;

  @override
  void initState() {
    super.initState();
    original = widget.plan.fieldsFor(widget.titleId);
    final keys = {
      'mal','simkl','anilist','tmdb','imdb','trakt','kitsu','isbn',
      ...original.externalIds.keys, ...original.manualExternalIds.keys,
    };
    for (final key in keys) {
      ids[key] = TextEditingController(text: original.externalIds[key] ?? '');
    }
    for (final season in original.seasons) {
      seasons.add(_SeasonRow(season));
    }
  }

  @override
  void dispose() {
    for (final controller in ids.values) {
      controller.dispose();
    }
    for (final row in seasons) {
      row.dispose();
    }
    super.dispose();
  }

  String _newId() => 'local-m39-${DateTime.now().microsecondsSinceEpoch}-${serial++}';

  void _addSeason() {
    setState(() {
      if (seasons.isEmpty && (original.progress > 0 ||
          (original.total ?? 0) > 0)) {
        seasons.add(_SeasonRow(MediaFlowSeason(
          'Unassigned', original.progress, original.total,
          id: _newId(), synthetic: true, manual: true, source: 'manual',
        )));
      }
      final number = seasons.where((r) =>
        int.tryParse(r.number.text) != null).fold<int>(
          0, (v,r) => int.parse(r.number.text) > v
              ? int.parse(r.number.text) : v) + 1;
      seasons.add(_SeasonRow(MediaFlowSeason(
        'Season $number', 0, null, id: _newId(),
        number: number.toDouble(), source:'manual', manual:true,
      )));
    });
  }

  int _integer(String text, String field, {bool optional = false}) {
    if (optional && text.trim().isEmpty) return -1;
    final v = int.tryParse(text.trim());
    if (v == null || v < 0) {
      throw FormatException('$field must be a non-negative whole number');
    }
    return v;
  }

  void _stage() {
    try {
      final changes = <String,String?>{};
      for (final entry in ids.entries) {
        final current = entry.value.text.trim();
        final previous = original.externalIds[entry.key] ?? '';
        if (current != previous) changes[entry.key] =
            current.isEmpty ? null : current;
      }
      final rows = <MediaFlowSeason>[];
      for (final r in seasons) {
        final number = _integer(r.number.text,'Season number',optional:true);
        final progress = _integer(r.progress.text,'Season progress');
        final total = _integer(r.total.text,'Season total',optional:true);
        final candidate = MediaFlowSeason(
          r.name.text.trim(), progress.toDouble(),
          total < 0 ? null : total.toDouble(), id: r.id,
          number: number < 0 ? null : number.toDouble(),
          source: r.original.source, manual: r.original.manual,
          synthetic: r.original.synthetic,
        );
        final unchanged = candidate.name == r.original.name &&
          candidate.number == r.original.number &&
          candidate.progress == r.original.progress &&
          candidate.total == r.original.total;
        rows.add(unchanged ? r.original : MediaFlowSeason(
          candidate.name, candidate.progress, candidate.total,
          id: candidate.id, number: candidate.number,
          source:'manual', manual:true,
          synthetic: candidate.synthetic,
        ));
      }
      widget.plan.editM39(widget.titleId,
        idChanges: changes,
        seasons: rows.isEmpty && original.seasons.isEmpty ? null : rows);
      Navigator.pop(context);
    } on FormatException catch (e) {
      if (mounted) setState(() => error = e.message);
    } on StateError catch (e) {
      if (mounted) setState(() => error = e.message);
    }
  }

  Widget _input(String label, TextEditingController controller,
    {String? keyName, bool numeric = false}) => TextField(
    key: keyName == null ? null : Key(keyName),
    controller: controller,
    keyboardType: numeric ? TextInputType.number : TextInputType.text,
    decoration: InputDecoration(labelText: label, isDense: true,
      border: const OutlineInputBorder()),
  );

  @override
  Widget build(BuildContext context) => SafeArea(child: Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: FractionallySizedBox(
      heightFactor: .93,
      child: ListView(
        key: const Key('m39-metadata-sheet'),
        padding: const EdgeInsets.all(18),
        children: [
          Text('External IDs & Seasons',
            style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text('LOCAL PREVIEW ONLY · No provider requests or account '
            'updates. Clearing a saved ID stores an intentional manual-clear '
            'marker in this device draft. Unknown website fields are not '
            'reconstructed from this preview.'),
          const SizedBox(height: 18),
          Text('External Media IDs',style:Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          for (final entry in ids.entries) ...[
            _input(entry.key.toUpperCase(), entry.value,
              keyName:'m39-id-${entry.key}'),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: Text('Seasons View',
              style: Theme.of(context).textTheme.titleMedium)),
            OutlinedButton.icon(
              key: const Key('m39-add-season'),
              onPressed: widget.plan.stale ? null : _addSeason,
              icon: const Icon(Icons.add),
              label: const Text('Add season')),
          ]),
          const Text('When seasons exist, overall progress and total are '
            'derived from the season rows. Removing every season from an '
            'existing seasonal title is disabled until full sync parity.'),
          const SizedBox(height: 10),
          for (final r in seasons) ...[
            Card(key: Key('m39-season-${r.id}'), child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(children: [
                Row(children: [
                  Expanded(child: Text(r.original.source.isEmpty
                    ? 'Season' : 'Source: ${r.original.source}')),
                  IconButton(
                    tooltip:'Remove local season row',
                    onPressed: widget.plan.stale ? null : () => setState(() {
                      seasons.remove(r);
                      // Dispose after this widget tree has rebuilt.
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        r.dispose();
                      });
                    }),
                    icon: const Icon(Icons.close)),
                ]),
                _input('Season name',r.name),
                const SizedBox(height: 8),
                Wrap(spacing:8,runSpacing:8,children:[
                  SizedBox(width:95,child:_input('#',r.number,numeric:true)),
                  SizedBox(width:115,child:_input('Progress',r.progress,
                    numeric:true)),
                  SizedBox(width:115,child:_input('Total',r.total,numeric:true)),
                ]),
              ]),
            )),
            const SizedBox(height: 8),
          ],
          if (error != null) Padding(
            padding: const EdgeInsets.symmetric(vertical:8),
            child: Text(error!, key:const Key('m39-metadata-error'),
              style:TextStyle(color:Theme.of(context).colorScheme.error))),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const Key('m39-stage-metadata'),
            onPressed: widget.plan.stale ? null : _stage,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Stage metadata locally')),
          const SizedBox(height: 8),
          Text('Original source, History, XP, Personal Order, and '
            'Collections remain unchanged.',
            style:Theme.of(context).textTheme.bodySmall),
        ],
      ),
    ),
  ));
}
