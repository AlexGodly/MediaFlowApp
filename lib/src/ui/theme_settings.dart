// Settings → Theme: the website's theme system with all its options. Every
// choice is an account setting, so the website and the app look the same.

import 'package:flutter/material.dart';

import '../data/account_controller.dart';
import '../state/models.dart';
import '../util/js.dart';
import 'collections_screen.dart' show pickLibraryTitles;
import 'theme.dart';
import 'theme_catalog.dart';
import 'theme_controller.dart';
import 'theme_palette.dart';
import 'widgets.dart';

const _groups = [
  ('mediaflow', 'MediaFlow'),
  ('platform', 'Platform'),
  ('fullstyle', 'Full Style'),
  ('custom', 'Custom'),
];

const _customKeys = [
  ('bg', 'Background', '#0E111A'),
  ('panel', 'Panels', '#161B2A'),
  ('raised', 'Raised surfaces', '#1C2334'),
  ('border', 'Borders', '#2B3448'),
  ('text', 'Text', '#F4F6FB'),
  ('muted', 'Muted text', '#8D98AD'),
  ('accent', 'Accent', '#E8A94A'),
];

class ThemeSettings extends StatelessWidget {
  const ThemeSettings({super.key, required this.account, required this.view});
  final AccountController account;
  final AccountView view;

  Map<String, dynamic> get _s => asMap(view.state['settings']) ?? const {};

  Future<void> _set(List<String> path, Object? value, {String? stamp}) async {
    await account.setSetting(path, value);
    if (stamp != null) await account.setSetting([stamp, 'modifiedAt'], DateTime.now().millisecondsSinceEpoch);
  }

  String get _theme => jsStr(_s['theme']).isEmpty ? 'dark' : jsStr(_s['theme']);

