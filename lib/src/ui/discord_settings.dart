// Settings → This app → Discord: Rich Presence on/off and linking (this
// device), and the fully customizable look (saved in the account, so every
// device shows the same status): preset, the two lines of every situation,
// what Discord's status line says, pictures, hover texts, timer, which log
// draft title is shown, verbs per category, privacy, idle and hidden categories.

import 'package:flutter/material.dart';

import '../data/account_controller.dart';
import '../logic/custom_status.dart';
import '../logic/presence_templates.dart';
import '../platform/discord_ffi.dart';
import '../platform/discord_presence.dart';
import '../util/js.dart';
import 'collections_screen.dart' show pickLibraryTitles;
import 'custom_status_screen.dart' show openCustomStatus;
import 'discord_card.dart';
import 'theme.dart';
import 'widgets.dart';

class DiscordSettings extends StatelessWidget {
  const DiscordSettings({super.key, required this.account});
  final AccountController? account;

  Future<void> _save(Map<String, dynamic> changes) async {
    final a = account;
    if (a == null || a.view == null) return;
    final next = DiscordPresence.instance.config.withChanges(changes);
    DiscordPresence.instance.setConfig(PresenceConfig(next));
    await a.setSetting([PresenceConfig.key], next);
  }

  Widget _choice<T>(String label, T value, List<(T, String)> options, ValueChanged<T> onChanged, {String? help}) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: DropdownButtonFormField<T>(
          initialValue: options.any((o) => o.$1 == value) ? value : options.first.$1,
          isExpanded: true,
          decoration: InputDecoration(labelText: label, helperText: help, helperMaxLines: 3),
          items: [for (final o in options) DropdownMenuItem(value: o.$1, child: Text(o.$2, overflow: TextOverflow.ellipsis))],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      );

