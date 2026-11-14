// Advanced RPC mode → Modify: MediaFlow's own (automatic) Discord status as
// fields, like a Custom Status, for one situation or all of them. Fields keep
// placeholders ({title}, {progress}, {cover}…), so the status stays live; an
// empty field keeps what MediaFlow shows. Saved in the account's Discord
// look (`mediaflowAppDiscord.modified`), on every device.

import 'package:flutter/material.dart';

import '../data/account_controller.dart';
import '../logic/presence_templates.dart';
import '../platform/discord_presence.dart';
import '../util/js.dart';
import 'discord_card.dart';
import 'presence.dart';
import 'theme.dart';

Future<void> openRpcModify(BuildContext context, AccountController account) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => RpcModifyScreen(account: account)));

class RpcModifyScreen extends StatefulWidget {
  const RpcModifyScreen({super.key, required this.account});
  final AccountController account;

  @override
  State<RpcModifyScreen> createState() => _RpcModifyScreenState();
}

class _RpcModifyScreenState extends State<RpcModifyScreen> {
  late String _situation;
  late Map<String, dynamic> _draft;
  int _rev = 0;

  PresenceConfig get _config => DiscordPresence.instance.config;

  @override
  void initState() {
    super.initState();
    final now = DiscordPresence.instance.currentSituation;
    _situation = kPresenceSituations.any((s) => s.$1 == now) ? now : 'logging';
    _load();
  }

  /// This situation's saved fields, or MediaFlow's status converted to fields.
  void _load() {
    final own = asMap(asMap(_config.raw['modified'])?[_situation]);
    final all = asMap(asMap(_config.raw['modified'])?['all']);
    _draft = {..._config.modifyFields(_situation == 'all' ? 'logging' : _situation), ...?all, ...?own};
    _rev++;
  }

  bool get _hasOwn => asMap(asMap(_config.raw['modified'])?[_situation]) != null;

  Future<void> _write(Map<String, dynamic>? fields) async {
    final modified = {...?asMap(_config.raw['modified'])};
    if (fields == null) {
      modified.remove(_situation);
    } else {
      modified[_situation] = fields;
    }
    final next = _config.withChanges({'modified': modified, 'advanced': true});
    DiscordPresence.instance.setConfig(PresenceConfig(next));
    await widget.account.setSetting([PresenceConfig.key], next);
  }

  void _set(String key, Object? value) => setState(() => _draft[key] = value);

  DiscordActivity? _preview() {
    final modified = {...?asMap(_config.raw['modified']), _situation: _draft};
    final c = PresenceConfig(_config.withChanges({'modified': modified, 'advanced': true}));
    return DiscordPresence.instance.effective(using: c, situation: _situation == 'all' ? null : _situation);
  }

