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
        SizedBox(
          height: 196,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _covers.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, i) {
              final c = _covers[i];
              final selected = i == _coverIndex;
              final link = item == null ? null : quickCoverLink(item, c);
              return InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => setState(() => _coverIndex = selected ? -1 : i),
                child: Container(
                  width: 104,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: selected ? MF.accent : Colors.transparent, width: 2),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(c.url, width: 96, height: 128, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(width: 96, height: 128, color: MF.surface)),
                    ),
                    Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                    Text('${c.provider} · ${(c.confidence * 100).round()}% match',
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10, color: MF.textDim)),
                    if (link != null && link.key.isNotEmpty)
                      Text(link.canLink ? 'Links ${link.key.toUpperCase()} ${link.id}' : 'ID already saved',
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 9, color: MF.textDim)),
                  ]),
                ),
              );
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