  @override
  Widget build(BuildContext context) {
    final d = DiscordPresence.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([d, if (account != null) account!]),
      builder: (context, _) {
        if (!DiscordPresence.supported) {
          return Text('Discord Rich Presence is available on Windows, Android and iOS.', style: TextStyle(color: MF.textDim));
        }
        if (!d.available) {
          return Text(
            'This build of MediaFlow does not include Discord Rich Presence.${DiscordFfi.loadError.isEmpty ? '' : '\n${DiscordFfi.loadError}'}',
            style: TextStyle(color: MF.textDim, fontSize: 12),
          );
        }
        final c = d.config;
        final cats = account?.view?.categories ?? const [];
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Show what I\'m doing in MediaFlow on Discord'),
            subtitle: Text(DiscordPresence.mobile
                ? 'On this device. Link your Discord account once (Discord\'s own sign-in).'
                : 'On this PC: through the Discord app when it is open, or link your Discord account to show it without the app.'),
            value: d.enabled,
            onChanged: (v) => d.setEnabled(v),
          ),
          if (d.enabled) ...[
            Row(children: [
              Icon(Icons.circle, size: 10, color: d.connected ? MF.good : MF.textMute),
              const SizedBox(width: 8),
              Expanded(child: Text(d.statusText, style: const TextStyle(fontWeight: FontWeight.w700))),
              if (!d.linked)
                FilledButton.icon(
                  onPressed: d.linking ? null : d.link,
                  icon: const Icon(Icons.link_rounded),
                  label: Text(d.linking ? 'Waiting…' : (DiscordPresence.mobile ? 'Link Discord' : 'Link Discord account')),
                )
              else if (d.linked)
                TextButton(onPressed: d.unlink, child: const Text('Unlink')),
            ]),
            if (d.lastError.isNotEmpty)
              Padding(padding: const EdgeInsets.only(top: 4), child: Text(d.lastError, style: TextStyle(color: MF.bad, fontSize: 12))),
          ],
          const SizedBox(height: 14),
          _Previews(),
          _PinnedTile(account: account),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: account == null ? null : () => openCustomStatus(context, account!),
              icon: const Icon(Icons.tune_rounded),
              label: Text(currentCustomStatus(asMap(account?.view?.state['settings']), DateTime.now()) == null
                  ? 'Custom Status…'
                  : 'Custom Status… (active)'),
            ),
          ),
          const SizedBox(height: 6),
          Text('The look below is saved in your account and used on every device.', style: TextStyle(color: MF.textMute, fontSize: 11)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, children: [
            for (final p in const [('detailed', 'Detailed'), ('simple', 'Simple'), ('custom', 'Custom')])
              ChoiceChip(
                label: Text(p.$2),
                selected: c.preset == p.$1,
                onSelected: (_) => _save({'preset': p.$1}),
              ),
          ]),
          _choice<String>('Discord\'s status line says', c.statusLine, const [
            ('name', 'Watching MediaFlow'),
            ('details', 'Watching + line 1 (e.g. Watching Frieren)'),
            ('state', 'Watching + line 2'),
          ], (v) => _save({'statusLine': v}), help: 'The short status under your name in member lists and DMs.'),
          _choice<String>('Profile card header says', c.activityName, const [
            ('mediaflow', 'Watching MediaFlow'),
            ('status', 'The same as the status line (e.g. Watching Frieren)'),
            ('custom', 'My own text…'),
          ], (v) => _save({'activityName': v}), help: 'The activity name at the top of your profile card.'),
          if (c.activityName == 'custom')
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Header text'),
              subtitle: Text(c.nameTemplate.isEmpty ? '(empty: MediaFlow)' : c.nameTemplate),
              trailing: const Icon(Icons.edit_rounded, size: 18),
              onTap: () async {
                final ctl = TextEditingController(text: c.nameTemplate);
                final v = await showDialog<String>(
                  context: context,
                  builder: (dc) => AlertDialog(
                    title: const Text('Profile card header'),
                    content: TextField(controller: ctl, decoration: const InputDecoration(helperText: 'Placeholders work here too, e.g. {title} or {category}')),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(dc), child: const Text('Cancel')),
                      FilledButton(onPressed: () => Navigator.pop(dc, ctl.text.trim()), child: const Text('Save')),
                    ],
                  ),
                );
                if (v != null) await _save({'nameTemplate': v});
              },
            ),
          _choice<String>('What to show', c.privacy, const [
            ('full', 'Everything (titles, covers, progress)'),
            ('activity', 'What I\'m doing, without titles or covers'),
            ('minimal', 'Just "Using MediaFlow"'),
          ], (v) => _save({'privacy': v})),
          _choice<String>('Big picture', c.picture, const [('cover', 'Title cover (MediaFlow logo when there is none)'), ('logo', 'MediaFlow logo')],
              (v) => _save({'picture': v})),
          _choice<String>('Small picture (on a cover)', c.smallPicture, const [('logo', 'MediaFlow logo'), ('none', 'None')],
              (v) => _save({'smallPicture': v})),
          _choice<String>('Timer', c.timer, const [
            ('title', 'Since I opened this title'),
            ('screen', 'Since I opened this screen'),
            ('app', 'Since I opened MediaFlow'),
            ('off', 'No timer'),
          ], (v) => _save({'timer': v})),
          _choice<String>('While logging several titles, show', c.draftEntry, const [
            ('last', 'The title I edited last'),
            ('first', 'The first title'),
            ('all', 'The first title + how many more'),
          ], (v) => _save({'draftEntry': v}), help: 'Title and progress come from your log draft, so they change as you type.'),
          _choice<String>('While logging, progress shows', c.progressMode, const [
            ('after', 'After this log (what I\'ve filled in)'),
            ('before', 'Before this log (where the title is now)'),
          ], (v) => _save({'progressMode': v}), help: 'For {progress}. {before} and {after} are always available too.'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Say what I\'m doing ("Logging Frieren")'),
            subtitle: const Text('Off: just the title ("Frieren")'),
            value: c.showAction,
            onChanged: (v) => _save({'showAction': v}),
          ),
          _choice<String>('When idle', c.idle, const [('show', 'Show the Idle status'), ('clear', 'Clear my status'), ('never', 'Never show idle (keep my status)')], (v) => _save({'idle': v})),
          _choice<int>('Idle after', c.idleMinutes, const [(2, '2 minutes'), (5, '5 minutes'), (10, '10 minutes'), (15, '15 minutes'), (30, '30 minutes')],
              (v) => _save({'idleMinutes': v})),
          const SizedBox(height: 14),
          const Text('Lines for each situation', style: TextStyle(fontWeight: FontWeight.w800)),
          Text('Tap one to edit. Placeholders like {title} or {progress} are filled in; pieces with nothing to show disappear.',
              style: TextStyle(color: MF.textDim, fontSize: 12)),
          for (final s in kPresenceSituations)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(s.$2, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('${c.template(s.$1).$1}${c.template(s.$1).$2.isEmpty ? '' : '\n${c.template(s.$1).$2}'}',
                  style: TextStyle(color: MF.textDim, fontSize: 12)),
              trailing: const Icon(Icons.edit_rounded, size: 18),
              onTap: () => _editTemplate(context, s.$1, s.$2),
            ),
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Hover texts on the pictures', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('Big: ${c.largeText}\nSmall: ${c.smallText}', style: TextStyle(color: MF.textDim, fontSize: 12)),
            trailing: const Icon(Icons.edit_rounded, size: 18),
            onTap: () => _editHover(context),
          ),
          if (cats.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Text('Verb for each category', style: TextStyle(fontWeight: FontWeight.w800)),
            for (final cat in cats)
              _choice<String>(cat.name, c.types[cat.id] ?? 'auto', const [
                ('auto', 'Automatic'),
                ('watching', 'Watching'),
                ('listening', 'Listening to'),
                ('playing', 'Playing'),
              ], (v) {
                final types = {...c.types};
                v == 'auto' ? types.remove(cat.id) : types[cat.id] = v;
                _save({'types': types});
              }),
            const SizedBox(height: 10),
            Text('Never show titles from these categories', style: TextStyle(color: MF.textDim, fontSize: 12)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final cat in cats)
                FilterChip(
                  label: Text(cat.name),
                  selected: c.hiddenCategories.contains(cat.id),
                  onSelected: (on) {
                    final next = {...c.hiddenCategories};
                    on ? next.add(cat.id) : next.remove(cat.id);
                    _save({'hiddenCategories': next.toList()});
                  },
                ),
            ]),
          ],
          const SizedBox(height: 10),
          Text(
            'Uses Discord\'s official Social SDK. MediaFlow never sees your Discord password or account token; you can remove '
            'it any time under Discord → Settings → Authorized Apps.',
            style: TextStyle(color: MF.textMute, fontSize: 11),
          ),
        ]);
      },
    );
  }

  Future<void> _editTemplate(BuildContext context, String situation, String label) async {
    final t = DiscordPresence.instance.config.template(situation);
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (_) => _TemplateDialog(title: label, first: t.$1, second: t.$2),
    );
    if (result == null) return;
    final next = DiscordPresence.instance.config.withTemplate(situation, result.$1, result.$2);
    DiscordPresence.instance.setConfig(PresenceConfig(next));
    await account?.setSetting([PresenceConfig.key], next);
  }

  Future<void> _editHover(BuildContext context) async {
    final c = DiscordPresence.instance.config;
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (_) => _TemplateDialog(title: 'Hover texts', first: c.largeText, second: c.smallText, labels: const ('Big picture', 'Small picture')),
    );
    if (result != null) await _save({'largeText': result.$1, 'smallText': result.$2});
  }
}

