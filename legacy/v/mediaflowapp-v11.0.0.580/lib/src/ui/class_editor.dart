// Add / Edit Category Class — every field of the website's editor
// (368-v481-category-class-management.js): class name; icon (MediaFlow
// icons, emoji & symbols, your saved icons, add an emoji or an icon link);
// colour (palette, your saved colours, any hex); class weight 1–5 and
// Enabled; assigned categories with search, "Show selected only", the
// selected count and "Currently in … · selection transfers it". Saving is the
// website's v480SaveClass (logic/category_classes.dart).

import 'package:flutter/material.dart';

import '../data/account_controller.dart';
import '../logic/categories.dart';
import '../logic/category_classes.dart';
import '../state/models.dart';
import '../util/js.dart';
import 'presence.dart';
import 'theme.dart';
import 'widgets.dart';

Future<void> openClassEditor(BuildContext context, AccountController account, Map<String, dynamic>? existing) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ClassEditorScreen(account: account, existing: existing)));

/// A class drawn like a category badge (its emoji, MediaFlow icon or icon link).
Widget classBadge(Map<String, dynamic> g, {double size = 36}) => CategoryBadge(
      Category({'name': jsStr(g['name']), 'icon': jsStr(g['icon']), 'iconUrl': jsStr(g['iconUrl']), 'color': jsStr(g['color'])}),
      size: size,
    );

class ClassEditorScreen extends StatefulWidget {
  const ClassEditorScreen({super.key, required this.account, this.existing});
  final AccountController account;
  final Map<String, dynamic>? existing;

  @override
  State<ClassEditorScreen> createState() => _ClassEditorScreenState();
}

class _ClassEditorScreenState extends State<ClassEditorScreen> {
  late final Map<String, dynamic>? g = widget.existing;
  late final _name = TextEditingController(text: jsStr(g?['name']));
  late String _icon = jsStr(g?['icon']).isEmpty ? '✨' : jsStr(g?['icon']);
  late final _iconUrl = TextEditingController(text: safeCategoryIconUrl(g?['iconUrl']));
  late String _color = (jsStr(g?['color']).isEmpty ? '#A78BFA' : jsStr(g?['color'])).toUpperCase();
  late int _weight = jsNum(g?['weight']).round().clamp(1, 5).toInt();
  late bool _enabled = g?['enabled'] != false;
  late final Set<String> _members = {for (final c in asList(g?['categoryIds'])) jsStr(c)};
  final _customEmoji = TextEditingController();
  final _hex = TextEditingController();
  final _search = TextEditingController();
  bool _onlySelected = false, _saving = false;

  AccountController get account => widget.account;
  Map<String, dynamic>? get _settings => asMap(account.view?.state['settings']);

  @override
  void dispose() {
    for (final c in [_name, _iconUrl, _customEmoji, _hex, _search]) {
      c.dispose();
    }
    super.dispose();
  }

