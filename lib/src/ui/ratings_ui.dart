// External ratings and External IDs (website v555): the ratings on Title
// Details with "Refresh ratings", the External IDs editor with the ID finder
// ("Discover verified External IDs"), and Settings' "Refresh all missing
// ratings".

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/account_controller.dart';
import '../data/rating_sources.dart';
import '../data/ratings_refresh.dart';
import '../logic/ratings_engine.dart';
import '../util/js.dart';
import 'presence.dart';
import 'theme.dart';
import 'widgets.dart';

void _toast(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 3)));

const _sourceLabels = {
  'all': 'All sites', 'jikan': 'MyAnimeList (Jikan)', 'anilist': 'AniList', 'kitsu': 'Kitsu', 'tvmaze': 'TVmaze',
  'tmdb': 'TMDB', 'omdb': 'IMDb (OMDb)', 'malofficial': 'MyAnimeList Official', 'trakt': 'Trakt', 'simkl': 'SIMKL',
  'watchmode': 'Watchmode', 'animeschedule': 'AnimeSchedule', 'metron': 'Metron', 'episodate': 'EpisoDate',
  'gutendex': 'Gutendex', 'fanart': 'Fanart.tv', 'vndb': 'VNDB', 'openlibrary': 'Open Library', 'itunes': 'Apple iTunes',
  'steam': 'Steam Store', 'musicbrainz': 'MusicBrainz',
};
String sourceLabel(String id) => _sourceLabels[id] ?? id;

/// The ratings part of Title Details.
class ExternalRatingsSection extends StatelessWidget {
  const ExternalRatingsSection({super.key, required this.account, required this.item});
  final AccountController account;
  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final id = jsStr(item['id']);
    final rows = ratingRows(item);
    final ids = (asMap(item['externalIds']) ?? const {}).entries.where((e) => jsStr(e.value).trim().isNotEmpty).toList();
    return ListenableBuilder(
      listenable: RatingsRefresh.instance,
      builder: (context, _) {
        final r = RatingsRefresh.instance;
        final mine = r.titleId == id;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Expanded(child: Text('External ratings', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
            if (mine)
              TextButton.icon(onPressed: r.stop, icon: const Icon(Icons.stop_rounded, size: 18), label: const Text('Stop'))
            else
              TextButton.icon(
                onPressed: r.working
                    ? null
                    : () async {
                        final res = await r.refresh(account, id);
                        if (context.mounted) _toast(context, res.note);
                      },
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Refresh ratings'),
              ),
          ]),
          if (mine)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(children: [
                const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 8),
                Expanded(child: Text(r.note, style: TextStyle(color: MF.textDim, fontSize: 12))),
              ]),
            ),
          if (rows.isEmpty && !mine)
            Text('No external ratings yet. Refresh ratings uses saved IDs first, then finds missing IDs.',
                style: TextStyle(color: MF.textDim, fontSize: 13)),
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                SizedBox(width: 170, child: Text(row.$1, style: TextStyle(color: MF.textDim))),
                Expanded(child: Text(row.$2, style: const TextStyle(fontWeight: FontWeight.w700))),
                if (row.$3.isNotEmpty) Text(sourceLabel(row.$3), style: TextStyle(color: MF.textMute, fontSize: 11)),
              ]),
            ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: Text('External IDs · ${ids.length} saved', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            ),
            TextButton.icon(
              onPressed: () => showExternalIds(context, account, id),
              icon: const Icon(Icons.tag_rounded, size: 18),
              label: const Text('Edit / find IDs'),
            ),
          ]),
          if (ids.isNotEmpty)
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final e in ids)
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text('${idLabel(e.key)}: ${jsStr(e.value)}', style: const TextStyle(fontSize: 12)),
                ),
            ]),
        ]);
      },
    );
  }
}

/// Opens the External IDs editor with the ID finder.
Future<void> showExternalIds(BuildContext context, AccountController account, String id) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: MF.surface,
    builder: (c) => PresenceScope(
      info: const PresenceInfo(details: 'Finding title IDs'),
      child: SizedBox(height: MediaQuery.sizeOf(c).height * 0.92, child: _IdsEditor(account: account, id: id)),
    ),
  );
}

class _Candidate {
  _Candidate(this.key, this.value, this.title, this.year, this.type, this.exact, this.link);
  final String key, value, title, type, link;
  int year;
  bool exact;
  final Set<String> sources = {};
}