class _TemplateDialog extends StatefulWidget {
  const _TemplateDialog({required this.title, required this.first, required this.second, this.labels = const ('Line 1', 'Line 2')});
  final String title, first, second;
  final (String, String) labels;

  @override
  State<_TemplateDialog> createState() => _TemplateDialogState();
}

class _TemplateDialogState extends State<_TemplateDialog> {
  late final _a = TextEditingController(text: widget.first);
  late final _b = TextEditingController(text: widget.second);
  TextEditingController? _focused;

  static const _sample = {
    'title': 'Frieren', 'verb': 'Watching', 'action': 'Logging', 'progress': '12', 'total': '28', 'unit': 'Episode', 'units': 'episodes',
    'percent': '43%', 'season': 'Season 1', 'category': 'Anime', 'more': '+2 more', 'count': '3', 'collection': 'Comfort Anime',
    'level': '24', 'streak': '7', 'xp': '12,345', 'library': '1,240', 'rerolls': '3',
  };

  @override
  void dispose() {
    _a.dispose();
    _b.dispose();
    super.dispose();
  }

  void _insert(String token) {
    final c = _focused ?? _a;
    final sel = c.selection;
    final at = sel.isValid ? sel.start : c.text.length;
    final end = sel.isValid ? sel.end : c.text.length;
    c.text = c.text.replaceRange(at, end, token);
    c.selection = TextSelection.collapsed(offset: at + token.length);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Focus(
              onFocusChange: (f) => f ? _focused = _a : null,
              child: TextField(controller: _a, maxLength: 128, onChanged: (_) => setState(() {}), decoration: InputDecoration(labelText: widget.labels.$1)),
            ),
            Focus(
              onFocusChange: (f) => f ? _focused = _b : null,
              child: TextField(controller: _b, maxLength: 128, onChanged: (_) => setState(() {}), decoration: InputDecoration(labelText: widget.labels.$2)),
            ),
            Text('Example', style: TextStyle(color: MF.textDim, fontSize: 11, fontWeight: FontWeight.w800)),
            Text(renderPresence(_a.text, _sample), style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(renderPresence(_b.text, _sample), style: TextStyle(color: MF.textDim)),
            const SizedBox(height: 10),
            Text('Tap to insert', style: TextStyle(color: MF.textDim, fontSize: 11, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final p in kPresencePlaceholders)
                Tooltip(
                  message: p.$2,
                  child: ActionChip(label: Text(p.$1, style: const TextStyle(fontSize: 12)), onPressed: () => _insert(p.$1)),
                ),
            ]),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, (_a.text.trim(), _b.text.trim())), child: const Text('Save')),
      ],
    );
  }
}

