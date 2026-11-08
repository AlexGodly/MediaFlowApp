// The Recovery Workspace (website v445): Cover Recovery, Metadata Recovery
// and the metadata sources (Provider Management, v439 / v453 presets).

import 'dart:async';

import 'package:flutter/material.dart';

import '../data/account_controller.dart';
import '../data/rating_sources.dart';
import '../data/recovery_runner.dart';
import '../logic/extras.dart' show OtdEvent;
import '../logic/ratings_engine.dart';
import '../logic/recovery.dart';
import '../state/models.dart';
import '../util/js.dart';
import 'presence.dart';
import 'ratings_ui.dart' show sourceLabel;
import 'theme.dart';
import 'widgets.dart' show fmtNumber;

/// `mf555OnThisDayIds`: today's On This Day titles that are in the Library.
List<String> onThisDayLibraryIds(AccountView view, List<({int years, List<OtdEvent> rows})> groups) {
  final inLibrary = {for (final t in view.library) t.id};
  final ids = <String>[];
  for (final g in groups) {
    for (final row in g.rows) {
      final id = (row.libraryId ?? '').isNotEmpty ? row.libraryId! : jsStr(row.item?['id']);
      if (id.isNotEmpty && inLibrary.contains(id) && !ids.contains(id)) ids.add(id);
    }
  }
  return ids;
}

void _toast(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 3)));

/// Opens Recovery: the Recovery Workspace page (More) on [tab], or — for a
/// given set of titles (On This Day, a selection) — a screen for just those.
Future<void> openRecovery(BuildContext context, AccountController account,
    {List<String>? ids, String label = '', int tab = 0, bool combined = false}) async {
  final go = RecoveryScreen.goToPage;
  if (ids == null && go != null) {
    RecoveryScreen.request.value = (tab: tab, combined: combined, n: (RecoveryScreen.request.value?.n ?? 0) + 1);
    go();
    return;
  }
  await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => RecoveryScreen(account: account, ids: ids, label: label, initialTab: tab, combined: combined)));
}

class RecoveryScreen extends StatefulWidget {
  const RecoveryScreen({super.key, required this.account, this.ids, this.label = '', this.initialTab = 0, this.combined = false});
  final AccountController account;

  /// Opened as "New Combined Recovery": covers and details in one go.
  final bool combined;

  /// Titles to work on (e.g. today's On This Day titles); null = choose a scope.
  final List<String>? ids;
  final String label;
  final int initialTab;

  /// Set by the home shell: shows the Recovery Workspace page.
  static void Function()? goToPage;

  /// A tab (and Combined) to show on the page, from the + menu and elsewhere.
  static final ValueNotifier<({int tab, bool combined, int n})?> request = ValueNotifier(null);

  @override
  State<RecoveryScreen> createState() => _RecoveryScreenState();
}

class _RecoveryScreenState extends State<RecoveryScreen> with SingleTickerProviderStateMixin {
  String _scope = 'given'; // given | all | <categoryId>
  late final TabController _tabs = TabController(length: 3, vsync: this, initialIndex: widget.initialTab.clamp(0, 2).toInt());
  bool _combined = false;
  int _seen = 0;

  void _onRequest() {
    final r = RecoveryScreen.request.value;
    if (widget.ids != null || r == null || r.n <= _seen || !mounted) return;
    _seen = r.n;
    setState(() => _combined = r.combined);
    _tabs.animateTo(r.tab.clamp(0, 2).toInt());
  }

  @override
  void dispose() {
    RecoveryScreen.request.removeListener(_onRequest);
    _tabs.dispose();
    super.dispose();
  }

  /// Reviews where "Link verified External IDs" was turned off.
  final Set<CoverReview> _noLink = {};

