// Settings → API Providers & Testing (website v434 gateway panel + v438
// registry). Public sources can be switched on or off for Cover Recovery
// (settings.v424Covers.enabled, shared with the website) and tested with the
// website's read-only requests. Gateway providers keep their keys on the
// server: "Check connections" asks the gateway which are configured, and a
// test searches one title (passing tests are saved to v434TestedProviders).

import 'package:flutter/material.dart';

import '../data/account_controller.dart';
import '../data/metadata_search.dart';
import '../state/models.dart';
import '../util/js.dart';
import 'theme.dart';

class ApiProvidersSection extends StatefulWidget {
  const ApiProvidersSection({super.key, required this.account, required this.view});
  final AccountController account;
  final AccountView view;

  @override
  State<ApiProvidersSection> createState() => _ApiProvidersSectionState();
}

class _ApiProvidersSectionState extends State<ApiProvidersSection> {
  final _title = TextEditingController(text: 'Breaking Bad');
  final Map<String, String> _results = {};
  final Set<String> _busy = {};
  Map<String, ({bool configured, bool testable})>? _gateway;
  bool _checking = false;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Map<String, dynamic>? get _settings => asMap(widget.view.state['settings']);

  Future<void> _toggle(String id, bool on) {
    final list = [...enabledCoverSources(_settings)]..remove('itunes');
    if (on && !list.contains(id)) list.add(id);
    if (!on) list.remove(id);
    final order = [for (final p in kPublicProviders) if (list.contains(p.id)) p.id];
    return widget.account.setSetting(['v424Covers', 'enabled'], order);
  }

  Future<void> _testPublic(String id) async {
    setState(() {
      _busy.add(id);
      _results[id] = 'Testing…';
    });
    final error = await testPublicProvider(id);
    if (!mounted) return;
    setState(() {
      _busy.remove(id);
      _results[id] = error == null ? 'Passed · ${TimeOfDay.now().format(context)}' : 'Failed · $error';
    });
  }

  Future<void> _check() async {
    setState(() => _checking = true);
    final st = await gatewayStatus(refresh: true);
    if (mounted) {
      setState(() {
        _checking = false;
        _gateway = st;
      });
    }
  }

  Future<void> _testGateway(String id) async {
    final title = _title.text.trim();
    if (title.length < 2) {
      setState(() => _results['gw:$id'] = 'Enter a real title to test. Example: Breaking Bad, Naruto, Frankenstein.');
      return;
    }
    setState(() {
      _busy.add('gw:$id');
      _results['gw:$id'] = 'Checking…';
    });
    String msg;
    try {
      final rows = await searchGateway(id, title, rethrowErrors: true, checkReady: false);
      if (id == 'omdb' && rows.isEmpty) throw Exception('OMDb responded, but no matching title was found. Try The Matrix or Breaking Bad.');
      msg = 'Responded successfully · ${rows.length} matching records';
      final tested = {for (final x in asList(_settings?['v434TestedProviders'])) jsStr(x)}..add(id);
      await widget.account.setSetting(['v434TestedProviders'], tested.toList());
    } catch (e) {
      msg = 'Failed · ${'$e'.replaceFirst('Exception: ', '')}';
    }
    if (!mounted) return;
    setState(() {
      _busy.remove('gw:$id');
      _results['gw:$id'] = msg;
    });
  }

  @override
  Widget build(BuildContext context) {
    final enabled = enabledCoverSources(_settings);
    final tested = {for (final x in asList(_settings?['v434TestedProviders'])) jsStr(x)};
    final dim = TextStyle(color: MF.textDim, fontSize: 12);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Public sources the app calls directly. Turned-on sources are used by Cover Recovery and Metadata Recovery '
          '(the same choice as on the website).', style: dim),
      const SizedBox(height: 6),
      for (final p in kPublicProviders)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: p.id == 'itunes'
              ? const Icon(Icons.public_rounded)
              : Switch(value: enabled.contains(p.id), onChanged: (v) => _toggle(p.id, v)),
          title: Text(p.name),
          subtitle: Text([p.media, if (_results[p.id] != null) _results[p.id]!].join(' · ')),
          trailing: TextButton(onPressed: _busy.contains(p.id) ? null : () => _testPublic(p.id), child: const Text('Test API')),
        ),
      const Divider(height: 24),
      const Text('Verified API connections', style: TextStyle(fontWeight: FontWeight.w800)),
      Text('Keys stay in MediaFlow\'s server. Configured providers work without testing first; Test API is an optional check.', style: dim),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
          child: TextField(
            controller: _title,
            maxLength: 110,
            decoration: const InputDecoration(labelText: 'Test title', hintText: 'Breaking Bad / Naruto / Frankenstein', counterText: ''),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton.tonal(onPressed: _checking ? null : _check, child: Text(_checking ? 'Checking…' : 'Check connections')),
      ]),
      const SizedBox(height: 6),
      if (_gateway == null)
        Text('Tap Check connections to see which providers are set up.', style: dim)
      else if (_gateway!.isEmpty)
        Text('The provider gateway could not be reached. Check your connection and that you are signed in.', style: dim)
      else
        for (final e in _gateway!.entries)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(kGatewayCoverProviders[e.key] ?? e.key),
            subtitle: Text([
              !e.value.testable
                  ? 'API access or licensing review'
                  : !e.value.configured
                      ? 'Credential missing'
                      : tested.contains(e.key)
                          ? 'Ready · last diagnostic passed'
                          : 'Ready · optional test',
              if (!kGatewayCoverProviders.containsKey(e.key)) 'ID-only source',
              if (_results['gw:${e.key}'] != null) _results['gw:${e.key}']!,
            ].join(' · ')),
            trailing: TextButton(
              onPressed: !e.value.testable || !e.value.configured || _busy.contains('gw:${e.key}') ? null : () => _testGateway(e.key),
              child: const Text('Test API'),
            ),
          ),
    ]);
  }
}
