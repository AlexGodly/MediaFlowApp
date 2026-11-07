// Settings: the website's account settings (saved to the account, shared with
// the website) and this app's own settings (this device only).

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../data/account_controller.dart';
import '../data/app_prefs.dart';
import '../data/cover_cache.dart';
import '../logic/stats.dart' show kStatsComponents, statsComponentVisible;
import '../platform/desktop_tray.dart';
import '../platform/notifications.dart';
import '../state/models.dart';
import '../util/js.dart';
import 'discord_settings.dart';
import 'home_shell.dart' show Section;
import 'ratings_ui.dart';
import 'theme.dart';
import 'theme_settings.dart';
import 'widgets.dart';

void _toast(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 3)));

/// One account setting.
class _S {
  const _S(this.path, this.label, {this.help = '', this.kind = 'int', this.def, this.min = 0, this.max = 100000, this.choices = const []});
  final List<String> path;
  final String label, help, kind; // int | double | bool | choice
  final Object? def;
  final double min, max;
  final List<(String, String)> choices;
}

const _unitKeys = ['episodes', 'chapters', 'issues', 'movies', 'sessions', 'videos', 'pages', 'volumes', 'tracks', 'albums', 'levels', 'missions', 'matches', 'lessons', 'items'];
const _unitDefaults = {'episodes': 10, 'chapters': 3, 'issues': 6, 'movies': 30, 'sessions': 12, 'videos': 9, 'pages': 1, 'volumes': 14, 'tracks': 2, 'albums': 18, 'levels': 10, 'missions': 10, 'matches': 12, 'lessons': 8, 'items': 5};