  Widget _field(String key, String label, {String? help, int maxLength = 128}) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: TextFormField(
          key: ValueKey('$key-$_situation-$_rev'),
          initialValue: jsStr(_draft[key]),
          maxLength: maxLength,
          decoration: InputDecoration(labelText: label, helperText: help, helperMaxLines: 3, counterText: ''),
          onChanged: (v) => _set(key, v),
        ),
      );

  Widget _choice(String key, String label, List<(String, String)> options) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: DropdownButtonFormField<String>(
          key: ValueKey('$key-$_situation-$_rev'),
          initialValue: options.any((o) => o.$1 == _draft[key]) ? jsStr(_draft[key]) : options.first.$1,
          isExpanded: true,
          decoration: InputDecoration(labelText: label),
          items: [for (final o in options) DropdownMenuItem(value: o.$1, child: Text(o.$2, overflow: TextOverflow.ellipsis))],
          onChanged: (v) => _set(key, v),
        ),
      );

  Widget _imageRow(String key) => Wrap(spacing: 4, children: [
        TextButton(onPressed: () => setState(() { _draft[key] = '{cover}'; _rev++; }), child: const Text('Title cover')),
        TextButton(onPressed: () => setState(() { _draft[key] = '{logo}'; _rev++; }), child: const Text('MediaFlow logo')),
        TextButton(onPressed: () => setState(() { _draft[key] = ''; _rev++; }), child: const Text('Automatic')),
      ]);

  @override
  Widget build(BuildContext context) {
    final d = DiscordPresence.instance;
    final modifiedSituations = _config.modifiedSituations.toSet();
    return PresenceScope(
      info: const PresenceInfo(situation: 'settings'),
      child: Scaffold(
        appBar: AppBar(title: const Text('Modify Discord status')),
        body: ListenableBuilder(
          listenable: d,
          builder: (context, _) {
            final buttons = asList(_draft['buttons']).map(asMap).whereType<Map<String, dynamic>>().toList();
            return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 40), children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Advanced RPC mode'),
                subtitle: const Text('Use these modifications. Off: MediaFlow\'s status as it is (your modifications are kept).'),
                value: _config.advanced,
                onChanged: (v) async {
                  final next = _config.withChanges({'advanced': v});
                  d.setConfig(PresenceConfig(next));
                  await widget.account.setSetting([PresenceConfig.key], next);
                  if (mounted) setState(() {});
                },
              ),
              DropdownButtonFormField<String>(
                key: ValueKey('situation-$_rev'),
                initialValue: _situation,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Scenario', helperText: 'Each scenario can have its own status; "Every scenario" is used where one has none.'),
                items: [
                  DropdownMenuItem(value: 'all', child: Text('Every scenario${modifiedSituations.contains('all') ? ' · modified' : ''}')),
                  for (final s in kPresenceSituations)
                    DropdownMenuItem(value: s.$1, child: Text('${s.$2}${modifiedSituations.contains(s.$1) ? ' · modified' : ''}', overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setState(() {
                  _situation = v ?? _situation;
                  _load();
                }),
              ),
              const SizedBox(height: 12),
              Text('Preview', style: TextStyle(fontWeight: FontWeight.w800, color: MF.accent)),
              const SizedBox(height: 6),
              DiscordActivityCard(activity: _preview(), empty: 'Nothing shown in this scenario'),
              const SizedBox(height: 4),
              Text('Placeholders like {title}, {progress}, {total}, {unit}, {category}, {level} keep it live. Empty fields keep what MediaFlow shows.',
                  style: TextStyle(color: MF.textMute, fontSize: 11)),
              const Divider(height: 28),
              _field('name', 'Activity name', help: 'The header on your profile (empty: MediaFlow\'s).'),
              _field('details', 'Details (first line)'),
              _field('state', 'State (second line)'),
              _choice('display', 'Status line shows', const [('name', 'The activity name'), ('details', 'Details'), ('state', 'State')]),
              _choice('type', 'Activity type', const [
                ('auto', 'MediaFlow decides'),
                ('playing', 'Playing'),
                ('watching', 'Watching'),
                ('listening', 'Listening to'),
                ('competing', 'Competing in'),
              ]),
              const Divider(height: 28),
              _field('largeImage', 'Large image', maxLength: 512, help: '{cover}, {logo} or an https:// link.'),
              _imageRow('largeImage'),
              _field('largeText', 'Large image text'),
              if (d.supportsLinks) _field('largeUrl', 'Large image link (https://)', maxLength: 512),
              _field('smallImage', 'Small image', maxLength: 512, help: '{cover}, {logo} or an https:// link.'),
              _imageRow('smallImage'),
              _field('smallText', 'Small image text'),
              if (d.supportsLinks) _field('smallUrl', 'Small image link (https://)', maxLength: 512),
              if (d.supportsLinks) ...[
                _field('detailsUrl', 'Details link (https://)', maxLength: 512),
                _field('stateUrl', 'State link (https://)', maxLength: 512),
              ],
              const Divider(height: 28),
              Row(children: [
                const Expanded(child: Text('Buttons', style: TextStyle(fontWeight: FontWeight.w800))),
                if (buttons.length < 2)
                  TextButton.icon(
                    onPressed: () => setState(() {
                      _draft['buttons'] = [...buttons, {'label': '', 'url': ''}];
                      _rev++;
                    }),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Add'),
                  ),
              ]),
              for (var i = 0; i < buttons.length; i++)
                Row(children: [
                  Expanded(
                    child: TextFormField(
                      key: ValueKey('bl$i-$_situation-$_rev'),
                      initialValue: jsStr(buttons[i]['label']),
                      maxLength: 32,
                      decoration: const InputDecoration(labelText: 'Label', counterText: ''),
                      onChanged: (v) => setState(() => buttons[i]['label'] = v),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      key: ValueKey('bu$i-$_situation-$_rev'),
                      initialValue: jsStr(buttons[i]['url']),
                      decoration: const InputDecoration(labelText: 'https:// link'),
                      onChanged: (v) => setState(() => buttons[i]['url'] = v.trim()),
                    ),
                  ),
                  IconButton(
                    onPressed: () => setState(() {
                      _draft['buttons'] = [for (var j = 0; j < buttons.length; j++) if (j != i) buttons[j]];
                      _rev++;
                    }),
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
                ]),
              const SizedBox(height: 20),
              Wrap(spacing: 8, runSpacing: 8, children: [
                FilledButton.icon(
                  onPressed: () async {
                    _draft['buttons'] = buttons;
                    await _write({..._draft});
                    if (!context.mounted) return;
                    ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('Saved · Advanced RPC mode is on')));
                    setState(() {});
                  },
                  icon: const Icon(Icons.save_rounded),
                  label: const Text('Save this scenario'),
                ),
                OutlinedButton(
                  onPressed: () => setState(_load),
                  child: const Text('Undo changes'),
                ),
                if (_hasOwn)
                  TextButton(
                    onPressed: () async {
                      await _write(null);
                      if (mounted) setState(_load);
                    },
                    child: const Text('Back to MediaFlow\'s status'),
                  ),
              ]),
            ]);
          },
        ),
      ),
    );
  }
}