  @override
  void initState() {
    super.initState();
    if (widget.ids == null) _scope = 'all';
    _combined = widget.combined;
    RecoveryScreen.request.addListener(_onRequest);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onRequest());
  }

  AccountView? get view => widget.account.view;

  List<String> _ids({required bool covers}) {
    final v = view;
    if (v == null) return const [];
    if (_scope == 'given' && widget.ids != null) return widget.ids!;
    final out = <String>[];
    for (final t in v.library) {
      if (_scope != 'all' && t.categoryId != _scope) continue;
      if (covers) {
        if (coverMissing(t.raw)) out.add(t.id);
      } else {
        final r = t.raw;
        final missing = !hasValue(r['synopsis']) || !hasValue(r['genres']) || !hasValue(r['year']) || !hasValue(r['mediaFormat']);
        if (missing) out.add(t.id);
      }
    }
    return out;
  }

  /// Every title in the scope (Combined Recovery checks covers and details).
  List<String> _idsAll() {
    final v = view;
    if (v == null) return const [];
    if (_scope == 'given' && widget.ids != null) return widget.ids!;
    return [for (final t in v.library) if (_scope == 'all' || t.categoryId == _scope) t.id];
  }

  Widget _scopePicker() {
    final v = view;
    return DropdownButtonFormField<String>(
      initialValue: _scope,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Titles'),
      items: [
        if (widget.ids != null)
          DropdownMenuItem(value: 'given', child: Text('${widget.label.isEmpty ? 'Selected titles' : widget.label} (${widget.ids!.length})')),
        const DropdownMenuItem(value: 'all', child: Text('Whole Library')),
        for (final c in v?.categories ?? const <Category>[]) DropdownMenuItem(value: c.id, child: Text(c.name)),
      ],
      onChanged: (x) => setState(() => _scope = x ?? 'all'),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PresenceScope(
      info: const PresenceInfo(situation: 'recovery'),
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.ids == null ? 'Recovery Workspace' : 'Recovery'),
          bottom: TabBar(controller: _tabs, tabs: const [Tab(text: 'Covers'), Tab(text: 'Details'), Tab(text: 'Sources')]),
        ),
        body: ListenableBuilder(
          listenable: Listenable.merge([RecoveryRunner.instance, widget.account]),
          builder: (context, _) => TabBarView(controller: _tabs, children: [
            _coverTab(context),
            _metadataTab(context),
            SourcesSettings(account: widget.account),
          ]),
        ),
      ),
    );
  }

  // ---------- covers ----------

  Widget _coverTab(BuildContext context) {
    final r = RecoveryRunner.instance;
    final job = r.cover;
    final ids = _ids(covers: true);
    return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 32), children: [
      Text('Finds covers for titles that have none. Only confident matches (same title and year) are saved automatically; '
          'the others wait below for you to pick. Existing covers are never replaced.',
          style: TextStyle(color: MF.textDim, fontSize: 13)),
      const SizedBox(height: 12),
      _scopePicker(),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: Text('${fmtNumber(ids.length)} title${ids.length == 1 ? '' : 's'} without a cover', style: const TextStyle(fontWeight: FontWeight.w700))),
        if (job?.running == true) ...[
          IconButton(
            tooltip: job!.paused ? 'Resume' : 'Pause',
            onPressed: () => job.paused ? r.resumeAll() : r.pauseAll(),
            icon: Icon(job.paused ? Icons.play_arrow_rounded : Icons.pause_rounded),
          ),
          OutlinedButton.icon(onPressed: r.stopCover, icon: const Icon(Icons.stop_rounded), label: const Text('Stop')),
        ]
        else
          FilledButton.icon(
            onPressed: ids.isEmpty ? null : () => unawaited(r.startCover(widget.account, ids, _scope == 'given' ? widget.label : 'Covers')),
            icon: const Icon(Icons.image_search_rounded),
            label: const Text('Start Cover Recovery'),
          ),
      ]),
      if (_combined || r.combinedRunning)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: MF.accentSoft, borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              const Expanded(
                child: Text('Combined Recovery: covers first, then missing details, for the titles above.',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
              ),
              if (!r.combinedRunning && job?.running != true && r.metadata?.running != true)
                FilledButton(
                  onPressed: () => unawaited(r.startCombined(widget.account, _idsAll(), _scope == 'given' ? widget.label : 'Combined')),
                  child: const Text('Start both'),
                ),
            ]),
          ),
        ),
      if (job != null) _progress(job),
      for (final review in List.of(job?.coverReviews ?? const <CoverReview>[])) _coverReview(context, review),
    ]);
  }

  Widget _progress(RecoveryJob job) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          LinearProgressIndicator(value: job.ids.isEmpty ? 0 : job.done / job.ids.length, minHeight: 6, borderRadius: BorderRadius.circular(4)),
          const SizedBox(height: 6),
          Text(
            '${job.done} / ${job.ids.length} checked · ${job.applied} saved'
            '${job.kind == 'metadata' ? ' (${job.fieldsFilled} fields)' : ''} · '
            '${job.kind == 'cover' ? job.coverReviews.length : job.metadataReviews.length} to review · ${job.noMatch} no match'
            '${job.xp > 0 ? ' · +${job.xp} XP' : ''}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          if (job.running && job.current.isNotEmpty) Text(job.current, style: TextStyle(color: MF.textDim, fontSize: 12)),
          if (!job.running) Text(job.stopped ? 'Stopped.' : 'Done.', style: TextStyle(color: MF.textDim, fontSize: 12)),
          for (final e in job.errors.take(3)) Text(e, style: TextStyle(color: MF.bad, fontSize: 11)),
        ]),
      );

  Widget _coverReview(BuildContext context, CoverReview review) => Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: MF.raised, borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(review.title, style: const TextStyle(fontWeight: FontWeight.w800))),
            TextButton(onPressed: () => RecoveryRunner.instance.skipCover(review), child: const Text('Skip')),
          ]),
          if (review.candidates.any((c) => c.ids.isNotEmpty))
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: !_noLink.contains(review),
              onChanged: (v) => setState(() => v == true ? _noLink.remove(review) : _noLink.add(review)),
              title: const Text('Also link the verified External IDs of the cover I pick', style: TextStyle(fontSize: 12)),
            ),
          SizedBox(
            height: 162,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              for (final c in review.candidates)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () async {
                      final ok = await RecoveryRunner.instance.chooseCover(widget.account, review, c, linkIds: !_noLink.contains(review));
                      if (context.mounted) _toast(context, ok ? 'Cover saved for ${review.title}' : 'The title changed meanwhile; nothing was saved.');
                    },
                    child: SizedBox(
                      width: 84,
                      child: Column(children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(c.url, width: 84, height: 112, fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(width: 84, height: 112, color: MF.surface)),
                        ),
                        Text('${c.provider}${c.year != null ? ' · ${c.year}' : ''}',
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10, color: c.confidence >= 0.94 ? MF.good : MF.textDim)),
                        Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10)),
                        if (c.ids.isNotEmpty)
                          Text(c.ids.map((x) => '${x.$1.toUpperCase()} ${x.$2}').join(' · '),
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 9, color: MF.textDim)),
                      ]),
                    ),
                  ),
                ),
            ]),
          ),
        ]),
      );

  // ---------- details ----------

  Widget _metadataTab(BuildContext context) {
    final r = RecoveryRunner.instance;
    final job = r.metadata;
    final settings = asMap(view?.state['settings']);
    final max = jsNum(metadataPreferences(settings)['maxBatch']).toInt();
    final all = _ids(covers: false);
    final ids = all.length > max ? all.sublist(0, max) : all;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 32), children: [
      Text('Fills missing details (description, genres, year, format…) and external ratings from verified sources. '
          'Existing and protected values are never replaced; conflicting or uncertain results wait for your review.',
          style: TextStyle(color: MF.textDim, fontSize: 13)),
      const SizedBox(height: 12),
      _scopePicker(),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(
          child: Text(
            '${fmtNumber(all.length)} title${all.length == 1 ? '' : 's'} missing details${all.length > max ? ' · first $max per batch' : ''}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        if (job?.running == true) ...[
          IconButton(
            tooltip: job!.paused ? 'Resume' : 'Pause',
            onPressed: () => job.paused ? r.resumeAll() : r.pauseAll(),
            icon: Icon(job.paused ? Icons.play_arrow_rounded : Icons.pause_rounded),
          ),
          OutlinedButton.icon(onPressed: r.stopMetadata, icon: const Icon(Icons.stop_rounded), label: const Text('Stop')),
        ]
        else
          FilledButton.icon(
            onPressed: ids.isEmpty ? null : () => unawaited(r.startMetadata(widget.account, ids, 'Details')),
            icon: const Icon(Icons.manage_search_rounded),
            label: const Text('Start Metadata Recovery'),
          ),
      ]),
      if (job != null) _progress(job),
      for (final preview in List.of(job?.metadataReviews ?? const <MetadataPreview>[])) _MetadataReviewCard(account: widget.account, preview: preview),
    ]);
  }
}