final _sections = <(String, IconData, List<_S>)>[
  (
    'MediaFlow System',
    Icons.auto_awesome_rounded,
    [
      _S(['exactTitleRecommendations'], 'Recommend exact titles', kind: 'bool', def: false, help: 'MediaFlow Recommends picks a Library title, not just a category.'),
      _S(['prioritizePersonalOrder'], 'Prioritize Personal Order', kind: 'bool', def: false, help: 'Recommend the next title of your Personal Order first.'),
      _S(['dailyMinutes'], 'Daily minutes goal', def: 180, max: 1440),
      _S(['tasksPerDay'], 'Tasks per day', def: 5, max: 50),
      _S(['neglectRate'], 'Neglect bonus per idle day', def: 6),
      _S(['neglectCap'], 'Neglect bonus cap', def: 42),
      _S(['repetitionPenalty'], 'Repetition penalty', def: 12),
      _S(['consecutivePenalty'], 'Consecutive penalty', def: 26),
      _S(['saturationWeight'], 'Saturation weight', def: 20),
      _S(['seasonalBonus'], 'Seasonal bonus', def: 15),
      _S(['randomness'], 'Randomness (0–1)', kind: 'double', def: 0.28, max: 1),
    ]
  ),
  (
    'Default Logging Method',
    Icons.edit_note_rounded,
    [
      _S(['v369Logging', 'defaultInterface'], 'Logging interface', kind: 'choice', def: 'itemized', choices: [('itemized', 'Advanced (per unit)'), ('quick', 'Quick')]),
      _S(['v181Logging', 'defaultMode'], 'Quick logging mode', kind: 'choice', def: 'progress', choices: [('progress', 'Progress reached'), ('amount', 'Amount consumed')]),
      _S(['v419LoggingCollapsed'], 'Start with the Logging Workspace collapsed', kind: 'bool', def: false),
      _S(['v405ShowFloatingAdd'], 'Show the floating + button', kind: 'bool', def: true),
      _S(['v405ShowFloatingTaskProgress'], 'Show Floating Task Progress', kind: 'bool', def: true),
    ]
  ),
  (
    'Recovery Shortcuts & Background Processes',
    Icons.auto_fix_high_rounded,
    [
      _S(['v447RecoveryShortcuts', 'floating'], 'Recovery items in the + menu', kind: 'bool', def: true),
      _S(['v447RecoveryShortcuts', 'library'], 'Recovery in the Library menu', kind: 'bool', def: true),
      _S(['v447RecoveryShortcuts', 'editor'], 'Recovery in the title editor', kind: 'bool', def: true),
      _S(['v447RecoveryShortcuts', 'details'], 'Recovery in Title Details', kind: 'bool', def: true),
      _S(['v447RecoveryShortcuts', 'collections'], 'Recovery in Collections', kind: 'bool', def: true),
      _S(['v447RecoveryShortcuts', 'order'], 'Recovery in Personal Order', kind: 'bool', def: true),
      _S(['v447RecoveryShortcuts', 'widget'], 'Recovery shortcuts in Background Processes', kind: 'bool', def: true),
      _S(['v441RecoveryUI', 'visibility'], 'Background Processes widget', kind: 'choice', def: 'auto',
          choices: [('auto', 'While something runs'), ('always', 'Always'), ('hidden', 'Hidden')]),
      _S(['v441RecoveryUI', 'showFinished'], 'Keep finished jobs in the widget', kind: 'bool', def: false),
    ]
  ),
  (
    'Leveling & XP',
    Icons.military_tech_rounded,
    [
      _S(['leveling', 'enabled'], 'Leveling enabled', kind: 'bool', def: true),
      _S(['leveling', 'globalStreakMultiplierEnabled'], 'Day-streak multiplier', kind: 'bool', def: true),
      _S(['leveling', 'minuteXP'], 'XP per minute', kind: 'double', def: 1),
      _S(['leveling', 'libraryAdditionXP'], 'New Library title XP', def: 25),
      _S(['leveling', 'completionXP'], 'Completed title XP', def: 50),
      _S(['leveling', 'loggingCompletionBonusXP'], 'Logged completion bonus XP', def: 25),
      _S(['leveling', 'fullRepeatXP'], 'Full repeat XP', def: 50),
      _S(['leveling', 'libraryEditXP'], 'Edit Library title XP', def: 5),
      _S(['leveling', 'coverChangeXP'], 'Cover change XP', def: 15),
      _S(['leveling', 'ratingXP'], 'Rating XP', def: 10),
      _S(['leveling', 'firstTitleStartXP'], 'First title start XP', def: 40),
      _S(['leveling', 'firstEpisodeXP'], 'First episode XP', def: 20),
      _S(['leveling', 'batchLogXP'], 'Batch Log bonus XP', def: 15),
      _S(['leveling', 'collectionCreateXP'], 'Collection created XP', def: 35),
      _S(['leveling', 'collectionEditXP'], 'Collection edited XP', def: 10),
      _S(['leveling', 'collectionAddTitleXP'], 'Add title to Collection XP', def: 8),
      _S(['leveling', 'collectionReorderTitleXP'], 'Reorder Collection titles XP', def: 4),
      _S(['leveling', 'orderAddTitleXP'], 'Add title to Personal Order XP', def: 6),
      _S(['leveling', 'orderAddCollectionXP'], 'Add Collection to Personal Order XP', def: 12),
      _S(['leveling', 'orderReorderTitleXP'], 'Reorder Personal Order titles XP', def: 4),
      _S(['leveling', 'orderReorderCollectionXP'], 'Reorder Personal Order Collections XP', def: 6),
      _S(['leveling', 'rotationMultiplier', 'neglected'], 'Rotation ×: neglected', kind: 'double', def: 10),
      _S(['leveling', 'rotationMultiplier', 'due'], 'Rotation ×: due', kind: 'double', def: 8),
      _S(['leveling', 'rotationMultiplier', 'healthy'], 'Rotation ×: healthy', kind: 'double', def: 5),
      _S(['leveling', 'rotationMultiplier', 'overused'], 'Rotation ×: overused', kind: 'double', def: 2),
      for (final u in _unitKeys) _S(['leveling', 'unitXP', u], 'XP per ${kUnits[u]![0]}', kind: 'double', def: _unitDefaults[u]),
    ]
  ),
  (
    'Library Experience',
    Icons.video_library_rounded,
    [
      _S(['v175PageSizes', 'library'], 'Library titles per page (website)', def: 50, min: 1, max: 5000),
      _S(['v175PageSizes', 'loggingLibrary'], 'Logging Library titles per page', def: 20, min: 1, max: 5000),
      _S(['v175PageSizes', 'orderLibrary'], 'Personal Order picker per page', def: 20, min: 1, max: 5000),
      _S(['v175PageSizes', 'batchLibrary'], 'Batch Log picker per page', def: 20, min: 1, max: 5000),
      _S(['historyPageSize'], 'History entries per page (website)', def: 10, min: 1, max: 5000),
    ]
  ),
  (
    'Dashboard',
    Icons.dashboard_rounded,
    [
      _S(['v192Dashboard', 'showTodayBalance'], "Show Today's Balance", kind: 'bool', def: true),
      _S(['v192Dashboard', 'showOnThisDay'], 'Show On This Day', kind: 'bool', def: true),
      _S(['v192Dashboard', 'showRatingQueue'], 'Show Rate Your Library', kind: 'bool', def: true),
      _S(['v192Dashboard', 'showMissingCovers'], 'Show Missing Covers', kind: 'bool', def: true),
      _S(['v192Dashboard', 'showStopwatch'], 'Show Stopwatch', kind: 'bool', def: true),
      _S(['v508Panels', 'todayBalance', 'metrics'], "Today's Balance totals", kind: 'choice', def: 'all', choices: [('all', 'All categories'), ('visible', 'Only shown categories')]),
      _S(['v508Panels', 'todayBalance', 'source'], "Today's Balance categories", kind: 'choice', def: 'categories',
          choices: [('categories', 'Enabled categories'), ('system', 'MediaFlow System categories'), ('custom', 'Custom'), ('libraryOverview', 'Same as Library Overview')]),
    ]
  ),
];

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.account});
  final AccountController account;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Settings'),
          actions: [SyncIndicator(account: account)],
          bottom: const TabBar(tabs: [Tab(text: 'Account settings'), Tab(text: 'This app')]),
        ),
        body: TabBarView(children: [
          _AccountSettings(account: account),
          _AppSettings(account: account),
        ]),
      ),
    );
  }
}

