// Choosing a cover (Cover Recovery reviews, Quick Title Recovery, "Search
// manually"): every candidate shows its full title, the name that matched
// ("also known as"), year, source, format, how sure the match is and the IDs
// it would link; tapping the cover opens a large preview.

import 'package:flutter/material.dart';

import '../data/account_controller.dart';
import '../data/recovery_runner.dart';
import '../logic/recovery.dart';
import '../util/js.dart';
import 'presence.dart';
import 'theme.dart';

/// The match level the website's confidences stand for.
(String, Color) coverMatchLevel(CoverCandidate c) {
  if (c.idMatch && c.confidence >= 0.95) return ('Saved ID + title', MF.good);
  if (c.confidence >= 0.95) return ('Title + year', MF.good);
  if (c.idMatch) return ('Saved ID · different title', MF.warn);
  if (c.confidence >= 0.65) return ('Title only', const Color(0xFF7FB2FF));
  if (c.confidence >= 0.3) return ('Different year', MF.warn);
  return ('Not matched', MF.textDim);
}

/// The record's name that matched [itemTitle], when it isn't the one shown.
String? coverAlsoKnownAs(CoverCandidate c, String itemTitle) {
  final wanted = coverNorm(cleanTitle(itemTitle));
  if (wanted.isEmpty || coverNorm(c.title) == wanted) return null;
  for (final n in c.altTitles) {
    if (coverNorm(n) == wanted) return n;
  }
  return null;
}

String _ids(CoverCandidate c) => c.ids.map((x) => '${x.$1.toUpperCase()} ${x.$2}').join(' · ');

Future<void> showCoverPreview(BuildContext context, CoverCandidate c, String itemTitle, {VoidCallback? onUse}) {
  final (level, color) = coverMatchLevel(c);
  final aka = coverAlsoKnownAs(c, itemTitle);
  return showDialog<void>(
    context: context,
    builder: (d) => Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: InteractiveViewer(
                child: Image.network(c.url,
                    fit: BoxFit.contain,
                    height: MediaQuery.sizeOf(context).height * .55,
                    errorBuilder: (_, __, ___) => Container(height: 240, color: MF.surface, child: const Icon(Icons.broken_image_outlined))),
              ),
            ),
            const SizedBox(height: 12),
            SelectableText(c.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            if (aka != null) Text('Also known as: $aka', style: TextStyle(color: MF.textDim)),
            const SizedBox(height: 4),
            Text([sourceLabelFor(c.provider), if (c.year != null && c.year! > 0) '${c.year}', if (c.format.isNotEmpty) c.format].join(' · '),
                style: TextStyle(color: MF.textDim)),
            Text('$level · ${(c.confidence * 100).round()}% · ${c.reason}', style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
            if (c.ids.isNotEmpty) Text(_ids(c), style: TextStyle(color: MF.textDim, fontSize: 12)),
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(onPressed: () => Navigator.pop(d), child: const Text('Close')),
              if (onUse != null)
                FilledButton(
                  onPressed: () {
                    Navigator.pop(d);
                    onUse();
                  },
                  child: const Text('Use this cover'),
                ),
            ]),
          ]),
        ),
      ),
    ),
  );
}

String sourceLabelFor(String provider) => const {
      'anilist': 'AniList',
      'tvmaze': 'TVmaze',
      'openlibrary': 'Open Library',
      'itunes': 'iTunes',
      'tmdb': 'TMDB',
      'kitsu': 'Kitsu',
      'jikan': 'Jikan',
    }[provider] ??
    provider;

/// A wrapping grid of candidates with their full details.
class CoverChoiceGrid extends StatelessWidget {
  const CoverChoiceGrid({super.key, required this.itemTitle, required this.candidates, required this.onPick, this.selectedUrl});
  final String itemTitle;
  final List<CoverCandidate> candidates;
  final ValueChanged<CoverCandidate> onPick;