const _idLinks = {
  'imdb': 'https://www.imdb.com/title/', 'tmdb': 'https://www.themoviedb.org/movie/', 'tmdb_tv': 'https://www.themoviedb.org/tv/',
  'mal': 'https://myanimelist.net/anime/', 'anilist': 'https://anilist.co/anime/', 'kitsu': 'https://kitsu.io/anime/',
  'tvmaze': 'https://www.tvmaze.com/shows/',
};

/// `MF555ID_KEYS` order for the result groups.
const _groupOrder = [
  'imdb', 'tmdb', 'tmdb_tv', 'mal', 'anilist', 'kitsu', 'tvmaze', 'trakt', 'simkl', 'tvdb_series', 'anidb', 'animeschedule',
  'watchmode', 'metron_series', 'gcd_series', 'comicvine_volume', 'episodate', 'gutendex',
];
const _groupLabels = {
  'imdb': 'IMDb', 'tmdb': 'TMDB Movie', 'tmdb_tv': 'TMDB TV', 'mal': 'MyAnimeList', 'anilist': 'AniList', 'kitsu': 'Kitsu',
  'tvmaze': 'TVmaze', 'trakt': 'Trakt', 'simkl': 'SIMKL', 'tvdb_series': 'TheTVDB', 'anidb': 'AniDB',
  'animeschedule': 'AnimeSchedule', 'watchmode': 'Watchmode', 'metron_series': 'Metron', 'gcd_series': 'Grand Comics Database',
  'comicvine_volume': 'Comic Vine', 'episodate': 'EpisoDate', 'gutendex': 'Gutendex',
};

const _publicFinder = ['jikan', 'anilist', 'kitsu', 'tvmaze'];
const _coverGateway = ['tmdb', 'omdb', 'fanart', 'animeschedule', 'malofficial', 'episodate', 'gutendex'];
const _mappingGateway = ['metron', 'trakt', 'watchmode'];

class _IdsEditor extends StatefulWidget {
  const _IdsEditor({required this.account, required this.id});
  final AccountController account;
  final String id;

  @override
  State<_IdsEditor> createState() => _IdsEditorState();
}

class _IdsEditorState extends State<_IdsEditor> {
  final Map<String, TextEditingController> _fields = {};
  final _filter = TextEditingController();
  final _query = TextEditingController();
  String _site = 'all';
  bool _busy = false;
  StopToken? _stop;
  final Map<String, (String, String)> _status = {}; // provider → (state, note)
  final Map<String, Map<String, _Candidate>> _results = {};
  final Map<String, String> _chosen = {};