Object? _read(Map<String, dynamic> state, List<String> path) {
  Object? cur = state['settings'];
  for (final k in path) {
    final m = asMap(cur);
    if (m == null) return null;
    cur = m[k];
  }
  return cur;
}

class _AccountSettings extends StatelessWidget {
  const _AccountSettings({required this.account});
  final AccountController account;

  Future<void> _set(List<String> path, Object? value) async {
    await account.setSetting(path, value);
    // Website containers with their own stamp.
    final head = path.first;
    if (const ['v181Logging', 'v369Logging', 'v175PageSizes', 'v192Dashboard'].contains(head) && path.length > 1) {
      await account.setSetting([head, 'modifiedAt'], DateTime.now().millisecondsSinceEpoch);
    }
    if (head == 'v508Panels' && path.length > 2) {
      await account.setSetting(['v508Panels', path[1], 'modifiedAt'], DateTime.now().millisecondsSinceEpoch);
    }
  }

  Future<void> _edit(BuildContext context, _S s, Object? current) async {
    final c = TextEditingController(text: current == null ? '' : '$current');
    final v = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(s.label),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: TextInputType.numberWithOptions(decimal: s.kind == 'double'),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(s.kind == 'double' ? r'[0-9.,]' : r'[0-9]'))],
          decoration: InputDecoration(helperText: s.help.isEmpty ? 'Default: ${s.def}' : '${s.help} Default: ${s.def}'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(d, '\u0000default'), child: const Text('Default')),
          FilledButton(onPressed: () => Navigator.pop(d, c.text), child: const Text('Save')),
        ],
      ),
    );
    c.dispose();
    if (v == null) return;
    num? n = v == '\u0000default' ? (s.def as num?) : num.tryParse(v.replaceAll(',', '.'));
    if (n == null) return;
    n = n.clamp(s.min, s.max);
    await _set(s.path, s.kind == 'double' ? n : n.round());
  }

  @override
  Widget build(BuildContext context) {
    return LiveBuilder(
      listenable: account,
      builder: (context, _) {
        final view = account.view;
        if (view == null) return const SizedBox.shrink();
        final state = view.state;
        return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 40), children: [
          Text('These settings belong to your account: the website uses them too.', style: TextStyle(color: MF.textDim)),
          const SizedBox(height: 10),
          _intensity(context, state),
          SectionCard(
            prefKey: 'settings.theme',
            initiallyOpen: false,
            icon: Icons.palette_rounded,
            title: 'Theme',
            subtitle: 'Themes, Light / Dark and Dynamic Cover Theme',
            child: ThemeSettings(account: account, view: view),
          ),
          bulkRatingsSection(account),
          for (final sec in _sections)
            SectionCard(
              prefKey: 'settings.${sec.$1}',
              initiallyOpen: false,
              icon: sec.$2,
              title: sec.$1,
              child: Column(children: [for (final s in sec.$3) _row(context, state, s)]),
            ),
          SectionCard(
            prefKey: 'settings.categories',
            initiallyOpen: false,
            icon: Icons.category_rounded,
            title: 'Categories',
            subtitle: 'Enable, rename, targets and units',
            child: _CategoriesEditor(account: account, view: view),
          ),
          SectionCard(
            prefKey: 'settings.stats',
            initiallyOpen: false,
            icon: Icons.insights_rounded,
            title: 'Statistics sections',
            child: Column(children: [
              for (final comp in kStatsComponents)
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(comp.$2),
                  value: statsComponentVisible(state, comp.$1),
                  onChanged: (v) async {
                    await account.setSetting(['v186ControlCenter', 'statsComponents', 'values', comp.$1], v);
                    await account.setSetting(['v186ControlCenter', 'statsComponents', 'modifiedAt'], DateTime.now().millisecondsSinceEpoch);
                  },
                ),
            ]),
          ),
          SectionCard(
            prefKey: 'settings.scopes',
            initiallyOpen: false,
            icon: Icons.tune_rounded,
            title: 'Category scopes',
            subtitle: 'Which categories each feature uses',
            child: Column(children: [
              for (final k in const [('scheduler', 'MediaFlow System'), ('todayBalance', "Today's Balance (legacy)"), ('categoryBalance', 'Category balance (Statistics)'), ('saturation', 'Recent saturation (Statistics)')])
                _ScopeEditor(account: account, view: view, keyName: k.$1, label: k.$2),
            ]),
          ),
        ]);
      },
    );
  }

  Widget _intensity(BuildContext context, Map<String, dynamic> state) {
    const presets = [('light', 'Light', 3, 90), ('normal', 'Normal', 5, 180), ('marathon', 'Marathon', 8, 300)];
    final current = jsStr(_read(state, ['intensity'])).isEmpty ? 'normal' : jsStr(_read(state, ['intensity']));
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Intensity', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        SegmentedButton<String>(
          segments: [for (final p in presets) ButtonSegment(value: p.$1, label: Text(p.$2))],
          selected: {presets.any((p) => p.$1 == current) ? current : 'normal'},
          onSelectionChanged: (s) async {
            final p = presets.firstWhere((x) => x.$1 == s.first);
            await account.setSetting(['intensity'], p.$1);
            await account.setSetting(['tasksPerDay'], p.$3);
            await account.setSetting(['dailyMinutes'], p.$4);
          },
        ),
      ]),
    );
  }

  Widget _row(BuildContext context, Map<String, dynamic> state, _S s) {
    final raw = _read(state, s.path);
    switch (s.kind) {
      case 'bool':
        final v = raw == null ? s.def == true : raw == true || (raw != false && jsTruthy(raw));
        return SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(s.label),
          subtitle: s.help.isEmpty ? null : Text(s.help, style: const TextStyle(fontSize: 12)),
          value: v,
          onChanged: (x) => _set(s.path, x),
        );
      case 'choice':
        final v = raw == null || !s.choices.any((c) => c.$1 == jsStr(raw)) ? '${s.def}' : jsStr(raw);
        return ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(s.label),
          trailing: CompactDropdown<String>(value: v, items: s.choices, onChanged: (x) => _set(s.path, x), maxWidth: 220),
        );
      default:
        final v = raw ?? s.def;
        return ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(s.label),
          subtitle: s.help.isEmpty ? null : Text(s.help, style: const TextStyle(fontSize: 12)),
          trailing: Text('$v', style: const TextStyle(fontWeight: FontWeight.w800)),
          onTap: () => _edit(context, s, v),
        );
    }
  }
}

