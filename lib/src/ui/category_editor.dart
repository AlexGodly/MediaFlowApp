// The full category editor (website v144/v200/v283/v369): name, icon (emoji
// palette, saved icons, or an icon link with preview), colour (palette, saved
// colours, any hex), unit, media type, target, weight, default runtime
// HH:MM:SS, seasonal, enabled and the default cover for titles without one;
// Clear (v282) and Delete (restorable, v171). Writes go through
// logic/categories.dart, which matches the website (category_golden_test).

import 'package:flutter/material.dart';

import '../data/account_controller.dart';
import '../logic/categories.dart';
import '../state/models.dart';
import '../util/js.dart';
import 'presence.dart';
import 'theme.dart';
import 'widgets.dart';

Future<void> openCategoryEditor(BuildContext context, AccountController account, Category? cat) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => CategoryEditorScreen(account: account, category: cat)));

class CategoryEditorScreen extends StatefulWidget {
  const CategoryEditorScreen({super.key, required this.account, this.category});
  final AccountController account;
  final Category? category;

  @override
  State<CategoryEditorScreen> createState() => _CategoryEditorScreenState();
}

class _CategoryEditorScreenState extends State<CategoryEditorScreen> {
  late final CategoryForm f = CategoryForm.of(widget.category?.raw);
  late final _name = TextEditingController(text: f.name);
  late final _iconUrl = TextEditingController(text: f.iconUrl);
  late final _cover = TextEditingController(text: f.missingCover);
  late final _target = TextEditingController(text: f.target);
  late final _h = TextEditingController(text: f.hours);
  late final _m = TextEditingController(text: f.minutes);
  late final _s = TextEditingController(text: f.seconds);
  final _customEmoji = TextEditingController();
  final _hex = TextEditingController();
  bool _saving = false;

  AccountController get account => widget.account;
  Map<String, dynamic>? get _settings => asMap(account.view?.state['settings']);

  @override
  void dispose() {
    for (final c in [_name, _iconUrl, _cover, _target, _h, _m, _s, _customEmoji, _hex]) {
      c.dispose();
    }
    super.dispose();
  }