  Map<String, dynamic>? get _item {
    for (final raw in asList(widget.account.view?.state['library'])) {
      final m = asMap(raw);
      if (m != null && jsStr(m['id']) == widget.id) return m;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    final item = _item ?? const <String, dynamic>{};
    final ids = asMap(item['externalIds']) ?? const <String, dynamic>{};
    final keys = [for (final k in kIdKeys) k.$1];
    for (final k in ids.keys) {
      if (!keys.contains(k) && RegExp(r'^[a-z][a-z0-9_]{0,32}$', caseSensitive: false).hasMatch(k)) keys.add(k);
    }
    for (final k in keys) {
      _fields[k] = TextEditingController(text: jsStr(ids[k]));
    }
    _query.text = cleanTitle(item['title']);
  }

  @override
  void dispose() {
    _stop?.stop();
    for (final c in _fields.values) {
      c.dispose();
    }
    _filter.dispose();
    _query.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final edited = {for (final e in _fields.entries) e.key: e.value.text.trim()};
    for (final e in edited.entries) {
      if (!idValid(e.key, e.value)) {
        _toast(context, 'Invalid ${e.key.toUpperCase()} ID. Please correct it before saving.');
        return;
      }
    }
    var changed = false;
    await widget.account.edit((s, now) {
      for (final raw in asList(s['library'])) {
        final m = asMap(raw);
        if (m != null && jsStr(m['id']) == widget.id) {
          changed = saveExternalIds(m, edited, now);
          return;
        }
      }
    }, label: 'Edit External IDs');
    if (!mounted) return;
    Navigator.pop(context);
    _toast(context, changed ? 'External IDs saved' : 'No ID changes');
  }

  List<_Candidate> _candidates(Map<String, dynamic> row, String provider) {
    final list = <(String, String)>[];
    if (row['externalIdCandidates'] is List) {
      for (final x in asList(row['externalIdCandidates']).map(asMap)) {
        list.add((jsStr(x?['key']), jsStr(x?['value'])));
      }
    } else {
      (asMap(row['externalIds']) ?? const {}).forEach((k, v) => list.add((k, jsStr(v))));
    }
    var type = jsStr(asMap(row['legacy'])?['mediaFormat'] ?? asMap(row['fields'])?['mediaFormat']).trim();
    if (type.isEmpty) type = list.any((x) => x.$1 == 'tmdb_tv') ? 'TV' : list.any((x) => x.$1 == 'tmdb') ? 'Movie' : '';
    final legacy = asMap(row['legacy']);
    final year = yearOf(row['year'] ?? legacy?['year'] ?? legacy?['releaseDate']);
    return [
      for (final (key, value) in list)
        if (key.isNotEmpty && value.trim().isNotEmpty && finderIdValid(key, value))
          _Candidate(key, value, jsStr(row['title']), year, type, row['exact'] != false,
              jsStr(row['recordUrl']).isNotEmpty ? jsStr(row['recordUrl']) : (_idLinks[key] != null ? '${_idLinks[key]}$value' : '')),
    ];
  }

  Future<List<Map<String, dynamic>>> _searchOne(String provider, String name, Map<String, dynamic>? item, StopToken stop) async {
    if (_publicFinder.contains(provider)) {
      final query = {
        'id': item?['id'],
        'title': name,
        'categoryId': item?['categoryId'],
        'externalIds': <String, dynamic>{},
        'universalMetadata': {'mediaType': jsStr(asMap(item?['universalMetadata'])?['mediaType']).isEmpty ? 'unspecified' : asMap(item?['universalMetadata'])!['mediaType']},
      };
      final rows = await RatingSources.instance.lookupPublic(provider, query, stop: stop);
      final n = normTitle(name);
      return [
        for (final r in rows) {...r, 'exact': [r['title'], ...asList(r['aliases'])].any((t) => normTitle(t) == n)},
      ];
    }
    return RatingSources.instance.searchGateway(provider, name, item?['year'], stop: stop);
  }

  Future<void> _find() async {
    if (_busy) {
      _stop?.stop();
      return;
    }
    final title = _query.text.trim();
    if (title.length < 2) {
      _toast(context, 'Enter a title for ID discovery.');
      return;
    }
    final item = _item;
    final stop = StopToken();
    setState(() {
      _busy = true;
      _stop = stop;
      _results.clear();
      _status.clear();
      _chosen.clear();
    });
    try {
      final ready = await RatingSources.instance.gatewayReady(force: true);
      final gateway = [for (final p in [..._coverGateway, ..._mappingGateway]) if (ready.contains(p)) p];
      var providers = _site == 'all' ? [..._publicFinder, ...gateway].where((p) => p != 'fanart').toSet().toList() : [_site];
      if (_site == 'all' && item != null) {
        final type = jsStr(widget.account.view?.category(jsStr(item['categoryId'])).raw['type']);
        const fit = {
          'video': ['jikan', 'anilist', 'kitsu', 'tvmaze', 'tmdb', 'omdb', 'malofficial', 'trakt', 'simkl', 'watchmode', 'animeschedule', 'episodate'],
          'reading': ['jikan', 'anilist', 'kitsu', 'malofficial', 'metron', 'gutendex'],
          'playing': <String>[],
          'listening': <String>[],
        };
        if (fit[type] != null) providers = providers.where(fit[type]!.contains).toList();
      }
      if (_site != 'all' && !_publicFinder.contains(_site) && !gateway.contains(_site)) {
        setState(() => _status[_site] = (
              'error',
              RatingSources.instance.statusError.isNotEmpty
                  ? 'Could not reach the MediaFlow provider service. Check your connection and sign-in.'
                  : 'Not set up: the API key for this site is missing in Supabase.'
            ));
        return;
      }
      final names = <String, String>{};
      for (final n in [title, ...(item == null ? const <String>[] : titleVariants(item))]) {
        final t = n.trim();
        if (t.isNotEmpty) names.putIfAbsent(normTitle(t), () => t);
      }
      final variants = names.values.take(3).toList();
      setState(() {
        for (final p in providers) {
          _status[p] = ('waiting', 'Waiting…');
        }
      });
      await Future.wait(providers.map((p) async {
        if (mounted) setState(() => _status[p] = ('busy', 'Searching…'));
        var found = 0;
        try {
          for (final v in variants) {
            stop.check();
            final rows = await _searchOne(p, v, item, stop);
            for (final row in rows) {
              for (final c in _candidates(row, p)) {
                final group = _results.putIfAbsent(c.key, () => {});
                final prev = group[c.value];
                if (prev != null) {
                  prev.sources.add(p);
                  prev.exact = prev.exact || c.exact;
                  if (prev.year == 0 && c.year != 0) prev.year = c.year;
                } else {
                  group[c.value] = c..sources.add(p);
                  found++;
                }
              }
            }
            if (rows.any((r) => r['exact'] != false)) break;
          }
          _status[p] = ('ok', found > 0 ? '$found result${found == 1 ? '' : 's'}' : 'No match');
        } catch (e) {
          _status[p] = stop.stopped ? ('stopped', 'Stopped') : ('error', RatingSources.reason(e));
        }
        if (mounted) setState(() {});
      }));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _stop = null;
          _preselect();
        });
      }
    }
  }

  void _preselect() {
    for (final e in _results.entries) {
      if (_current(e.key).isNotEmpty || _chosen.containsKey(e.key)) continue;
      final exact = e.value.values.where((r) => r.exact).toList();
      _chosen[e.key] = exact.length == 1 ? exact.first.value : '';
    }
  }

  String _current(String key) => _fields[key]?.text.trim() ?? '';

  void _linkChosen() {
    var count = 0, kept = 0;
    _chosen.forEach((key, value) {
      if (value.isEmpty || !finderIdValid(key, value)) return;
      final field = _fields.putIfAbsent(key, () => TextEditingController());
      if (field.text.trim().isNotEmpty && field.text.trim() != value) {
        kept++;
        return;
      }
      if (field.text == value) return;
      field.text = value;
      count++;
    });
    setState(() {});
    _toast(
        context,
        count > 0
            ? '$count ID${count == 1 ? '' : 's'} added${kept > 0 ? ' · $kept existing kept' : ''}. Save to keep them.'
            : 'No new IDs selected.');
  }

  @override
  Widget build(BuildContext context) {
    final q = _filter.text.trim().toLowerCase();
    final keys = _fields.keys.where((k) => q.isEmpty || k.contains(q) || idLabel(k).toLowerCase().contains(q)).toList();
    final savedCount = _fields.values.where((c) => c.text.trim().isNotEmpty).length;
    final groups = _results.entries.toList()
      ..sort((a, b) {
        int rank(String k) => _groupOrder.contains(k) ? _groupOrder.indexOf(k) : 99;
        return rank(a.key) - rank(b.key);
      });
    final anyNew = groups.any((g) => _current(g.key).isEmpty);
    final siteOptions = ['all', ..._publicFinder, ..._coverGateway, ..._mappingGateway].toSet().toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
        child: Row(children: [
          Expanded(
            child: Text('External Media IDs · $savedCount saved', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          ),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: _save, child: const Text('Save')),
        ]),
      ),
      Expanded(
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
          // ---- the ID finder ----
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: MF.raised, borderRadius: BorderRadius.circular(14)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('Discover verified External IDs', style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(
                'Searches with every name this title has. Pick the right record for each ID below; existing IDs are never replaced, and nothing is saved until you save.',
                style: TextStyle(color: MF.textDim, fontSize: 12),
              ),
              const SizedBox(height: 10),
              TextField(controller: _query, maxLength: 110, decoration: const InputDecoration(labelText: 'Title to identify', counterText: '')),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _site,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Sites to search'),
                    items: [for (final s in siteOptions) DropdownMenuItem(value: s, child: Text(sourceLabel(s)))],
                    onChanged: _busy ? null : (v) => setState(() => _site = v ?? 'all'),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _find,
                  icon: Icon(_busy ? Icons.stop_rounded : Icons.search_rounded),
                  label: Text(_busy ? 'Stop' : 'Find IDs'),
                ),
              ]),
              if (_status.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final e in _status.entries)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: (e.value.$1 == 'error'
                                ? MF.bad
                                : e.value.$1 == 'ok'
                                    ? MF.good
                                    : MF.textDim)
                            .withValues(alpha: .15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text('${sourceLabel(e.key)}: ${e.value.$2}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                    ),
                ]),
              ],
              if (!_busy && _status.isNotEmpty && groups.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text('No records found. Try another name (for anime, the English or romanized title) or a single site.',
                      style: TextStyle(color: MF.textDim, fontSize: 12)),
                ),
              for (final g in groups) _group(g.key, g.value),
              if (anyNew && !_busy)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: OutlinedButton(onPressed: _linkChosen, child: const Text('Add selected IDs to this title')),
                ),
            ]),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _filter,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Find an ID field…'),
          ),
          const SizedBox(height: 8),
          for (final k in keys)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: TextField(
                controller: _fields[k],
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(labelText: idLabel(k), isDense: true),
              ),
            ),
        ]),
      ),
    ]);
  }

  Widget _group(String key, Map<String, _Candidate> map) {
    final rows = map.values.toList()
      ..sort((a, b) => a.exact != b.exact ? (b.exact ? 1 : -1) : b.sources.length - a.sources.length);
    final label = _groupLabels[key] ?? idLabel(key);
    final current = _current(key);
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(border: Border.all(color: MF.border), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('$label${rows.length > 1 ? ' · ${rows.length} results' : ''}', style: const TextStyle(fontWeight: FontWeight.w800)),
        if (current.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Already set: $current${rows.where((r) => r.value == current).map((r) => ' · ${r.title}').firstOrNull ?? ''} (kept)',
              style: TextStyle(color: MF.textDim, fontSize: 12),
            ),
          )
        else ...[
          for (final r in rows)
            _choice(
              selected: (_chosen[key] ?? '') == r.value,
              onTap: () => setState(() => _chosen[key] = r.value),
              title: r.title.isEmpty ? 'Untitled' : r.title,
              subtitle: Text(
                [if (r.year != 0) '${r.year}', if (r.type.isNotEmpty) r.type, 'ID ${r.value}', r.sources.map(sourceLabel).join(', '), if (!r.exact) 'check this']
                    .join(' · '),
                style: TextStyle(color: r.exact ? MF.textDim : MF.warn, fontSize: 11),
              ),
              trailing: r.link.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Open',
                      icon: const Icon(Icons.open_in_new_rounded, size: 18),
                      onPressed: () => launchUrl(Uri.parse(r.link), mode: LaunchMode.externalApplication),
                    ),
            ),
          _choice(
            selected: (_chosen[key] ?? '').isEmpty,
            onTap: () => setState(() => _chosen[key] = ''),
            title: 'None of these',
          ),
        ],
      ]),
    );
  }
}