class _ScopeEditor extends StatelessWidget {
  const _ScopeEditor({required this.account, required this.view, required this.keyName, required this.label});
  final AccountController account;
  final AccountView view;
  final String keyName, label;

  @override
  Widget build(BuildContext context) {
    final scope = asMap(asMap(asMap(view.state['settings'])?['v186ControlCenter'])?[keyName]);
    final custom = scope?['mode'] == 'custom';
    final ids = scope?['categoryIds'] is List
        ? asList(scope!['categoryIds']).map(jsStr).toSet()
        : view.categories.where((c) => c.enabled).map((c) => c.id).toSet();
    Future<void> save(String mode, Set<String> next) async {
      await account.setSetting(['v186ControlCenter', keyName, 'mode'], mode);
      await account.setSetting(['v186ControlCenter', keyName, 'categoryIds'], [for (final c in view.categories) if (next.contains(c.id)) c.id]);
      await account.setSetting(['v186ControlCenter', keyName, 'modifiedAt'], DateTime.now().millisecondsSinceEpoch);
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(label),
        subtitle: Text(custom ? 'Own category selection' : 'Follows the main category settings'),
        value: custom,
        onChanged: (v) => save(v ? 'custom' : 'follow', ids),
      ),
      if (custom)
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final c in view.categories)
            FilterChip(
              label: Text(c.name),
              selected: ids.contains(c.id),
              onSelected: (v) => save('custom', v ? {...ids, c.id} : ({...ids}..remove(c.id))),
            ),
        ]),
      const Divider(),
    ]);
  }
}