class _MetadataReviewCard extends StatefulWidget {
  const _MetadataReviewCard({required this.account, required this.preview});
  final AccountController account;
  final MetadataPreview preview;

  @override
  State<_MetadataReviewCard> createState() => _MetadataReviewCardState();
}

class _MetadataReviewCardState extends State<_MetadataReviewCard> {
  String _show(Object? v) {
    if (v is Map) return '${fmtNumber(jsNum(v['score']))} / ${fmtNumber(jsNum(v['scale']))}';
    if (v is List) return v.join(', ');
    final s = jsStr(v);
    return s.length > 160 ? '${s.substring(0, 160)}…' : s;
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.preview;
    final open = p.proposals.where((x) => !x.hasOriginal && !x.isProtected && !x.same).toList();
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: MF.raised, borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(p.title, style: const TextStyle(fontWeight: FontWeight.w800)),
        for (final prop in open)
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: prop.selected,
              onChanged: (v) => setState(() => prop.selected = v == true),
              title: Text(prop.label, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(
                '${_show(prop.options[prop.choice].value)}\n'
                '${prop.options[prop.choice].sources.map((s) => '${sourceLabel(s.provider)} · ${s.evidence}').join('; ')}',
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: MF.textDim),
              ),
            ),
            if (prop.options.length > 1)
              Wrap(spacing: 6, children: [
                for (var i = 0; i < prop.options.length; i++)
                  ChoiceChip(
                    label: Text(_show(prop.options[i].value), maxLines: 1, overflow: TextOverflow.ellipsis),
                    selected: prop.choice == i,
                    onSelected: (_) => setState(() => prop.choice = i),
                  ),
              ]),
          ]),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          TextButton(onPressed: () => RecoveryRunner.instance.skipReview(p), child: const Text('Skip')),
          FilledButton(
            onPressed: open.any((x) => x.selected)
                ? () async {
                    final n = await RecoveryRunner.instance.applyReview(widget.account, p);
                    if (context.mounted) _toast(context, n > 0 ? '$n field${n == 1 ? '' : 's'} saved for ${p.title}' : 'Nothing to save');
                  }
                : null,
            child: const Text('Save selected'),
          ),
        ]),
      ]),
    );
  }
}