Widget _choice({required bool selected, required VoidCallback onTap, required String title, Widget? subtitle, Widget? trailing}) => ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      onTap: onTap,
      leading: Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded, color: selected ? MF.accent : MF.textDim),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: subtitle,
      trailing: trailing,
    );

/// Settings: "Refresh all missing ratings" with progress and Stop.
class BulkRatingsCard extends StatelessWidget {
  const BulkRatingsCard({super.key, required this.account});
  final AccountController account;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: RatingsRefresh.instance,
      builder: (context, _) {
        final b = RatingsRefresh.instance;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(
            'Uses saved IDs first, finds missing IDs (Wikidata links and every known title name), then rechecks with the new IDs. '
            'Seasons share the whole show’s IMDb and TMDB rating. Saved IDs are never replaced, and uncertain matches are skipped rather than guessed.',
            style: TextStyle(color: MF.textDim, fontSize: 12),
          ),
          const SizedBox(height: 10),
          if (b.bulkRunning) ...[
            LinearProgressIndicator(value: b.bulkTotal == 0 ? null : b.bulkDone / b.bulkTotal, minHeight: 6, borderRadius: BorderRadius.circular(4)),
            const SizedBox(height: 6),
            Text('${b.bulkDone} / ${b.bulkTotal} titles · ${b.bulkRatings} ratings · ${b.bulkIds} IDs saved',
                style: const TextStyle(fontWeight: FontWeight.w800)),
            Text(b.bulkCurrent.isEmpty ? 'Preparing…' : b.bulkCurrent, style: TextStyle(color: MF.textDim, fontSize: 12)),
            if (b.working) Text(b.note, style: TextStyle(color: MF.textMute, fontSize: 11)),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(onPressed: b.stopAll, icon: const Icon(Icons.stop_rounded), label: const Text('Stop')),
            ),
          ] else ...[
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: b.working ? null : () => unawaited(b.refreshAllMissing(account)),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Refresh all missing ratings'),
              ),
            ),
            if (b.bulkNote.isNotEmpty)
              Padding(padding: const EdgeInsets.only(top: 6), child: Text(b.bulkNote, style: TextStyle(color: MF.textDim, fontSize: 12))),
          ],
        ]);
      },
    );
  }
}

/// A small wrapper so screens can show the bulk card in a SectionCard.
Widget bulkRatingsSection(AccountController account) => SectionCard(
      title: 'External ratings',
      subtitle: 'Automatic external-rating intelligence',
      icon: Icons.star_half_rounded,
      prefKey: 'settings.ratings',
      child: BulkRatingsCard(account: account),
    );
