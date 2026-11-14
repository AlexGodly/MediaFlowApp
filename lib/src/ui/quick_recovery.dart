// Quick Title Recovery (website v453 / v456): new covers and missing
// metadata for one title, previewed first. Nothing is saved until the person
// confirms; a cover that replaces an existing one asks once more.

import 'dart:async';

import 'package:flutter/material.dart';

import '../data/account_controller.dart';
import '../data/rating_sources.dart';
import '../data/recovery_runner.dart';
import '../logic/library_logic.dart' show findTitle;
import '../logic/ratings_engine.dart' show StopToken;
import '../logic/recovery.dart';
import '../util/js.dart';
import 'presence.dart';
import 'cover_choice.dart';
import 'theme.dart';

/// Opens the quick preview ([kind]: cover | metadata | both). Returns the new
/// cover URL when one was saved (the title editor shows it right away).
Future<String?> openQuickRecovery(BuildContext context, AccountController account, String id, {String kind = 'both'}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _QuickRecovery(account: account, id: id, kind: kind),
  );
}

class _QuickRecovery extends StatefulWidget {
  const _QuickRecovery({required this.account, required this.id, required this.kind});
  final AccountController account;
  final String id, kind;

  @override
  State<_QuickRecovery> createState() => _QuickRecoveryState();
}

class _QuickRecoveryState extends State<_QuickRecovery> {
  final _stop = StopToken();
  final List<CoverCandidate> _covers = [];
  int _coverIndex = -1;
  MetadataPreview? _preview;
  bool _coverLoading = false, _metaLoading = false, _applying = false;
  final List<String> _errors = [];

  bool get _wantCover => widget.kind != 'metadata';
  bool get _wantMeta => widget.kind != 'cover';

  Map<String, dynamic>? get _item => findTitle(widget.account.view?.state ?? const {}, widget.id);

  @override
  void initState() {
    super.initState();
    _coverLoading = _wantCover;
    _metaLoading = _wantMeta;
    unawaited(_scan());
  }

  @override
  void dispose() {
    _stop.stop();
    super.dispose();
  }

  Future<void> _scan() async {
    final item = _item;
    if (item == null) return;
    final snapshot = jsonClone(item) as Map<String, dynamic>;
    if (_wantCover) {
      try {
        final found = await RecoveryRunner.instance.coverCandidates(widget.account, snapshot);
        if (!mounted || _stop.stopped) return;
        setState(() => _covers.addAll(found.where((c) => c.url.startsWith('https://') && c.confidence >= 0.65).take(12)));
      } catch (e) {
        _errors.add('Covers: $e');
      }
      if (mounted) setState(() => _coverLoading = false);
    }
    if (_wantMeta && !_stop.stopped) {
      try {
        final ready = await RatingSources.instance.gatewayReady();
        final settings = asMap(widget.account.view?.state['settings']);
        final minConf = jsNum(metadataPreferences(settings)['minimumConfidence']);
        final sources = metadataSourcesFor(snapshot, settings, ready);
        if (sources.isEmpty) {
          _errors.add('No metadata sources are on for this category.');
        } else {
          final found = await discoverMetadata(snapshot, sources, (p, q) => RatingSources.instance.lookup(p, q, stop: _stop),
              minimumConfidence: minConf, stop: _stop);
          for (final f in found.failures) {
            _errors.add('${f.$1}: ${f.$2}');
          }
          _preview = metadataProposals(snapshot, found.results, minimumConfidence: minConf);
        }
      } catch (e) {
        if (!_stop.stopped) _errors.add('$e');
      }
      if (mounted) setState(() => _metaLoading = false);
    }
  }

  bool get _anySelected => _coverIndex >= 0 || (_preview?.proposals.any((p) => p.selected) ?? false);

