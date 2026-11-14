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
import '../logic/categories.dart';
import '../logic/extras.dart' show balancePanel, editPanel;
import '../logic/stats.dart' show kStatsComponents, statsComponentVisible;
import '../platform/desktop_tray.dart';
import '../platform/diagnostics.dart';
import '../platform/notifications.dart';
import '../state/models.dart';
import '../util/js.dart';
import 'api_providers.dart';
import 'app_nav.dart' show openNavigationSettings;
import '../logic/action_xp.dart' show kActionXpGroups;
import '../logic/category_classes.dart';
import 'class_editor.dart' show classBadge, openClassEditor;
import '../logic/choice_layout.dart';
import '../logic/title_names.dart';
import 'category_editor.dart';
import 'data_cloud.dart';
import 'discord_settings.dart';
import 'home_shell.dart' show Section;
import 'ratings_ui.dart';
import 'theme.dart';
import 'offline_covers_ui.dart';
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
      // Website Scheduler tuning: fresh Seasonal Anime episodes (checked by the website).
      _S(['seasonalFreshAuto'], 'Find fresh Seasonal Anime episodes automatically', kind: 'bool', def: true,
          help: 'From Jikan / MyAnimeList episode data.'),
      _S(['seasonalFreshSyncMinutes'], 'Fresh-episode check every (minutes)', def: 60, min: 5, max: 1440),
      _S(['seasonalFreshCount'], 'Fresh Seasonal Anime episodes (manual)', def: 0, max: 500),
    ]
  ),
  (
    'Default Logging Method',
    Icons.edit_note_rounded,
    [
      _S(['v369Logging', 'defaultInterface'], 'Logging interface', kind: 'choice', def: 'itemized', choices: [('itemized', 'Advanced (per unit)'), ('quick', 'Quick')]),
      _S(['v181Logging', 'defaultMode'], 'Quick logging mode', kind: 'choice', def: 'progress', choices: [('progress', 'Progress reached'), ('amount', 'Amount consumed')]),
      _S(['v419LoggingCollapsed'], 'Start with the Logging Workspace collapsed', kind: 'bool', def: false),
      // 7.0.0 / website v566 (shared with the website).
      _S(['mf566LogTime'], 'Log time', kind: 'choice', def: 'unit',
          help: 'When a log is saved, its titles count on the day you consumed them. Streaks, History and Statistics follow.',
          choices: [('unit', 'When each unit was logged'), ('added', 'When the title was added to the log')]),
    ]
  ),
  (
    'Floating Controls',
    Icons.picture_in_picture_alt_rounded,
    [
      // Website Settings → Appearance → Floating Controls (v405, v441, v565).
      // Quick Actions
      _S(['v405ShowFloatingAdd'], 'Show the floating + button', kind: 'bool', def: true),
      // Progress Widgets
      _S(['v405ShowFloatingTaskProgress'], 'Show Floating Task Progress', kind: 'bool', def: true),
      _S(['mf565TaskFinish'], 'Task progress finishes at', kind: 'choice', def: 'minimum',
          help: 'Where the card reaches 100% for a goal like 9–13.', choices: [('minimum', 'Minimum (9 of 9–13)'), ('maximum', 'Maximum (13 of 9–13)')]),
      _S(['mf565TaskOver'], 'When you go over the maximum', kind: 'choice', def: 'count',
          choices: [('count', 'Count past 100%'), ('warning', 'Warning colour'), ('status', 'Status only')]),
      // Background Processes (the position itself stays on each device)
      _S(['v441RecoveryUI', 'visibility'], 'Background Processes widget', kind: 'choice', def: 'auto',
          choices: [('auto', 'While something runs'), ('always', 'Always'), ('hidden', 'Hidden')]),
      _S(['v441RecoveryUI', 'showFinished'], 'Keep finished jobs in the widget', kind: 'bool', def: false),
      _S(['mf565Processes', 'position'], 'Background Processes: when it reopens', kind: 'choice', def: 'remember', choices: [('remember', 'Where I left it'), ('default', 'Always at the default spot')]),
      _S(['mf565Processes', 'edges'], 'Background Processes: after moving it', kind: 'choice', def: 'stay', choices: [('stay', 'Stay where dropped'), ('snap', 'Snap to nearest edge')]),
      _S(['mf565Processes', 'icon'], 'Background Processes: minimised icon', kind: 'choice', def: 'both',
          choices: [('both', 'Progress ring and count'), ('ring', 'Progress ring'), ('count', 'Count of running jobs'), ('plain', 'Plain icon')]),
      _S(['mf565Processes', 'idle'], 'Background Processes: when nothing is running', kind: 'choice', def: 'hide', choices: [('hide', 'Hide the icon'), ('show', 'Always show it')]),
    ]
  ),
  (
    'Recovery Shortcuts',
    Icons.auto_fix_high_rounded,
    [
      _S(['v447RecoveryShortcuts', 'floating'], 'Recovery items in the + menu', kind: 'bool', def: true),
      _S(['v447RecoveryShortcuts', 'editor'], 'Recovery in the title editor', kind: 'bool', def: true),
      _S(['v447RecoveryShortcuts', 'details'], 'Recovery in Title Details', kind: 'bool', def: true),
      _S(['v447RecoveryShortcuts', 'collections'], 'Recovery in Collections', kind: 'bool', def: true),
      _S(['v447RecoveryShortcuts', 'order'], 'Recovery in Personal Order', kind: 'bool', def: true),
      _S(['v447RecoveryShortcuts', 'widget'], 'Recovery shortcuts in Background Processes', kind: 'bool', def: true),
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
      // Website v580: task goal XP (once per task, by any log).
      _S(['mf580GoalXP', 'enabled'], 'Task goal XP', kind: 'bool', def: true,
          help: 'XP for reaching a recommendation\'s goal, once per task, by any log (Logging, Log any title).'),
      _S(['mf580GoalXP', 'min'], 'Task goal: reaching the minimum XP', def: 100),
      _S(['mf580GoalXP', 'max'], 'Task goal: reaching the maximum XP (more)', def: 300),
      _S(['mf580GoalXP', 'perExtra'], 'Task goal: each unit past the maximum XP', def: 10, max: 10000),
      _S(['mf580GoalXP', 'extraCap'], 'Task goal: past the maximum, at most XP', def: 100),
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
      // v565: XP for every action, background work and time away (0 turns one off).
      for (final g in kActionXpGroups) _S(['leveling', 'mf565ActionXP', g.$1], 'Action XP: ${g.$2}', kind: 'double', def: g.$3),
      _S(['leveling', 'mf565BackupXP'], 'Automatic backup XP', kind: 'double', def: 5),
      _S(['leveling', 'mf565RecoveryXP'], 'Finished recovery XP', kind: 'double', def: 10),
      _S(['leveling', 'mf565FreshCheckXP'], 'Fresh-episode check XP', kind: 'double', def: 2),
      _S(['leveling', 'mf565AwayXPPerMinute'], 'Away XP per minute (empty: a quarter of active time)', kind: 'double', def: 0.5),
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
      _S(['mf565LogOnThisDay'], 'Show On This Day on the Log page', kind: 'bool', def: true, help: 'It stays in Extras either way.'),
      _S(['v192Dashboard', 'showRatingQueue'], 'Show Rate Your Library', kind: 'bool', def: true),
      _S(['v192Dashboard', 'showMissingCovers'], 'Show Missing Covers', kind: 'bool', def: true),
      _S(['v192Dashboard', 'showStopwatch'], 'Show Stopwatch', kind: 'bool', def: true),
      _S(['v508Panels', 'todayBalance', 'metrics'], "Today's Balance totals", kind: 'choice', def: 'all', choices: [('all', 'All categories'), ('visible', 'Only shown categories')]),
    ]
  ),
];

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.account});
  final AccountController account;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // 7.0.0: search every setting (both tabs).
  final _search = TextEditingController();
  bool _searching = false;

  AccountController get account => widget.account;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _close() => setState(() {
        _searching = false;
        _search.clear();
      });

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: _searching
              ? TextField(
                  controller: _search,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  decoration: const InputDecoration(hintText: 'Search settings', border: InputBorder.none),
                  onChanged: (_) => setState(() {}),
                )
              : const Text('Settings'),
          actions: [
            IconButton(
              tooltip: _searching ? 'Close search' : 'Search settings',
              icon: Icon(_searching ? Icons.close_rounded : Icons.search_rounded),
              onPressed: _searching ? _close : () => setState(() => _searching = true),
            ),
            SyncIndicator(account: account),
          ],
          bottom: const TabBar(tabs: [Tab(text: 'Account'), Tab(text: 'App')]),
        ),
        body: SettingsSearch(
          query: _searching ? _search.text : '',
          child: TabBarView(children: [
            _AccountSettings(account: account),
            _AppSettings(account: account),
          ]),
        ),
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
            Builder(builder: (context) {
              // Search: a card whose name matches shows every row; otherwise
              // only the rows that match.
              final q = SettingsSearch.of(context);
              final all = q.isEmpty || SettingsSearch.matches(q, sec.$1);
              final rows = [for (final s in sec.$3) if (all || SettingsSearch.matches(q, '${s.label} ${s.help}')) s];
              return SectionCard(
                prefKey: 'settings.${sec.$1}',
                initiallyOpen: false,
                icon: sec.$2,
                title: sec.$1,
                keywords: [for (final s in sec.$3) '${s.label} ${s.help}'].join(' '),
                child: Column(children: [for (final s in rows) _row(context, state, s)]),
              );
            }),
          SectionCard(
            prefKey: 'settings.categories',
            initiallyOpen: false,
            icon: Icons.category_rounded,
            title: 'Categories',
            subtitle: 'Enable, rename, targets and units',
            child: _CategoriesEditor(account: account, view: view),
          ),
          SectionCard(
            prefKey: 'settings.titleNames',
            initiallyOpen: false,
            icon: Icons.translate_rounded,
            title: 'Title names',
            subtitle: 'Which language each title is shown in',
            child: _TitleNamesEditor(account: account, view: view),
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
            prefKey: 'settings.panels',
            initiallyOpen: false,
            icon: Icons.view_list_rounded,
            title: "Today's Balance & Library Overview",
            subtitle: 'Which categories each panel shows, and in what order',
            child: Column(children: [
              _PanelEditor(account: account, view: view, keyName: 'todayBalance'),
              const Divider(),
              _PanelEditor(account: account, view: view, keyName: 'libraryOverview'),
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
          SectionCard(
            prefKey: 'settings.categoryClasses',
            initiallyOpen: false,
            icon: Icons.account_tree_rounded,
            title: 'Category Classes',
            subtitle: 'Hierarchical recommendations: Class → Category → Title',
            child: _ClassesEditor(account: account, view: view),
          ),
          SectionCard(
            prefKey: 'settings.choiceLayout',
            initiallyOpen: false,
            icon: Icons.swap_vert_rounded,
            title: 'Choice & filter layout',
            subtitle: 'Order and hide the choices in Set Category / Status / Priority and the Library filters',
            child: _ChoiceLayoutEditor(account: account, view: view),
          ),
          SectionCard(
            prefKey: 'settings.dataCloud',
            initiallyOpen: false,
            icon: Icons.cloud_sync_rounded,
            title: 'Data & Cloud',
            subtitle: 'Backups, Settings Presets, imports and exports',
            child: DataCloudSection(account: account, view: view),
          ),
          SectionCard(
            prefKey: 'settings.apiProviders',
            initiallyOpen: false,
            icon: Icons.hub_rounded,
            title: 'API Providers & Testing',
            subtitle: 'Cover and metadata sources, and testing them',
            child: ApiProvidersSection(account: account, view: view),
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

/// Settings for Today's Balance / Library Overview (website v508 panels):
/// shown or hidden, where the categories come from, and a custom list with
/// show/hide and order.
class _PanelEditor extends StatelessWidget {
  const _PanelEditor({required this.account, required this.view, required this.keyName});
  final AccountController account;
  final AccountView view;
  final String keyName;

  bool get _overview => keyName == 'libraryOverview';

  Future<void> _apply(BuildContext context, {bool? enabled, String? source, ({String id, bool show})? category, bool? showAll, ({String id, int position})? move, String? metrics}) async {
    final r = editPanel(view.state, keyName, DateTime.now().millisecondsSinceEpoch,
        enabled: enabled, source: source, category: category, showAll: showAll, move: move, metrics: metrics);
    if (r.message != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(r.message!)));
      return;
    }
    final panels = r.panels;
    if (panels == null) return;
    await account.setSetting(['v508Panels'], panels);
    // Older visibility switches stay in step (mf508Persist).
    await account.setSetting(['v192Dashboard', 'showTodayBalance'], (panels['todayBalance'] as Map)['enabled']);
    await account.setSetting(['v183LibraryOverview', 'showOverview'], (panels['libraryOverview'] as Map)['enabled']);
  }

  @override
  Widget build(BuildContext context) {
    final panel = balancePanel(view.state, keyName);
    final source = jsStr(panel['source']);
    final custom = source == 'custom';
    final hidden = asList(panel['hiddenIds']).map(jsStr).toSet();
    final order = [for (final id in asList(panel['order']).map(jsStr)) view.category(id)];
    final linked = _overview ? 'todayBalance' : 'libraryOverview';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(_overview ? 'Show Library Overview (in Extras)' : "Show Today's Balance"),
        value: panel['enabled'] != false,
        onChanged: (v) => _apply(context, enabled: v),
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Category source'),
        trailing: CompactDropdown<String>(
          value: source,
          items: [
            ('categories', 'Follow Categories (default)'),
            ('system', 'Follow MediaFlow System rotation'),
            ('custom', 'Custom visibility & order'),
            (linked, _overview ? "Follow Today's Balance" : 'Follow Library Overview'),
          ],
          onChanged: (v) => _apply(context, source: v),
        ),
      ),
      if (!_overview)
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Balance health totals'),
          trailing: CompactDropdown<String>(
            value: jsStr(panel['metrics']),
            items: const [('all', 'All categories'), ('visible', 'Only shown categories')],
            onChanged: (v) => _apply(context, metrics: v),
          ),
        ),
      if (_overview)
        ListenableBuilder(
          listenable: AppPrefs.instance,
          builder: (context, _) {
            final perPage = AppPrefs.instance.get<int>('overviewPerPage', 15);
            return ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Rows per page'),
              subtitle: const Text('This device'),
              trailing: CompactDropdown<int>(
                value: const [5, 10, 15, 25, 50, 100].contains(perPage) ? perPage : 15,
                items: [for (final n in const [5, 10, 15, 25, 50, 100]) (n, '$n')],
                onChanged: (v) => AppPrefs.instance.set('overviewPerPage', v),
              ),
            );
          },
        ),
      if (custom) ...[
        Row(children: [
          TextButton(onPressed: () => _apply(context, showAll: true), child: const Text('Show all')),
          TextButton(onPressed: () => _apply(context, showAll: false), child: const Text('Hide all')),
        ]),
        for (final (i, c) in order.indexed)
          Row(children: [
            Checkbox(value: !hidden.contains(c.id), onChanged: (v) => _apply(context, category: (id: c.id, show: v == true))),
            CategoryBadge(c, size: 26),
            const SizedBox(width: 8),
            Expanded(child: Text(c.name, overflow: TextOverflow.ellipsis)),
            IconButton(
              tooltip: 'Move up',
              icon: const Icon(Icons.arrow_upward_rounded, size: 18),
              onPressed: i == 0 ? null : () => _apply(context, move: (id: c.id, position: i - 1)),
            ),
            IconButton(
              tooltip: 'Move down',
              icon: const Icon(Icons.arrow_downward_rounded, size: 18),
              onPressed: i == order.length - 1 ? null : () => _apply(context, move: (id: c.id, position: i + 1)),
            ),
          ]),
      ],
    ]);
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

  Future<void> _move(String id, int to) => account.edit((s, now) => moveCategory(s, id, to), label: 'Reorder categories');

  @override
  Widget build(BuildContext context) {
    final cats = view.categories;
    final deleted = lastDeletedCategory(view.state);
    final missing = missingDefaultCategories(view.state).length;
    void toast(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Drag ⠿ or use the arrows to change the order every page shows categories in.', style: TextStyle(color: MF.textDim, fontSize: 12)),
      ReorderableListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        buildDefaultDragHandles: false,
        itemCount: cats.length,
        onReorderItem: (from, to) => _move(cats[from].id, to),
        itemBuilder: (context, i) {
          final c = cats[i];
          return Row(key: ValueKey(c.id), children: [
            ReorderableDragStartListener(index: i, child: Padding(padding: const EdgeInsets.all(6), child: Icon(Icons.drag_indicator_rounded, color: MF.textDim))),
            CategoryBadge(c, size: 30),
            const SizedBox(width: 10),
            Expanded(
              child: InkWell(
                onTap: () => openCategoryEditor(context, account, c),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(c.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                    Text('${fmtNumber(c.target ?? 1)} ${unitLabel(c.unit, c.target ?? 1)} per task · ${fmtNumber(c.minutesPerUnit)} min each',
                        style: TextStyle(color: MF.textDim, fontSize: 12)),
                  ]),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Move up',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.arrow_upward_rounded, size: 18),
              onPressed: i == 0 ? null : () => _move(c.id, i - 1),
            ),
            IconButton(
              tooltip: 'Move down',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.arrow_downward_rounded, size: 18),
              onPressed: i == cats.length - 1 ? null : () => _move(c.id, i + 1),
            ),
            Switch(
              value: c.enabled,
              onChanged: (v) => account.edit((s, now) {
                for (final x in asList(s['categories'])) {
                  if (jsStr(asMap(x)?['id']) == c.id) asMap(x)!['enabled'] = v;
                }
              }, label: v ? 'Enable category' : 'Disable category'),
            ),
          ]);
        },
      ),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        OutlinedButton.icon(onPressed: () => openCategoryEditor(context, account, null), icon: const Icon(Icons.add_rounded), label: const Text('Add category')),
        if (deleted != null)
          OutlinedButton.icon(
            onPressed: () async {
              String msg = '';
              await account.edit((s, now) => msg = restoreDeletedCategory(s, now), label: 'Restore category');
              toast(msg);
            },
            icon: const Icon(Icons.restore_rounded),
            label: Text('Restore ${jsStr(deleted['name']).isEmpty ? 'deleted category' : jsStr(deleted['name'])}'),
          ),
        if (missing > 0)
          OutlinedButton.icon(
            onPressed: () async {
              String msg = '';
              await account.edit((s, now) => msg = restoreDefaultCategories(s), label: 'Restore default categories');
              toast(msg);
            },
            icon: const Icon(Icons.settings_backup_restore_rounded),
            label: Text('Restore default categories ($missing missing)'),
          ),
      ]),
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
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.view_carousel_outlined),
                title: const Text('Navigation'),
                subtitle: const Text('Phone dock pages, the order of More and the desktop sidebar (saved to your account)'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => openNavigationSettings(context, account),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Remember Library layout and filters'),
                value: prefs.get<bool>('rememberLibraryUi', true),
                onChanged: (v) => prefs.set('rememberLibraryUi', v),
              ),
              // 7.0.0: external ratings on titles (hidden by default).
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Show external ratings on titles'),
                subtitle: const Text('MyAnimeList, IMDb and the other saved ratings, on Library titles and the recommended title.'),
                value: prefs.get<bool>(kShowExternalRatingsPref, false),
                onChanged: (v) => prefs.set(kShowExternalRatingsPref, v),
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
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              ListTile(
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
              OfflineCoversEditor(account: account),
            ]),
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
                const Divider(),
                // v565: crashes and freezes recorded on this device.
                Text('Crash and freeze log: ${Diagnostics.instance.entries.length} entr${Diagnostics.instance.entries.length == 1 ? 'y' : 'ies'}',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const Text('Kept on this device only. Copy it to send it if something keeps going wrong.', style: TextStyle(fontSize: 12)),
                Wrap(spacing: 8, children: [
                  TextButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: Diagnostics.instance.asText()));
                      _toast(context, 'Crash and freeze log copied');
                    },
                    icon: const Icon(Icons.content_copy_rounded, size: 18),
                    label: const Text('Copy log'),
                  ),
                  TextButton.icon(
                    onPressed: () async {
                      await Diagnostics.instance.clear();
                      if (context.mounted) _toast(context, 'Log cleared');
                    },
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    label: const Text('Clear log'),
                  ),
                ]),
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