class _CategoriesEditor extends StatelessWidget {
  const _CategoriesEditor({required this.account, required this.view});
  final AccountController account;
  final AccountView view;

  Future<void> _editCategory(BuildContext context, Category? cat) async {
    final raw = cat?.raw ?? const <String, dynamic>{};
    final name = TextEditingController(text: jsStr(raw['name']));
    final icon = TextEditingController(text: jsStr(raw['icon']));
    final color = TextEditingController(text: jsStr(raw['color']).isEmpty ? '#879cff' : jsStr(raw['color']));
    final target = TextEditingController(text: raw['target'] == null ? '1' : '${raw['target']}');
    final mpu = TextEditingController(text: raw['minutesPerUnit'] == null ? '24' : '${raw['minutesPerUnit']}');
    final weight = TextEditingController(text: raw['weight'] == null ? '1' : '${raw['weight']}');
    var unit = jsStr(raw['unit']).isEmpty ? 'episodes' : jsStr(raw['unit']);
    var type = jsStr(raw['type']).isEmpty ? 'video' : jsStr(raw['type']);
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, set) => AlertDialog(
          title: Text(cat == null ? 'New category' : 'Edit ${cat.name}'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
              Row(children: [
                Expanded(child: TextField(controller: icon, decoration: const InputDecoration(labelText: 'Icon (emoji)'))),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: color, decoration: const InputDecoration(labelText: 'Color (#RRGGBB)'))),
              ]),
              DropdownButtonFormField<String>(
                initialValue: kUnits.containsKey(unit) ? unit : 'episodes',
                decoration: const InputDecoration(labelText: 'Unit'),
                items: [for (final u in kUnits.keys) DropdownMenuItem(value: u, child: Text(u))],
                onChanged: (v) => set(() => unit = v ?? unit),
              ),
              DropdownButtonFormField<String>(
                initialValue: const ['video', 'reading', 'playing', 'listening'].contains(type) ? type : 'video',
                decoration: const InputDecoration(labelText: 'Media type'),
                items: const [
                  DropdownMenuItem(value: 'video', child: Text('Watching')),
                  DropdownMenuItem(value: 'reading', child: Text('Reading')),
                  DropdownMenuItem(value: 'playing', child: Text('Playing')),
                  DropdownMenuItem(value: 'listening', child: Text('Listening')),
                ],
                onChanged: (v) => set(() => type = v ?? type),
              ),
              Row(children: [
                Expanded(child: TextField(controller: target, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Target per task'))),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: mpu, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Minutes per unit'))),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: weight, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Weight'))),
              ]),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    final values = (name.text.trim(), icon.text.trim(), color.text.trim(), num.tryParse(target.text) ?? 1, num.tryParse(mpu.text) ?? 0, num.tryParse(weight.text) ?? 1);
    for (final c in [name, icon, color, target, mpu, weight]) {
      c.dispose();
    }
    if (ok != true || values.$1.isEmpty) return;
    await account.edit((s, now) {
      final cats = List<dynamic>.of(asList(s['categories']));
      final id = cat?.id ?? 'cat_${mediaFlowUid(now)}';
      final i = cats.indexWhere((c) => jsStr(asMap(c)?['id']) == id);
      final next = <String, dynamic>{
        ...?(i >= 0 ? asMap(cats[i]) : null),
        'id': id,
        'name': values.$1,
        'icon': values.$2.isEmpty ? '📚' : values.$2,
        'color': values.$3,
        'unit': unit,
        'type': type,
        'target': values.$4,
        'minutesPerUnit': values.$5,
        'weight': values.$6,
        if (i < 0) 'enabled': true,
      };
      if (i >= 0) {
        cats[i] = next;
      } else {
        cats.add(next);
        s['categoryOrder'] = [...asList(s['categoryOrder']).map(jsStr), id];
      }
      s['categories'] = cats;
    }, label: cat == null ? 'Add category' : 'Edit category');
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final c in view.categories)
        Row(children: [
          CategoryBadge(c, size: 30),
          const SizedBox(width: 10),
          Expanded(
            child: InkWell(
              onTap: () => _editCategory(context, c),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(c.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                Text('${fmtNumber(c.target ?? 1)} ${unitLabel(c.unit, c.target ?? 1)} per task · ${fmtNumber(c.minutesPerUnit)} min each',
                    style: TextStyle(color: MF.textDim, fontSize: 12)),
              ]),
            ),
          ),
          Switch(
            value: c.enabled,
            onChanged: (v) => account.edit((s, now) {
              for (final x in asList(s['categories'])) {
                if (jsStr(asMap(x)?['id']) == c.id) asMap(x)!['enabled'] = v;
              }
            }, label: v ? 'Enable category' : 'Disable category'),
          ),
        ]),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(onPressed: () => _editCategory(context, null), icon: const Icon(Icons.add_rounded), label: const Text('Add category')),
      ),
    ]);
  }
}