  String get _group {
    if (_theme == 'custom') return 'custom';
    return kWebsiteThemes.where((t) => t.id == _theme).firstOrNull?.group ?? 'mediaflow';
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    final dynamicOn = s['dynamicCoverTheme'] == true;
    final globalOn = s['globalAppearanceEnabled'] != false;
    final base = staticPalette({...s, 'globalAppearanceEnabled': false}, kWebsiteThemes);
    final appearance = appearanceMode(s, base);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // ---- theme collection and theme ----
      Text('Theme collection', style: TextStyle(color: MF.textDim, fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final g in _groups)
          ChoiceChip(
            label: Text(g.$2),
            selected: _group == g.$1,
            onSelected: (_) {
              if (_group == g.$1) return;
              final first = switch (g.$1) {
                'platform' => 'platform-anilist-dark',
                'fullstyle' => 'fullstyle-netflix',
                'custom' => 'custom',
                _ => 'dark',
              };
              _set(['theme'], first);
            },
          ),
      ]),
      const SizedBox(height: 10),
      if (_group == 'custom') _customEditor(context) else _themeGrid(),
      const Divider(height: 28),
      // ---- global Light / Dark appearance (v106 / v132) ----
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Global Light / Dark appearance'),
        subtitle: const Text('On: standard light or dark surfaces with the theme’s accent. Off: the theme’s own colours.'),
        value: globalOn,
        onChanged: (v) => _set(['globalAppearanceEnabled'], v),
      ),
      if (globalOn || dynamicOn)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'light', label: Text('Light'), icon: Icon(Icons.light_mode_rounded)),
              ButtonSegment(value: 'dark', label: Text('Dark'), icon: Icon(Icons.dark_mode_rounded)),
            ],
            selected: {appearance},
            onSelectionChanged: (v) => _set(['appearanceMode'], v.first),
          ),
        ),
      const Divider(height: 28),
      // ---- Dynamic Cover Theme (v145 → v173) ----
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Dynamic Cover Theme'),
        subtitle: const Text('Colours the whole app from a cover. The selected theme is the fallback.'),
        value: dynamicOn,
        onChanged: (v) => _set(['dynamicCoverTheme'], v),
      ),
      if (dynamicOn) _dynamic(context, s),
    ]);
  }

  Widget _themeGrid() {
    final themes = kWebsiteThemes.where((t) => t.group == _group).toList();
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (final t in themes) _ThemeSwatch(def: t, selected: t.id == _theme, onTap: () => _set(['theme'], t.id)),
    ]);
  }

  Widget _customEditor(BuildContext context) {
    final c = asMap(_s['customTheme']) ?? const {};
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Custom theme colours', style: TextStyle(color: MF.textDim, fontWeight: FontWeight.w700)),
      for (final k in _customKeys)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: parseCssColor(c[k.$1]) ?? parseCssColor(k.$3),
              shape: BoxShape.circle,
              border: Border.all(color: MF.border),
            ),
          ),
          title: Text(k.$2),
          subtitle: Text(jsStr(c[k.$1]).isEmpty ? k.$3 : jsStr(c[k.$1])),
          trailing: const Icon(Icons.edit_rounded, size: 18),
          onTap: () async {
            final v = await _pickColor(context, k.$2, jsStr(c[k.$1]).isEmpty ? k.$3 : jsStr(c[k.$1]));
            if (v == null) return;
            await _set(['customTheme', k.$1], v);
          },
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          onPressed: () => _set(['customTheme'], {for (final k in _customKeys) k.$1: k.$3}),
          child: const Text('Reset custom colours'),
        ),
      ),
    ]);
  }

  Widget _dynamic(BuildContext context, Map<String, dynamic> s) {
    final mode = jsStr(s['v162ThemeCollection']).isEmpty ? 'dynamic' : jsStr(s['v162ThemeCollection']);
    final ctl = ThemeController.instance;
    final (intervalPath, stamp) = switch (mode) {
      'library' => (['v162LibraryTheme', 'intervalSec'], 'v162LibraryTheme'),
      'image' => (['v162ImageTheme', 'intervalSec'], 'v162ImageTheme'),
      'recommended-only' => (['v173RecommendedTheme', 'intervalSec'], 'v173RecommendedTheme'),
      'onthisday-only' => (['v173OnThisDayTheme', 'intervalSec'], 'v173OnThisDayTheme'),
      'source-picker' => (['v173SourcePickerTheme', 'intervalSec'], 'v173SourcePickerTheme'),
      _ => (['v163DynamicThemeIntervalSec'], null),
    };
    Object? cur = s;
    for (final k in intervalPath) {
      cur = asMap(cur)?[k];
    }
    final interval = clampInterval(cur);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      CompactDropdown<String>(
        value: kCoverThemeModes.any((m) => m.$1 == mode) ? mode : 'dynamic',
        items: kCoverThemeModes,
        onChanged: (v) => _set(['v162ThemeCollection'], v),
        maxWidth: 420,
      ),
      const SizedBox(height: 8),
      ListenableBuilder(
        listenable: ctl,
        builder: (context, _) => Text('Now: ${ctl.status}', style: TextStyle(color: MF.textDim, fontSize: 12.5)),
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Rotate every'),
        subtitle: Text('$interval seconds (when there is more than one cover)'),
        trailing: const Icon(Icons.edit_rounded, size: 18),
        onTap: () async {
          final v = await _askNumber(context, 'Rotate every (seconds, 5–3600)', interval);
          if (v != null) await _set(intervalPath, v.clamp(5, 3600), stamp: stamp);
        },
      ),
      if (mode == 'library') _libraryPicker(context, s),
      if (mode == 'image') _imageLinks(context, s),
      if (mode == 'source-picker') _sourcePicker(s),
    ]);
  }

  Widget _libraryPicker(BuildContext context, Map<String, dynamic> s) {
    final ids = asList(asMap(s['v162LibraryTheme'])?['titleIds']).map(jsStr).toList();
    final byId = {for (final t in view.library) t.id: t};
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final id in ids)
        if (byId[id] != null)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Cover(title: byId[id]!, category: view.category(byId[id]!.categoryId), width: 28),
            title: Text(byId[id]!.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: IconButton(
              tooltip: 'Remove',
              icon: const Icon(Icons.close_rounded),
              onPressed: () => _set(['v162LibraryTheme', 'titleIds'], ids.where((x) => x != id).toList(), stamp: 'v162LibraryTheme'),
            ),
          ),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          icon: const Icon(Icons.add_rounded),
          label: const Text('Add Library covers'),
          onPressed: () async {
            final picked = await pickLibraryTitles(context, view, exclude: ids.toSet(), title: 'Covers for the theme');
            if (picked == null || picked.isEmpty) return;
            await _set(['v162LibraryTheme', 'titleIds'], [...ids, ...picked], stamp: 'v162LibraryTheme');
          },
        ),
      ),
    ]);
  }

  Widget _imageLinks(BuildContext context, Map<String, dynamic> s) {
    final urls = asList(asMap(s['v162ImageTheme'])?['urls']).map(jsStr).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final u in urls)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Image.network(u, width: 28, height: 40, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined)),
          ),
          title: Text(u, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: IconButton(
            tooltip: 'Remove',
            icon: const Icon(Icons.close_rounded),
            onPressed: () => _set(['v162ImageTheme', 'urls'], urls.where((x) => x != u).toList(), stamp: 'v162ImageTheme'),
          ),
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          icon: const Icon(Icons.add_link_rounded),
          label: const Text('Add image link'),
          onPressed: () async {
            final c = TextEditingController();
            final v = await showDialog<String>(
              context: context,
              builder: (d) => AlertDialog(
                title: const Text('Image link'),
                content: TextField(controller: c, autofocus: true, decoration: const InputDecoration(hintText: 'https://…')),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
                  FilledButton(onPressed: () => Navigator.pop(d, c.text.trim()), child: const Text('Add')),
                ],
              ),
            );
            c.dispose();
            var url = (v ?? '').trim();
            if (url.startsWith('//')) url = 'https:$url';
            if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(url) || urls.contains(url)) return;
            await _set(['v162ImageTheme', 'urls'], [...urls, url], stamp: 'v162ImageTheme');
          },
        ),
      ),
    ]);
  }

  Widget _sourcePicker(Map<String, dynamic> s) {
    final raw = asList(asMap(s['v173SourcePickerTheme'])?['selectedKeys']).map(jsStr).toList();
    final keys = raw.isEmpty ? ['recommended'] : raw;
    final all = ThemeController.instance.availablePickerSources();
    if (all.isEmpty) {
      return Text('No covers available right now (no recommended title or On This Day titles with covers).',
          style: TextStyle(color: MF.textDim, fontSize: 12.5));
    }
    return Column(children: [
      for (final x in all)
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          value: keys.contains(x.key),
          title: Text(x.label, maxLines: 1, overflow: TextOverflow.ellipsis),
          onChanged: (v) {
            final next = v == true ? {...keys, x.key}.toList() : keys.where((k) => k != x.key).toList();
            _set(['v173SourcePickerTheme', 'selectedKeys'], next, stamp: 'v173SourcePickerTheme');
          },
        ),
    ]);
  }

  Future<int?> _askNumber(BuildContext context, String title, int current) async {
    final c = TextEditingController(text: '$current');
    final v = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(title),
        content: TextField(controller: c, autofocus: true, keyboardType: TextInputType.number),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(d, c.text), child: const Text('Save')),
        ],
      ),
    );
    c.dispose();
    return int.tryParse((v ?? '').trim());
  }

  Future<String?> _pickColor(BuildContext context, String label, String current) async {
    final c = TextEditingController(text: current);
    const presets = ['#0E111A', '#161B2A', '#1C2334', '#2B3448', '#F4F6FB', '#8D98AD', '#E8A94A', '#FF5D9E', '#55D6BE', '#69A7FF', '#B892FF', '#76C893', '#FF9F68', '#FFFFFF', '#000000'];
    final v = await showDialog<String>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, setState) {
          final color = parseCssColor(c.text);
          return AlertDialog(
            title: Text(label),
            content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(height: 40, decoration: BoxDecoration(color: color ?? Colors.transparent, borderRadius: BorderRadius.circular(8), border: Border.all(color: MF.border))),
              const SizedBox(height: 10),
              TextField(
                controller: c,
                decoration: InputDecoration(labelText: 'Hex colour', errorText: color == null ? 'Use #RRGGBB' : null),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 10),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final p in presets)
                  InkWell(
                    onTap: () => setState(() => c.text = p),
                    child: Container(width: 26, height: 26, decoration: BoxDecoration(color: parseCssColor(p), shape: BoxShape.circle, border: Border.all(color: MF.border))),
                  ),
              ]),
            ]),
            actions: [
              TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
              FilledButton(onPressed: color == null ? null : () => Navigator.pop(d, hexOf(color)), child: const Text('Save')),
            ],
          );
        },
      ),
    );
    c.dispose();
    return v;
  }
}

class _ThemeSwatch extends StatelessWidget {
  const _ThemeSwatch({required this.def, required this.selected, required this.onTap});
  final ThemeDef def;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = def.palette;
    return Tooltip(
      message: def.label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 104,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: p.bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: selected ? MF.accent : p.border, width: selected ? 2.5 : 1),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(width: 18, height: 18, decoration: BoxDecoration(color: p.flow, shape: BoxShape.circle)),
              const SizedBox(width: 4),
              Expanded(child: Container(height: 18, decoration: BoxDecoration(color: p.panel, borderRadius: BorderRadius.circular(4)))),
            ]),
            const SizedBox(height: 6),
            Text(def.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.text, fontSize: 11.5, fontWeight: FontWeight.w700)),
          ]),
        ),
      ),
    );
  }
}