/// v565 Title names (website mf565NamesSettingsHtml): settings.mf565TitleNames
/// = {global, categories}. A title's own choice (in its editor) overrides both.
class _TitleNamesEditor extends StatelessWidget {
  const _TitleNamesEditor({required this.account, required this.view});
  final AccountController account;
  final AccountView view;

  Future<void> _set(String categoryId, String value) async {
    final p = namePrefs(asMap(view.state['settings']));
    var global = p.global;
    final cats = Map<String, String>.of(p.categories);
    if (categoryId.isEmpty) {
      if (kTitleLanguageCodes.contains(value)) global = value;
    } else if (value.isNotEmpty && kTitleLanguageCodes.contains(value)) {
      cats[categoryId] = value;
    } else {
      cats.remove(categoryId);
    }
    await account.setSetting(['mf565TitleNames'], <String, dynamic>{'global': global, 'categories': cats});
  }

  @override
  Widget build(BuildContext context) {
    final p = namePrefs(asMap(view.state['settings']));
    final items = [for (final l in kTitleLanguages) DropdownMenuItem(value: l.$1, child: Text(l.$2))];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Used everywhere a title name appears. If a title has no name in this language, its main title is shown. '
          'Names come from Details Recovery or the title editor.',
          style: TextStyle(color: MF.textDim, fontSize: 12)),
      const SizedBox(height: 10),
      DropdownButtonFormField<String>(
        initialValue: p.global,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Show titles in'),
        items: items,
        onChanged: (v) => v == null ? null : _set('', v),
      ),
      const SizedBox(height: 14),
      const Text('Per category', style: TextStyle(fontWeight: FontWeight.w800)),
      Text('Overrides the setting above for one category.', style: TextStyle(color: MF.textDim, fontSize: 12)),
      for (final c in view.categories.where((c) => c.enabled))
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: DropdownButtonFormField<String>(
            initialValue: p.categories[c.id] ?? '',
            isExpanded: true,
            decoration: InputDecoration(labelText: c.name, isDense: true),
            items: [const DropdownMenuItem(value: '', child: Text('Same as above')), ...items],
            onChanged: (v) => _set(c.id, v ?? ''),
          ),
        ),
    ]);
  }
}