// ---- this app ----------------------------------------------------------------------------

class _AppSettings extends StatefulWidget {
  const _AppSettings({required this.account});
  final AccountController account;

  @override
  State<_AppSettings> createState() => _AppSettingsState();
}

class _AppSettingsState extends State<_AppSettings> {
  int? _coverBytes;
  String? _update;
  bool _checking = false;

  AccountController get account => widget.account;
  AppPrefs get prefs => AppPrefs.instance;

  @override
  void initState() {
    super.initState();
    CoverCache.instance.sizeBytes().then((b) {
      if (mounted) setState(() => _coverBytes = b);
    });
  }

  Future<void> _checkUpdate() async {
    setState(() {
      _checking = true;
      _update = null;
    });
    String result;
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
      final req = await client.getUrl(Uri.parse('https://api.github.com/repos/AlexGodly/MediaFlowApp/releases/latest'));
      req.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      final res = await req.close().timeout(const Duration(seconds: 12));
      final body = await res.transform(utf8.decoder).join();
      client.close();
      final j = jsonDecode(body) as Map;
      final name = '${j['name'] ?? j['tag_name'] ?? ''}';
      final tag = '${j['tag_name'] ?? ''}';
      final newer = isNewerVersion(tag, kAppVersionLabel);
      result = newer ? 'Newer version available: $name' : 'You have the latest version ($kAppVersionLabel).';
      if (newer) prefs.set('updateUrl', '${j['html_url'] ?? ''}');
    } catch (_) {
      result = 'Could not check for updates (offline?).';
    }
    if (mounted) {
      setState(() {
        _checking = false;
        _update = result;
      });
    }
  }

  String _bytes(int? b) => b == null ? '…' : b < 1024 * 1024 ? '${(b / 1024).toStringAsFixed(0)} KB' : '${(b / 1024 / 1024).toStringAsFixed(1)} MB';

  @override
  Widget build(BuildContext context) {
    return LiveBuilder(
      listenable: Listenable.merge([account, prefs]),
      builder: (context, _) {
        final pending = account.pendingCount;
        final updateUrl = prefs.get<String>('updateUrl', '');
        final start = prefs.get<String>('startTab', 'log');
        return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 40), children: [
          Text('These settings are for this device only.', style: TextStyle(color: MF.textDim)),
          const SizedBox(height: 10),
          SectionCard(
            prefKey: 'app.general',
            icon: Icons.phone_android_rounded,
            title: 'General',
            child: Column(children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Open on'),
                trailing: CompactDropdown<String>(
                  value: Section.values.any((s) => s.name == start) ? start : 'log',
                  items: [for (final s in Section.values) (s.name, s.label)],
                  onChanged: (v) => prefs.set('startTab', v),
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Remember Library layout and filters'),
                value: prefs.get<bool>('rememberLibraryUi', true),
                onChanged: (v) => prefs.set('rememberLibraryUi', v),
              ),
            ]),
          ),
          notificationsSection(context, () => setState(() {})),
          discordSection(widget.account),
          if (DesktopTray.supported)
            SectionCard(
              prefKey: 'app.windows',
              icon: Icons.desktop_windows_rounded,
              title: 'Windows',
              subtitle: 'Tray icon and start-up',
              child: Column(children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Keep running in the tray when closed'),
                  subtitle: const Text('Closing the window hides MediaFlow to the tray. Quit from the tray icon.'),
                  value: DesktopTray.instance.closeToTray,
                  onChanged: (v) async {
                    await DesktopTray.instance.setCloseToTray(v);
                    if (mounted) setState(() {});
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Start with Windows'),
                  value: DesktopTray.instance.startWithWindows,
                  onChanged: (v) async {
                    await DesktopTray.instance.setStartWithWindows(v);
                    if (mounted) setState(() {});
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Start minimised to the tray'),
                  subtitle: const Text('When Windows starts MediaFlow (needs "Keep running in the tray").'),
                  value: DesktopTray.instance.startMinimized,
                  onChanged: !DesktopTray.instance.closeToTray
                      ? null
                      : (v) async {
                          await DesktopTray.instance.setStartMinimized(v);
                          if (mounted) setState(() {});
                        },
                ),
              ]),
            ),
          SectionCard(
            prefKey: 'app.sync',
            icon: Icons.sync_rounded,
            title: 'Sync & offline',
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Sync when the app comes back'),
                subtitle: const Text('Pull the newest account and upload changes when you return to the app.'),
                value: prefs.get<bool>('syncOnResume', true),
                onChanged: (v) => prefs.set('syncOnResume', v),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(pending == 0 ? 'Everything is saved to your account' : '$pending change${pending == 1 ? '' : 's'} waiting to upload'),
                subtitle: Text(account.lastSynced == null ? 'Not synced yet this session' : 'Last synced ${TimeOfDay.fromDateTime(account.lastSynced!).format(context)}'),
                trailing: FilledButton.tonal(onPressed: account.sync, child: const Text('Sync now')),
              ),
              Text('Offline, everything still works: changes are kept on this device and uploaded when you are back online. '
                  'If the same thing was changed elsewhere, the newest change wins.', style: TextStyle(color: MF.textDim, fontSize: 12)),
            ]),
          ),
          SectionCard(
            prefKey: 'app.storage',
            icon: Icons.storage_rounded,
            title: 'Storage',
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Saved covers'),
              subtitle: Text('${_bytes(_coverBytes)} kept on this device for offline use'),
              trailing: TextButton(
                onPressed: () async {
                  await CoverCache.instance.clear();
                  final b = await CoverCache.instance.sizeBytes();
                  if (mounted) setState(() => _coverBytes = b);
                },
                child: const Text('Clear'),
              ),
            ),
          ),
          SectionCard(
            prefKey: 'app.updates',
            icon: Icons.system_update_rounded,
            title: 'Updates',
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('MediaFlow app $kAppVersionLabel'),
                subtitle: _update == null ? null : Text(_update!),
                trailing: _checking
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : FilledButton.tonal(onPressed: _checkUpdate, child: const Text('Check')),
              ),
              if (updateUrl.isNotEmpty && _update != null && _update!.startsWith('Newer'))
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: () => launchUrl(Uri.parse(updateUrl), mode: LaunchMode.externalApplication),
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: const Text('Open the download page'),
                  ),
                ),
              TextButton(
                onPressed: () => launchUrl(Uri.parse(kWebsiteUrl), mode: LaunchMode.externalApplication),
                child: const Text('Open the MediaFlow website'),
              ),
            ]),
          ),
          SectionCard(
            prefKey: 'app.diagnostics',
            initiallyOpen: false,
            icon: Icons.bug_report_outlined,
            title: 'Diagnostics',
            child: Builder(builder: (context) {
              final kinds = <String, int>{};
              for (final op in account.pendingOps) {
                kinds[op.kind] = (kinds[op.kind] ?? 0) + 1;
              }
              final view = account.view;
              final text = [
                'MediaFlow app $kAppVersionLabel',
                'Platform: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
                'Sync: ${account.status.name}${account.message == null ? '' : ' · ${account.message}'}',
                'Pending: ${kinds.isEmpty ? 'none' : kinds.entries.map((e) => '${e.key}×${e.value}').join(', ')}',
                'Library: ${view?.library.length ?? 0} titles · History: ${view?.logs.length ?? 0} logs',
                'Saved covers: ${_bytes(_coverBytes)}',
              ].join('\n');
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                SelectableText(text, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: text));
                      _toast(context, 'Diagnostics copied');
                    },
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    label: const Text('Copy'),
                  ),
                ),
              ]);
            }),
          ),
        ]);
      },
    );
  }
}