/// Provider Management (website v439 settings + v453 presets): which sources
/// Metadata Recovery and external ratings use.
class SourcesSettings extends StatefulWidget {
  const SourcesSettings({super.key, required this.account});
  final AccountController account;

  @override
  State<SourcesSettings> createState() => _SourcesSettingsState();
}

class _SourcesSettingsState extends State<SourcesSettings> {
  Set<String> _ready = {};
  bool _checked = false;
  String _category = '';

  @override
  void initState() {
    super.initState();
    unawaited(RatingSources.instance.gatewayReady(force: true).then((r) {
      if (mounted) {
        setState(() {
          _ready = r;
          _checked = true;
        });
      }
    }));
  }

  Map<String, dynamic>? get _settings => asMap(widget.account.view?.state['settings']);

  String _status(String id) {
    if (!kGatewaySources.contains(id)) return 'Public · ready';
    if (!_checked) return 'Checking the MediaFlow provider service…';
    if (RatingSources.instance.statusError.isNotEmpty && _ready.isEmpty) return 'Could not reach the provider service';
    return _ready.contains(id) ? 'Set up on the server · ready' : 'Not set up (API key missing on the server)';
  }

  Future<void> _saveEnabled(List<String> enabled, int max) =>
      widget.account.setSetting(['v439Metadata'], metadataSettingsToSave(_settings, enabled, max));