/// v480 Category Classes (website mf480 panel): settings.v480CategoryClasses.
class _ClassesEditor extends StatelessWidget {
  const _ClassesEditor({required this.account, required this.view});
  final AccountController account;
  final AccountView view;

  Map<String, dynamic> get _prefs =>
      cleanCategoryClasses(asMap(view.state['settings'])?['v480CategoryClasses'], view.categories.map((c) => c.id));

  Future<void> _write(Map<String, dynamic> next) =>
      account.setSetting(['v480CategoryClasses'], cleanCategoryClasses(next, view.categories.map((c) => c.id)));

  Future<void> _editClass(BuildContext context, Map<String, dynamic>? existing) => openClassEditor(context, account, existing);

  @override
  Widget build(BuildContext context) {
    final p = _prefs;
    final on = p['enabled'] == true;
    final classes = [for (final g in asList(p['classes'])) asMap(g)!];
    final byId = {for (final c in view.categories) c.id: c};
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: on,
        onChanged: (v) => _write({...p, 'enabled': v}),
        title: const Text('Enable Category Classes'),
        subtitle: const Text('Off by default. Class → Category → Title when enabled.'),
      ),
      DropdownButtonFormField<String>(
        initialValue: jsStr(p['strength']),
        decoration: const InputDecoration(labelText: 'Class balancing strength'),
        items: [for (final x in kClassStrengths) DropdownMenuItem(value: x.$1, child: Text(x.$2))],
        onChanged: on ? (v) => _write({...p, 'strength': v}) : null,
      ),
      for (final t in kClassToggles)
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: p[t.$1] == true,
          onChanged: on ? (v) => _write({...p, t.$1: v == true}) : null,
          title: Text(t.$2),
          subtitle: Text(t.$3),
        ),
      const Divider(),
      Row(children: [
        Expanded(
          child: Text('Manage Classes · ${classes.length} saved', style: const TextStyle(fontWeight: FontWeight.w800)),
        ),
        FilledButton.tonalIcon(onPressed: () => _editClass(context, null), icon: const Icon(Icons.add_rounded), label: const Text('New Class')),
      ]),
      if (classes.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text('No classes yet. Create an Anime, Television, Reading or other class and assign existing categories. '
              'Categories not in a class remain eligible.', style: TextStyle(color: MF.textDim, fontSize: 12)),
        ),
      for (final g in classes)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: classBadge(g, size: 36),
          title: Text(jsStr(g['name'])),
          subtitle: Text('Weight ${jsNum(g['weight']).round()} · ${g['enabled'] == false ? 'Disabled' : 'Enabled'} · '
              '${[for (final c in asList(g['categoryIds'])) byId[jsStr(c)]?.name ?? ''].where((n) => n.isNotEmpty).join(', ')}'),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(tooltip: 'Edit', icon: const Icon(Icons.edit_rounded), onPressed: () => _editClass(context, g)),
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (d) => AlertDialog(
                    title: const Text('Delete Category Class?'),
                    content: Text('${jsStr(g['name'])} will be removed. Its ${asList(g['categoryIds']).length} categories stay as they are.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
                      FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Delete')),
                    ],
                  ),
                );
                if (ok == true) await _write({...p, 'classes': [for (final x in classes) if (x['id'] != g['id']) x]});
              },
            ),
          ]),
        ),
      Text('Each category belongs to at most one class. Disabled categories are never recommended. '
          'No Library titles, History or XP data are rewritten.', style: TextStyle(color: MF.textDim, fontSize: 12)),
    ]);
  }
}