/// What this device would show, next to what Discord last accepted.
class _Previews extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final d = DiscordPresence.instance;
    final wide = MediaQuery.sizeOf(context).width >= 700;
    final mine = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('PREVIEW', style: TextStyle(fontSize: 10, letterSpacing: 1, fontWeight: FontWeight.w900, color: MF.textMute)),
      const SizedBox(height: 4),
      DiscordActivityCard(activity: d.effective(), empty: 'Nothing shown (idle)'),
    ]);
    final has = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('DISCORD HAS', style: TextStyle(fontSize: 10, letterSpacing: 1, fontWeight: FontWeight.w900, color: MF.textMute)),
      const SizedBox(height: 4),
      DiscordActivityCard(activity: d.accepted, empty: d.connected ? 'No status accepted yet' : 'Not connected'),
    ]);
    return wide
        ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: mine), const SizedBox(width: 12), Expanded(child: has)])
        : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [mine, const SizedBox(height: 10), has]);
  }
}

/// "Show on Discord": the pinned title and how long it stays.
class _PinnedTile extends StatelessWidget {
  const _PinnedTile({required this.account});
  final AccountController? account;

  @override
  Widget build(BuildContext context) {
    final a = account;
    final view = a?.view;
    if (a == null || view == null) return const SizedBox.shrink();
    final pin = activePin(DiscordPresence.instance.config.raw, DateTime.now().millisecondsSinceEpoch);
    final t = pin == null ? null : view.library.where((x) => x.id == pin.titleId).firstOrNull;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.push_pin_rounded),
      title: Text(t == null ? 'Show a title on Discord' : 'Showing on Discord: ${t.title}'),
      subtitle: Text(t == null ? 'Pick any Library title to show as if you\'re on it' : 'Shown on all your devices until you stop it'),
      trailing: t == null
          ? const Icon(Icons.chevron_right_rounded)
          : TextButton(onPressed: () => stopShowingOnDiscord(a), child: const Text('Stop')),
      onTap: t != null
          ? null
          : () async {
              final ids = await pickLibraryTitles(context, view, title: 'Show on Discord', single: true);
              if (ids != null && ids.isNotEmpty && context.mounted) await showOnDiscord(context, a, ids.first);
            },
    );
  }
}

/// Pins a title ("Show on Discord") after asking for how long.
Future<void> showOnDiscord(BuildContext context, AccountController account, String titleId) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const ListTile(title: Text('Show on Discord for…', style: TextStyle(fontWeight: FontWeight.w800))),
        for (final o in const [('stop', 'Until I stop it'), ('1h', '1 hour'), ('3h', '3 hours'), ('close', 'Until I close the app (this device)')])
          ListTile(title: Text(o.$2), onTap: () => Navigator.pop(c, o.$1)),
      ]),
    ),
  );
  if (choice == null) return;
  final now = DateTime.now().millisecondsSinceEpoch;
  final pinned = {
    'titleId': titleId,
    'until': switch (choice) { '1h' => now + 3600000, '3h' => now + 3 * 3600000, _ => 0 },
    'session': choice == 'close' ? kAppSessionId : '',
    'setAt': now,
  };
  final next = DiscordPresence.instance.config.withChanges({'pinned': pinned});
  DiscordPresence.instance.setConfig(PresenceConfig(next));
  await account.setSetting([PresenceConfig.key], next);
}

Future<void> stopShowingOnDiscord(AccountController account) async {
  final next = DiscordPresence.instance.config.withChanges({'pinned': null});
  DiscordPresence.instance.setConfig(PresenceConfig(next));
  await account.setSetting([PresenceConfig.key], next);
}

/// The SectionCard for Settings.
Widget discordSection(AccountController? account) => SectionCard(
      prefKey: 'app.discord',
      icon: Icons.videogame_asset_rounded,
      title: 'Discord',
      subtitle: 'Rich Presence: fully customizable, on every device',
      child: DiscordSettings(account: account),
    );