  Future<void> _apply() async {
    final item = _item;
    if (item == null || !_anySelected || _applying) return;
    final cover = _coverIndex >= 0 ? _covers[_coverIndex] : null;
    final old = jsStr(item['coverUrl']);
    if (cover != null && old.isNotEmpty && old != cover.url) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Replace this title’s existing cover?'),
          content: const Text('Apply the selected verified cover? Your old cover will be kept if you cancel.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Replace Cover')),
          ],
        ),
      );
      if (ok != true) return;
    }
    _stop.stop(); // no need to wait for slower sources now
    setState(() => _applying = true);
    var covers = 0, fields = 0;
    final preview = _preview;
    await widget.account.edit((s, now) {
      final m = findTitle(s, widget.id);
      if (m == null) return;
      if (cover != null && applyQuickCover(m, cover, now)) covers = 1;
      if (preview != null && preview.proposals.any((p) => p.selected)) fields = applyMetadata(m, preview, now).changed;
    }, label: 'Quick title recovery');
    if (!mounted) return;
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (covers == 0 && fields == 0) {
      setState(() => _applying = false);
      messenger?.showSnackBar(const SnackBar(content: Text('Nothing eligible to save.')));
      return;
    }
    messenger?.showSnackBar(SnackBar(content: Text('Saved $covers cover and $fields verified metadata values.')));
    nav.pop(covers > 0 ? cover!.url : null);
  }

  @override
  Widget build(BuildContext context) {
    final item = _item;
    final title = cleanTitle(item?['title']);
    final cat = widget.account.view?.category(jsStr(item?['categoryId']));
    final busy = _coverLoading || _metaLoading || _applying;
    return PresenceScope(
      info: PresenceInfo(situation: 'recovery', values: {'title': title, 'action': 'Recovering'}),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        builder: (context, scroll) => Column(children: [
          Expanded(
            child: ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(18, 0, 18, 18), children: [
              Text('QUICK TITLE RECOVERY', style: TextStyle(fontSize: 11, letterSpacing: 1.2, color: MF.textDim, fontWeight: FontWeight.w800)),
              Text(widget.kind == 'both' ? 'Cover + Metadata' : widget.kind == 'cover' ? 'Cover Recovery' : 'Metadata Recovery',
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text('$title · ${cat?.name ?? 'Global defaults'} sources · Nothing saved until you confirm',
                  style: TextStyle(color: MF.textDim, fontSize: 12)),
              if (_wantCover) ..._coverSection(item),
              if (_wantMeta) ..._metaSection(),
              if (_errors.isNotEmpty)
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text('${_errors.length} source error${_errors.length == 1 ? '' : 's'}', style: const TextStyle(fontSize: 13)),
                  children: [for (final e in _errors) Align(alignment: Alignment.centerLeft, child: Text(e, style: TextStyle(fontSize: 12, color: MF.textDim)))],
                ),
            ]),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
              child: Row(children: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                const Spacer(),
                FilledButton.icon(
                  onPressed: !_anySelected || _applying ? null : _apply,
                  icon: _applying
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.check_rounded),
                  label: Text(busy && !_applying ? 'Confirm (still searching…)' : 'Confirm selected changes'),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  List<Widget> _coverSection(Map<String, dynamic>? item) {
    final old = jsStr(item?['coverUrl']);
    return [
      const SizedBox(height: 18),
      const Text('New covers', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
      const SizedBox(height: 8),
      if (_coverLoading && _covers.isEmpty)
        const Text('Searching cover sources…')
      else if (_covers.isEmpty)
        Text('No verified cover matches. Your existing cover stays untouched.', style: TextStyle(color: MF.textDim))
      else
        CoverChoiceGrid(
          itemTitle: cleanTitle(item?['title']),
          candidates: _covers,
          selectedUrl: _coverIndex >= 0 ? _covers[_coverIndex].url : null,
          onPick: (c) => setState(() {
            final i = _covers.indexOf(c);
            _coverIndex = i == _coverIndex ? -1 : i;
          }),
        ),
      if (!_coverLoading && item != null)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.search_rounded, size: 18),
            label: const Text('Search manually'),
            onPressed: () async {
              final c = await searchCoverManually(context, widget.account, item);
              if (c == null || !mounted) return;
              setState(() {
                _covers.removeWhere((x) => x.url == c.url);
                _covers.insert(0, c);
                _coverIndex = 0;
              });
            },
          ),
        ),
      if (old.isNotEmpty && _covers.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text('This title already has a cover; replacing it asks you first.', style: TextStyle(fontSize: 12, color: MF.textDim)),
        ),
    ];
  }

  List<Widget> _metaSection() {
    final preview = _preview;
    return [
      const SizedBox(height: 18),
      const Text('New metadata', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
      const SizedBox(height: 6),
      if (_metaLoading)
        const Text('Searching verified metadata…')
      else if (preview == null || preview.proposals.isEmpty)
        Text('No verified suggestions from the ready sources.', style: TextStyle(color: MF.textDim))
      else ...[
        Text('${preview.providers.length} source${preview.providers.length == 1 ? '' : 's'} · ${preview.proposals.length} proposed fields',
            style: TextStyle(fontSize: 12, color: MF.textDim)),
        // 10.0.0: Select all / Deselect all (like the Library-wide review).
        Builder(builder: (_) {
          final open = preview.proposals.where((p) => !(p.hasOriginal || p.isProtected || p.same)).toList();
          if (open.length < 2) return const SizedBox.shrink();
          return Row(children: [
            TextButton.icon(
              onPressed: () => setState(() {
                for (final p in open) {
                  p.selected = true;
                }
              }),
              icon: const Icon(Icons.done_all_rounded, size: 18),
              label: const Text('Select all'),
            ),
            TextButton.icon(
              onPressed: () => setState(() {
                for (final p in open) {
                  p.selected = false;
                }
              }),
              icon: const Icon(Icons.remove_done_rounded, size: 18),
              label: const Text('Deselect all'),
            ),
            const Spacer(),
            Text('${open.where((p) => p.selected).length} of ${open.length} selected', style: TextStyle(color: MF.textDim, fontSize: 11)),
          ]);
        }),
        for (final p in preview.proposals) _proposal(p),
      ],
    ];
  }

  Widget _proposal(FieldProposal p) {
    final locked = p.hasOriginal || p.isProtected || p.same;
    final option = p.choice < p.options.length ? p.options[p.choice] : p.options.first;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(4, 4, 10, 8),
      decoration: BoxDecoration(color: MF.raised, borderRadius: BorderRadius.circular(12)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Checkbox(value: p.selected, onChanged: locked ? null : (v) => setState(() => p.selected = v == true)),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SizedBox(height: 10),
            Text(p.label, style: const TextStyle(fontWeight: FontWeight.w800)),
            Text('Current: ${describeFieldValue(p.token, p.original)} · ${p.status}', style: TextStyle(fontSize: 11, color: MF.textDim)),
            const SizedBox(height: 2),
            Text(describeFieldValue(p.token, option.value), maxLines: 4, overflow: TextOverflow.ellipsis),
            Text('Source: ${option.sources.map((s) => '${s.provider} · ${s.evidence}').join(' / ')}',
                style: TextStyle(fontSize: 11, color: MF.textDim)),
            if (p.options.length > 1)
              DropdownButton<int>(
                isDense: true,
                value: p.choice,
                items: [
                  for (var j = 0; j < p.options.length; j++)
                    DropdownMenuItem(value: j, child: Text(p.options[j].sources.map((s) => s.provider).join(' + '))),
                ],
                onChanged: (v) => setState(() {
                  p.choice = v ?? 0;
                  p.selected = !locked;
                }),
              ),
          ]),
        ),
      ]),
    );
  }
}