/// v230 Choice & filter layout (website 164-v230-choice-filter-layout.js).
class _ChoiceLayoutEditor extends StatefulWidget {
  const _ChoiceLayoutEditor({required this.account, required this.view});
  final AccountController account;
  final AccountView view;

  @override
  State<_ChoiceLayoutEditor> createState() => _ChoiceLayoutEditorState();
}

class _ChoiceLayoutEditorState extends State<_ChoiceLayoutEditor> {
  String _surface = 'setCategory';

  static const _labels = {
    'planned': 'Planned', 'active': 'In progress', 'paused': 'Paused', 'completed': 'Completed', 'dropped': 'Dropped',
    'low': 'Low', 'medium': 'Medium', 'high': 'High',
  };

  List<String> get _cats => [for (final c in widget.view.categories) c.id];

  String _label(String id) {
    if (_labels[id] != null && !_cats.contains(id)) return _labels[id]!;
    final c = widget.view.categories.where((c) => c.id == id).firstOrNull;
    return c == null ? id : '${c.name}${c.enabled ? '' : ' (Disabled)'}';
  }

  Future<void> _save(String source, List<String> order, List<String> hidden) => widget.account.setSetting(
        ['v230ChoiceLayout'],
        withSurface(asMap(widget.view.state['settings']), _surface, source, order, hidden, _cats, DateTime.now().millisecondsSinceEpoch),
      );