/// Settings → Notifications (this device): every kind on/off, times, quiet
/// hours and a test.
Widget notificationsSection(BuildContext context, VoidCallback changed) {
  final n = AppNotifications.instance;
  const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
  Future<({int h, int m})?> pick(({int h, int m}) t) async {
    final picked = await showTimePicker(context: context, initialTime: TimeOfDay(hour: t.h, minute: t.m));
    return picked == null ? null : (h: picked.hour, m: picked.minute);
  }

  Widget timeTile(String label, ({int h, int m}) t, bool enabled, Future<void> Function(({int h, int m})) set) => ListTile(
        contentPadding: const EdgeInsets.only(left: 16),
        dense: true,
        enabled: enabled,
        title: Text(label),
        trailing: Text(AppNotifications.fmt(t), style: const TextStyle(fontWeight: FontWeight.w800)),
        onTap: () async {
          final v = await pick(t);
          if (v == null) return;
          await set(v);
          changed();
        },
      );

  return SectionCard(
    prefKey: 'app.notifications',
    icon: Icons.notifications_active_rounded,
    title: 'Notifications',
    subtitle: 'What MediaFlow tells you on this device',
    child: Column(children: [
      if (!n.supported)
        const ListTile(contentPadding: EdgeInsets.zero, title: Text('Notifications are not available on this device.')),
      if (Platform.isWindows)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text('Timed notifications show while MediaFlow is running (it can keep running in the tray).',
              style: TextStyle(color: MF.textDim, fontSize: 12)),
        ),
      for (final t in kNotifTypes) ...[
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(t.title),
          subtitle: Text(t.subtitle),
          value: n.isOn(t.key),
          onChanged: (v) async {
            await n.setOn(t.key, v);
            changed();
          },
        ),
        if (t.time != null)
          timeTile(t.weekly ? 'Time' : 'At', n.timeOf(t.key), n.isOn(t.key), (v) => n.setTime(t.key, v.h, v.m)),
        if (t.weekly)
          ListTile(
            contentPadding: const EdgeInsets.only(left: 16),
            dense: true,
            enabled: n.isOn(t.key),
            title: const Text('Day'),
            trailing: DropdownButton<int>(
              value: n.weeklyDay,
              underline: const SizedBox.shrink(),
              items: [for (var d = 1; d <= 7; d++) DropdownMenuItem(value: d, child: Text(days[d - 1]))],
              onChanged: !n.isOn(t.key)
                  ? null
                  : (v) async {
                      if (v == null) return;
                      await n.setWeeklyDay(v);
                      changed();
                    },
            ),
          ),
      ],
      const Divider(height: 24),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Quiet hours'),
        subtitle: const Text('Nothing is shown in this window; timed ones wait until it ends'),
        value: n.quietOn,
        onChanged: (v) async {
          await n.setQuiet(on: v);
          changed();
        },
      ),
      timeTile('From', n.quietFrom, n.quietOn, (v) => n.setQuiet(from: v)),
      timeTile('Until', n.quietTo, n.quietOn, (v) => n.setQuiet(to: v)),
      const SizedBox(height: 6),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: n.supported ? n.test : null,
          icon: const Icon(Icons.notifications_rounded),
          label: const Text('Send a test notification'),
        ),
      ),
    ]),
  );
}