  void _toast(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  Future<void> _save() async {
    if (_saving) return;
    f
      ..name = _name.text
      ..iconUrl = _iconUrl.text
      ..missingCover = _cover.text
      ..target = _target.text
      ..hours = _h.text
      ..minutes = _m.text
      ..seconds = _s.text;
    if (_iconUrl.text.trim().isNotEmpty && safeCategoryUrl(_iconUrl.text).isEmpty) {
      _toast('Use a valid http:// or https:// icon URL.');
      return;
    }
    setState(() => _saving = true);
    String? error;
    await account.edit((s, now) {
      var k = 0;
      error = saveCategory(s, widget.category?.id, f, now, () => mediaFlowUid(now + k++)).error;
    }, label: widget.category == null ? 'Add category' : 'Edit category');
    if (!mounted) return;
    setState(() => _saving = false);
    if (error != null) {
      _toast(error!);
      return;
    }
    _toast('${_name.text.trim().isEmpty ? 'Untitled category' : _name.text.trim()} saved');
    Navigator.pop(context);
  }

  Future<void> _savePalette(String key, List<Object> rows) => account.setSetting([key], rows);

  Future<void> _clear() async {
    final cat = widget.category!;
    final count = asList(account.view?.state['library']).where((i) => jsStr(asMap(i)?['categoryId']) == cat.id).length;
    if (count == 0) {
      _toast('${cat.name} is already empty');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Clear ${cat.name}?'),
        content: Text('Delete every Library title in this category ($count ${count == 1 ? 'title' : 'titles'}). '
            'The category stays; consumption History and Statistics stay intact, and the removed titles can be restored from Library History.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: MF.bad),
            onPressed: () => Navigator.pop(d, true),
            child: Text('Clear $count ${count == 1 ? 'title' : 'titles'}'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    String msg = '';
    await account.edit((s, now) {
      var k = 0;
      msg = clearCategory(s, cat.id, now, () => mediaFlowUid(now + k++));
    }, label: 'Clear category');
    if (mounted) _toast(msg);
  }

  Future<void> _delete() async {
    final cat = widget.category!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Delete ${cat.name}?'),
        content: const Text('Recovery available: the most recently deleted category can be restored from Settings → Categories until another '
            'category is deleted. Past history is kept.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: MF.bad), onPressed: () => Navigator.pop(d, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    await account.edit((s, now) => deleteCategory(s, cat.id, now), label: 'Delete category');
    if (!mounted) return;
    _toast('${cat.name} deleted');
    Navigator.pop(context);
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 8),
        child: Text(t, style: TextStyle(color: MF.textDim, fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: .6)),
      );

  Widget _swatch({required bool selected, required Widget child, required VoidCallback onTap, VoidCallback? onRemove, Color? fill}) => Stack(
        clipBehavior: Clip.none,
        children: [
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
        ],
      );

  Widget _preview() {
    final raw = <String, dynamic>{
      'name': _name.text.isEmpty ? 'Category' : _name.text,
      'icon': f.icon,
      'iconUrl': safeCategoryUrl(_iconUrl.text),
      'color': f.color,
    };
    return Row(children: [
      CategoryBadge(Category(raw), size: 52),
      const SizedBox(width: 12),
      Expanded(
        child: Text(_name.text.isEmpty ? 'New category' : _name.text,
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: MF.parseColor(f.color))),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    final savedIcons = savedCategoryIcons(settings);
    final savedColors = savedCategoryColors(settings);
    final url = safeCategoryUrl(_iconUrl.text);
    final cover = safeCategoryUrl(_cover.text);
    return PresenceScope(
      info: PresenceInfo(situation: 'settings', values: {'action': widget.category == null ? 'Adding a category' : 'Editing a category'}),
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.category == null ? 'New category' : 'Edit category'),
          actions: [
            if (widget.category != null)
              PopupMenuButton<String>(
                onSelected: (v) => v == 'clear' ? _clear() : _delete(),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'clear', child: Text('Clear its Library titles…')),
                  PopupMenuItem(value: 'delete', child: Text('Delete category…')),
                ],
              ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.check_rounded),
              label: const Text('Save category'),
            ),
          ),
        ),
        body: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 32), children: [
          _preview(),
          const SizedBox(height: 12),
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'Name'), onChanged: (_) => setState(() {})),
          _label('ICON'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final e in kIconChoices)
              _swatch(
                selected: url.isEmpty && f.icon == e,
                onTap: () => setState(() {
                  f.icon = e;
                  _iconUrl.clear();
                }),
                child: Text(e, style: const TextStyle(fontSize: 20)),
              ),
            for (final (i, row) in savedIcons.indexed)
              _swatch(
                selected: row['type'] == 'url' ? url == row['value'] : (url.isEmpty && f.icon == row['value']),
                onTap: () => setState(() {
                  if (row['type'] == 'url') {
                    _iconUrl.text = jsStr(row['value']);
                  } else {
                    f.icon = jsStr(row['value']);
                    _iconUrl.clear();
                  }
                }),
                onRemove: () => _savePalette('customCategoryIcons', [...savedIcons]..removeAt(i)),
                child: row['type'] == 'url'
                    ? NetIcon(url: jsStr(row['value']), size: 26, fallback: const Icon(Icons.link_rounded, size: 18))
                    : Text(jsStr(row['value']), style: const TextStyle(fontSize: 20)),
              ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: TextField(controller: _customEmoji, decoration: const InputDecoration(labelText: 'Any emoji or symbol', isDense: true))),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: () {
                final v = _customEmoji.text.trim().runes.take(12).map(String.fromCharCode).join();
                if (v.isEmpty) return _toast('Enter an emoji or symbol first.');
                if (!savedIcons.any((x) => x['type'] == 'emoji' && x['value'] == v)) {
                  _savePalette('customCategoryIcons', [...savedIcons, {'type': 'emoji', 'value': v}]);
                }
                setState(() {
                  f.icon = v;
                  _iconUrl.clear();
                  _customEmoji.clear();
                });
                _toast('Custom icon saved ✓');
              },
              child: const Text('Use & save'),
            ),
          ]),
          const SizedBox(height: 10),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              child: TextField(
                controller: _iconUrl,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(labelText: 'Icon URL (PNG, SVG, WebP…)', isDense: true),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 8),
            if (url.isNotEmpty)
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: MF.raised, borderRadius: BorderRadius.circular(8)),
                child: NetIcon(url: url, size: 28, fallback: Icon(Icons.broken_image_outlined, size: 18, color: MF.textDim)),
              ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: url.isEmpty
                  ? null
                  : () {
                      if (!savedIcons.any((x) => x['type'] == 'url' && x['value'] == url)) {
                        _savePalette('customCategoryIcons', [...savedIcons, {'type': 'url', 'value': url}]);
                      }
                      _toast('URL icon saved ✓');
                    },
              child: const Text('Save'),
            ),
          ]),
          _label('COLOUR'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final c in kColorChoices)
              _swatch(selected: f.color.toUpperCase() == c, fill: MF.parseColor(c), onTap: () => setState(() => f.color = c), child: const SizedBox()),
            for (final (i, c) in savedColors.indexed)
              _swatch(
                selected: f.color.toUpperCase() == c,
                fill: MF.parseColor(c),
                onTap: () => setState(() => f.color = c),
                onRemove: () => _savePalette('customCategoryColors', [...savedColors]..removeAt(i)),
                child: const SizedBox(),
              ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: TextField(controller: _hex, decoration: const InputDecoration(labelText: 'Any hex colour (#7C5CFC)', isDense: true))),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: () {
                final v = normalizeHexColor(_hex.text);
                if (v == null) return _toast('Enter a valid hex color such as #7C5CFC.');
                if (!savedColors.contains(v)) _savePalette('customCategoryColors', [...savedColors, v]);
                setState(() {
                  f.color = v;
                  _hex.clear();
                });
                _toast('Custom color saved ✓');
              },
              child: const Text('Use & save'),
            ),
          ]),
          _label('TRACKING'),
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: kUnits.containsKey(f.unit) ? f.unit : 'episodes',
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Unit'),
                items: [for (final u in kUnits.keys) DropdownMenuItem(value: u, child: Text(kUnits[u]![1]))],
                onChanged: (v) => setState(() => f.unit = v ?? f.unit),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: const ['video', 'reading', 'playing', 'listening'].contains(f.type) ? f.type : 'video',
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Type'),
                items: const [
                  DropdownMenuItem(value: 'video', child: Text('Watching')),
                  DropdownMenuItem(value: 'reading', child: Text('Reading')),
                  DropdownMenuItem(value: 'playing', child: Text('Playing')),
                  DropdownMenuItem(value: 'listening', child: Text('Listening')),
                ],
                onChanged: (v) => setState(() => f.type = v ?? f.type),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          TextField(
            controller: _target,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: 'Suggested target per task (${unitLabel(f.unit, 2)})', helperText: 'At least 1'),
          ),
          const SizedBox(height: 14),
          Text('Weight · ${f.weight}', style: const TextStyle(fontWeight: FontWeight.w700)),
          Slider(
            value: (jsNumOrNull(f.weight) ?? 3).clamp(1, 5).toDouble(),
            min: 1,
            max: 5,
            divisions: 4,
            label: f.weight,
            onChanged: (v) => setState(() => f.weight = '${v.round()}'),
          ),
          Text('How often the MediaFlow System picks this category, from 1 (rarely) to 5 (often).', style: TextStyle(color: MF.textDim, fontSize: 12)),
          const SizedBox(height: 14),
          const Text('Default runtime per unit (HH:MM:SS)', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Row(children: [
            for (final (c, l) in [(_h, 'Hours'), (_m, 'Minutes'), (_s, 'Seconds')]) ...[
              Expanded(child: TextField(controller: c, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: l, isDense: true))),
              if (l != 'Seconds') const SizedBox(width: 8),
            ],
          ]),
          Text('Applied to each new itemized unit. Existing saved runtimes are never overwritten.', style: TextStyle(color: MF.textDim, fontSize: 12)),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Seasonal'),
            subtitle: const Text('Airing-season titles (seasonal bonus and fresh-episode rules)'),
            value: f.seasonal,
            onChanged: (v) => setState(() => f.seasonal = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Enabled'),
            subtitle: const Text('Used by the MediaFlow System and shown in pickers'),
            value: f.enabled,
            onChanged: (v) => setState(() => f.enabled = v),
          ),
          _label('MISSING DEFAULT COVER'),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: TextField(
                controller: _cover,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(labelText: 'Cover URL for titles without one', helperText: 'Only shown; never saved into titles', isDense: true),
                onChanged: (_) => setState(() {}),
              ),
            ),
            if (cover.isNotEmpty) ...[
              const SizedBox(width: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.network(cover, width: 44, height: 64, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(width: 44, height: 64, color: MF.raised, child: const Icon(Icons.broken_image_outlined, size: 18))),
              ),
            ],
          ]),
        ]),
      ),
    );
  }
}