  @override
  Widget build(BuildContext context) {
    final settings = asMap(widget.view.state['settings']);
    final cur = normalizeSurface(asMap(settings?['v230ChoiceLayout'])?[_surface], _surface, _cats);
    final shown = visibleChoices(settings, _surface, choiceCategories(widget.view));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      DropdownButtonFormField<String>(
        initialValue: _surface,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Choice list'),
        items: [for (final x in kChoiceSurfaces) DropdownMenuItem(value: x.$1, child: Text(x.$2))],
        onChanged: (v) => setState(() => _surface = v ?? _surface),
      ),
      const SizedBox(height: 10),
      DropdownButtonFormField<String>(
        key: ValueKey('src-$_surface'),
        initialValue: cur.source,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Follow'),
        items: [for (final x in choiceSources(_surface)) DropdownMenuItem(value: x.$1, child: Text(x.$2))],
        onChanged: (v) => _save(v ?? 'custom', cur.order, cur.hidden),
      ),
      const SizedBox(height: 8),
      if (cur.source != 'custom') ...[
        Text('Shown: ${shown.map(_label).join(' · ')}', style: TextStyle(color: MF.textDim, fontSize: 12)),
      ] else
        for (var i = 0; i < cur.order.length; i++)
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: IconButton(
              tooltip: cur.hidden.contains(cur.order[i]) ? 'Show' : 'Hide',
              icon: Icon(cur.hidden.contains(cur.order[i]) ? Icons.visibility_off_rounded : Icons.visibility_rounded),
              onPressed: () {
                final id = cur.order[i];
                final hidden = [...cur.hidden];
                hidden.contains(id) ? hidden.remove(id) : hidden.add(id);
                _save('custom', cur.order, hidden);
              },
            ),
            title: Row(children: [
              if (widget.view.categories.where((c) => c.id == cur.order[i]).firstOrNull case final c?) ...[
                CategoryBadge(c, size: 24),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(_label(cur.order[i]), style: TextStyle(color: cur.hidden.contains(cur.order[i]) ? MF.textDim : null)),
              ),
            ]),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                tooltip: 'Move up',
                icon: const Icon(Icons.arrow_upward_rounded, size: 18),
                onPressed: i == 0 ? null : () => _save('custom', [...cur.order]..insert(i - 1, cur.order[i])..removeAt(i + 1), cur.hidden),
              ),
              IconButton(
                tooltip: 'Move down',
                icon: const Icon(Icons.arrow_downward_rounded, size: 18),
                onPressed: i == cur.order.length - 1
                    ? null
                    : () => _save('custom', [...cur.order]..insert(i + 2, cur.order[i])..removeAt(i), cur.hidden),
              ),
            ]),
          ),
    ]);
  }
}