  /// Marks the chosen cover (Quick Title Recovery picks before saving).
  final String? selectedUrl;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final cols = (box.maxWidth / 150).floor().clamp(2, 6);
      const gap = 8.0;
      final w = (box.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(spacing: gap, runSpacing: gap, children: [
        for (final c in candidates)
          SizedBox(width: w, child: _CoverTile(c: c, itemTitle: itemTitle, selected: c.url == selectedUrl, onPick: () => onPick(c))),
      ]);
    });
  }
}

class _CoverTile extends StatelessWidget {
  const _CoverTile({required this.c, required this.itemTitle, required this.onPick, this.selected = false});
  final bool selected;
  final CoverCandidate c;
  final String itemTitle;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final (level, color) = coverMatchLevel(c);
    final aka = coverAlsoKnownAs(c, itemTitle);
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
          color: MF.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? MF.accent : MF.border, width: selected ? 2 : 1)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          onTap: () => showCoverPreview(context, c, itemTitle, onUse: onPick),
          borderRadius: BorderRadius.circular(8),
          child: AspectRatio(
            aspectRatio: 2 / 3,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(c.url, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: MF.raised, child: const Icon(Icons.broken_image_outlined))),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(c.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
        if (aka != null) Text('aka $aka', style: TextStyle(color: MF.textDim, fontSize: 11)),
        Text([sourceLabelFor(c.provider), if (c.year != null && c.year! > 0) '${c.year}', if (c.format.isNotEmpty) c.format].join(' · '),
            style: TextStyle(color: MF.textDim, fontSize: 11)),
        Text(level, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
        if (c.ids.isNotEmpty) Text(_ids(c), style: TextStyle(color: MF.textDim, fontSize: 10)),
        const SizedBox(height: 4),
        FilledButton.tonal(
          onPressed: onPick,
          style: FilledButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 6)),
          child: Text(selected ? 'Selected' : 'Use', style: const TextStyle(fontSize: 12)),
        ),
      ]),
    );
  }
}

/// "Search manually": search any name and pick from every result (nothing
/// is filtered out by confidence). Returns the chosen cover.
Future<CoverCandidate?> searchCoverManually(BuildContext context, AccountController account, Map<String, dynamic> item) {
  return Navigator.of(context).push<CoverCandidate>(MaterialPageRoute(builder: (_) => _ManualCoverSearch(account: account, item: item)));
}

class _ManualCoverSearch extends StatefulWidget {
  const _ManualCoverSearch({required this.account, required this.item});
  final AccountController account;
  final Map<String, dynamic> item;

  @override
  State<_ManualCoverSearch> createState() => _ManualCoverSearchState();
}

class _ManualCoverSearchState extends State<_ManualCoverSearch> {
  late final _q = TextEditingController(text: cleanTitle(widget.item['title']));
  List<CoverCandidate>? _results;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final q = _q.text.trim();
    if (q.isEmpty) return;
    setState(() => _busy = true);
    final found = await RecoveryRunner.instance.coverCandidates(widget.account, widget.item, query: q, manual: true);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _results = found;
    });
  }

  @override
  Widget build(BuildContext context) {
    final title = cleanTitle(widget.item['title']);
    final year = jsStr(widget.item['year']);
    return PresenceScope(
      info: const PresenceInfo(situation: 'recovery', values: {'action': 'Searching for a cover'}),
      child: Scaffold(
        appBar: AppBar(title: const Text('Search manually')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          Text('Looking for: $title${year.isEmpty ? '' : ' ($year)'}', style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _q,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _search(),
                decoration: const InputDecoration(labelText: 'Search for', prefixIcon: Icon(Icons.search_rounded)),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(onPressed: _busy ? null : _search, child: const Text('Search')),
          ]),
          const SizedBox(height: 14),
          if (_busy) const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
          if (!_busy && _results != null && _results!.isEmpty)
            Text('Nothing found. Try another name (the original or English title often works).', style: TextStyle(color: MF.textDim)),
          if (!_busy && (_results?.isNotEmpty ?? false))
            CoverChoiceGrid(itemTitle: title, candidates: _results!, onPick: (c) => Navigator.pop(context, c)),
        ]),
      ),
    );
  }
}