  @override
  Widget build(BuildContext context) {
    final view = widget.account.view;
    if (view == null) return const SizedBox.shrink();
    final prefs = metadataPreferences(_settings);
    final enabled = (prefs['enabled'] as List).cast<String>().toSet();
    final max = jsNum(prefs['maxBatch']).toInt();
    final cats = view.categories;
    if (_category.isEmpty && cats.isNotEmpty) _category = cats.first.id;
    final presetRaw = asMap(asMap(_settings?['v453RecoveryPresets'])?[_category])?['metadata'];
    final custom = presetRaw is List;
    final presetIds = metadataProvidersFor(_settings, _category).toSet();
    return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 32), children: [
      const Text('Metadata and rating sources', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
      const SizedBox(height: 4),
      Text('Shared with the website. Public sources work right away; the others go through MediaFlow\'s provider service and need their API key set up on the server.',
          style: TextStyle(color: MF.textDim, fontSize: 12)),
      for (final id in kAvailableSources)
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(sourceLabel(id), style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(_status(id), style: TextStyle(fontSize: 11, color: _status(id).contains('ready') ? MF.good : MF.textDim)),
          value: enabled.contains(id),
          onChanged: (on) {
            final next = {...enabled};
            on ? next.add(id) : next.remove(id);
            unawaited(_saveEnabled(next.toList(), max));
          },
        ),
      const SizedBox(height: 8),
      DropdownButtonFormField<int>(
        initialValue: [25, 50, 100, 250].contains(max) ? max : 250,
        decoration: const InputDecoration(labelText: 'Titles per Metadata Recovery batch'),
        items: const [
          DropdownMenuItem(value: 25, child: Text('25')),
          DropdownMenuItem(value: 50, child: Text('50')),
          DropdownMenuItem(value: 100, child: Text('100')),
          DropdownMenuItem(value: 250, child: Text('250')),
        ],
        onChanged: (v) => unawaited(_saveEnabled(enabled.toList(), v ?? 250)),
      ),
      const SizedBox(height: 18),
      const Text('Category presets', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
      Text('Pick which sources a category uses. Categories without a preset use the list above.', style: TextStyle(color: MF.textDim, fontSize: 12)),
      const SizedBox(height: 8),
      if (cats.isNotEmpty)
        DropdownButtonFormField<String>(
          initialValue: _category,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Category'),
          items: [for (final c in cats) DropdownMenuItem(value: c.id, child: Text(c.name))],
          onChanged: (v) => setState(() => _category = v ?? _category),
        ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Use its own sources'),
        subtitle: Text(custom ? 'Custom preset · ${presetIds.length} selected' : 'Uses the global list'),
        value: custom,
        onChanged: (on) => widget.account.setSetting(['v453RecoveryPresets'], presetsToSave(_settings, _category, on ? enabled.toList() : null)),
      ),
      if (custom)
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final id in kAvailableSources)
            FilterChip(
              label: Text(sourceLabel(id)),
              selected: presetIds.contains(id),
              onSelected: (on) {
                final next = {...presetIds};
                on ? next.add(id) : next.remove(id);
                widget.account.setSetting(['v453RecoveryPresets'], presetsToSave(_settings, _category, next.toList()));
              },
            ),
        ]),
    ]);
  }
}