  void _toast(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  Future<void> _savePalette(String key, List<Object> rows) => account.setSetting([key], rows);

  Future<void> _save() async {
    final view = account.view;
    if (_saving || view == null) return;
    final name = _name.text.trim();
    if (name.isEmpty) return _toast('Enter a class name');
    final url = safeCategoryIconUrl(_iconUrl.text);
    if (_iconUrl.text.trim().isNotEmpty && url.isEmpty) return _toast('Use an http(s) icon link or one of the MediaFlow icons.');
    setState(() => _saving = true);
    final ids = view.categories.map((c) => c.id);
    final prefs = cleanCategoryClasses(_settings?['v480CategoryClasses'], ids);
    final item = <String, dynamic>{
      'id': jsStr(g?['id']).isEmpty ? mediaFlowUid(DateTime.now().millisecondsSinceEpoch) : jsStr(g?['id']),
      'name': name.length > 80 ? name.substring(0, 80) : name,
      'icon': url.isNotEmpty ? '🖼️' : _icon,
      'iconUrl': url,
      'color': _color,
      'weight': _weight,
      'enabled': _enabled,
      'categoryIds': [for (final c in view.categories) if (_members.contains(c.id)) c.id],
    };
    await account.setSetting(['v480CategoryClasses'], cleanCategoryClasses(saveCategoryClass(prefs, item), ids));
    if (!mounted) return;
    _toast('Category Class saved');
    Navigator.of(context).pop();
  }

  Widget _label(String t, [String? sub]) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t, style: TextStyle(color: MF.textDim, fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: .6)),
          if (sub != null) Text(sub, style: TextStyle(color: MF.textDim, fontSize: 12)),
        ]),
      );

  Widget _swatch({required bool selected, required Widget child, required VoidCallback onTap, VoidCallback? onRemove, Color? fill}) =>
      Stack(clipBehavior: Clip.none, children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: fill ?? MF.raised,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: selected ? MF.text : MF.border, width: selected ? 2.5 : 1),
            ),
            child: child,
          ),
        ),
        if (onRemove != null)
          Positioned(
            right: -6,
            top: -6,
            child: InkWell(
              onTap: onRemove,
              child: Container(
                decoration: BoxDecoration(color: MF.surface, shape: BoxShape.circle, border: Border.all(color: MF.border)),
                child: const Icon(Icons.close_rounded, size: 14),
              ),
            ),
          ),
      ]);

  @override
  Widget build(BuildContext context) {
    final view = account.view;
    final settings = _settings;
    final savedIcons = savedCategoryIcons(settings);
    final savedColors = savedCategoryColors(settings);
    final url = safeCategoryIconUrl(_iconUrl.text);
    final prefs = view == null ? const <String, dynamic>{} : cleanCategoryClasses(settings?['v480CategoryClasses'], view.categories.map((c) => c.id));
    final owners = <String, Map<String, dynamic>>{};
    for (final x in asList(prefs['classes'])) {
      for (final c in asList(asMap(x)!['categoryIds'])) {
        owners[jsStr(c)] = asMap(x)!;
      }
    }
    final q = _search.text.trim().toLowerCase();
    final cats = [
      for (final c in view?.categories ?? const <Category>[])
        if ((q.isEmpty || c.name.toLowerCase().contains(q)) && (!_onlySelected || _members.contains(c.id))) c,
    ];
    return PresenceScope(
      info: PresenceInfo(situation: 'settings', values: {'action': g == null ? 'Adding a Category Class' : 'Editing a Category Class'}),
      child: Scaffold(
        appBar: AppBar(title: Text(g == null ? 'Add Category Class' : 'Edit Category Class')),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(onPressed: _saving ? null : _save, icon: const Icon(Icons.check_rounded), label: const Text('Save Class')),
              ),
            ]),
          ),
        ),
        body: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 32), children: [
          Text('Customize the class and assign categories', style: TextStyle(color: MF.textDim)),
          const SizedBox(height: 12),
          Row(children: [
            classBadge({'name': _name.text, 'icon': _icon, 'iconUrl': url, 'color': _color}, size: 52),
            const SizedBox(width: 12),
            Expanded(
              child: Text(_name.text.isEmpty ? 'New class' : _name.text,
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: MF.parseColor(_color))),
            ),
          ]),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            maxLength: 80,
            decoration: const InputDecoration(labelText: 'Class name', hintText: 'e.g. Anime', counterText: ''),
            onChanged: (_) => setState(() {}),
          ),
          _label('ICON', 'MediaFlow icons · Built-in artwork'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final b in kBuiltInCategoryIcons)
              Tooltip(
                message: b.$1,
                child: _swatch(
                  selected: url == b.$2,
                  onTap: () => setState(() => _iconUrl.text = b.$2),
                  child: NetIcon(url: categoryIconUrl(b.$2), size: 30, fallback: const Icon(Icons.image_outlined, size: 18)),
                ),
              ),
          ]),
          const SizedBox(height: 12),
          Text('Emoji & symbols', style: TextStyle(color: MF.textDim, fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final e in kIconChoices)
              _swatch(
                selected: url.isEmpty && _icon == e,
                onTap: () => setState(() {
                  _icon = e;
                  _iconUrl.clear();
                }),
                child: Text(e, style: const TextStyle(fontSize: 20)),
              ),
          ]),
          const SizedBox(height: 12),
          Text('Your saved icons', style: TextStyle(color: MF.textDim, fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          if (savedIcons.isEmpty) Text('None yet — add an emoji or an icon link below.', style: TextStyle(color: MF.textDim, fontSize: 12)),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final (i, row) in savedIcons.indexed)
              _swatch(
                selected: row['type'] == 'url' ? url == row['value'] : (url.isEmpty && _icon == row['value']),
                onTap: () => setState(() {
                  if (row['type'] == 'url') {
                    _iconUrl.text = jsStr(row['value']);
                  } else {
                    _icon = jsStr(row['value']);
                    _iconUrl.clear();
                  }
                }),
                onRemove: () => _savePalette('customCategoryIcons', [...savedIcons]..removeAt(i)),
                child: row['type'] == 'url'
                    ? NetIcon(url: categoryIconUrl(jsStr(row['value'])), size: 26, fallback: const Icon(Icons.link_rounded, size: 18))
                    : Text(jsStr(row['value']), style: const TextStyle(fontSize: 20)),
              ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: TextField(controller: _customEmoji, decoration: const InputDecoration(labelText: 'Add emoji / symbol', hintText: '🧠', isDense: true))),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: () {
                final v = _customEmoji.text.trim().runes.take(12).map(String.fromCharCode).join();
                if (v.isEmpty) return _toast('Enter an emoji or symbol first.');
                if (!savedIcons.any((x) => x['type'] == 'emoji' && x['value'] == v)) {
                  _savePalette('customCategoryIcons', [...savedIcons, {'type': 'emoji', 'value': v}]);
                }
                setState(() {
                  _icon = v;
                  _iconUrl.clear();
                  _customEmoji.clear();
                });
              },
              child: const Text('Add'),
            ),
          ]),
          const SizedBox(height: 10),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              child: TextField(
                controller: _iconUrl,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(labelText: 'Add icon URL', hintText: 'https://example.com/icon.png', isDense: true),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: url.isEmpty
                  ? null
                  : () {
                      if (!savedIcons.any((x) => x['type'] == 'url' && x['value'] == url)) {
                        _savePalette('customCategoryIcons', [...savedIcons, {'type': 'url', 'value': url}]);
                      }
                      _toast('Icon saved ✓');
                    },
              child: const Text('Add'),
            ),
          ]),
          _label('COLOR'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final c in kColorChoices)
              _swatch(selected: _color == c.toUpperCase(), fill: MF.parseColor(c), onTap: () => setState(() => _color = c.toUpperCase()), child: const SizedBox()),
          ]),
          const SizedBox(height: 12),
          Text('Your saved colors', style: TextStyle(color: MF.textDim, fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final (i, c) in savedColors.indexed)
              _swatch(
                selected: _color == c,
                fill: MF.parseColor(c),
                onTap: () => setState(() => _color = c),
                onRemove: () => _savePalette('customCategoryColors', [...savedColors]..removeAt(i)),
                child: const SizedBox(),
              ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: TextField(controller: _hex, decoration: const InputDecoration(labelText: 'Add custom color', hintText: '#AABBCC', isDense: true))),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: () {
                final v = normalizeHexColor(_hex.text);
                if (v == null) return _toast('Enter a valid hex color such as #7C5CFC.');
                if (!savedColors.contains(v)) _savePalette('customCategoryColors', [...savedColors, v]);
                setState(() {
                  _color = v;
                  _hex.clear();
                });
              },
              child: const Text('Add color'),
            ),
          ]),
          _label('CLASS SETTINGS'),
          Row(children: [
            const Text('Class weight (1–5)'),
            Expanded(
              child: Slider(value: _weight.toDouble(), min: 1, max: 5, divisions: 4, label: '$_weight', onChanged: (v) => setState(() => _weight = v.round())),
            ),
            Text('$_weight', style: const TextStyle(fontWeight: FontWeight.w800)),
          ]),
          SwitchListTile(contentPadding: EdgeInsets.zero, value: _enabled, onChanged: (v) => setState(() => _enabled = v), title: const Text('Enabled')),
          _label('ASSIGNED CATEGORIES', 'Search and select; category assignments are independent of category eligibility.'),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _search,
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Search categories…', isDense: true),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 10),
            Text('${_members.length} selected', style: const TextStyle(fontWeight: FontWeight.w800)),
          ]),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: _onlySelected,
            onChanged: (v) => setState(() => _onlySelected = v == true),
            title: const Text('Show selected only'),
          ),
          if (cats.isEmpty) Padding(padding: const EdgeInsets.all(8), child: Text('No matching categories.', style: TextStyle(color: MF.textDim))),
          for (final c in cats)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: _members.contains(c.id),
              onChanged: (v) => setState(() => v == true ? _members.add(c.id) : _members.remove(c.id)),
              secondary: CategoryBadge(c, size: 30),
              title: Text(c.name),
              subtitle: () {
                final owner = owners[c.id];
                final bits = [
                  if (!c.enabled) 'Disabled · not eligible for recommendations',
                  if (owner != null && jsStr(owner['id']) != jsStr(g?['id'])) 'Currently in ${jsStr(owner['name'])} · selection transfers it',
                ];
                return bits.isEmpty ? null : Text(bits.join('\n'));
              }(),
            ),
        ]),
      ),
    );
  }
}
