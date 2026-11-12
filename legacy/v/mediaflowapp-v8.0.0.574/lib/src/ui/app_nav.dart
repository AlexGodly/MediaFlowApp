// Custom navigation, saved per account (`settings.mediaflowAppNav`, synced):
// which pages sit in the phone dock (3–5, in order, More is always last),
// the order of the pages inside More, and the desktop sidebar order. Pages
// added in later versions join More (and the end of the sidebar) by default,
// and Settings can never be hidden: whatever isn't in the dock is in More.

import 'package:flutter/material.dart';

import '../data/account_controller.dart';
import '../util/js.dart';
import 'home_shell.dart' show Section;
import 'presence.dart';
import 'theme.dart';

const kAppNavKey = 'mediaflowAppNav';
const kDockMin = 3, kDockMax = 5;
const kDefaultDock = [Section.log, Section.library, Section.history, Section.extras];

class AppNav {
  AppNav._(this.dock, this.more, this.desktop);

  /// Phone dock pages (More is added after them).
  final List<Section> dock;

  /// Every other page, in the More list's order.
  final List<Section> more;

  /// Every page, in the desktop sidebar's order.
  final List<Section> desktop;

  static List<Section> _names(Object? raw) {
    final out = <Section>[];
    for (final n in asList(raw)) {
      final s = Section.values.where((s) => s.name == jsStr(n)).firstOrNull;
      if (s != null && !out.contains(s)) out.add(s);
    }
    return out;
  }

  factory AppNav.of(Map<String, dynamic>? settings) {
    final raw = asMap(settings?[kAppNavKey]) ?? const <String, dynamic>{};
    var dock = _names(raw['dock']);
    if (dock.length < kDockMin) dock = [...kDefaultDock];
    if (dock.length > kDockMax) dock = dock.take(kDockMax).toList();
    final more = [
      for (final s in _names(raw['more'])) if (!dock.contains(s)) s,
    ];
    for (final s in Section.values) {
      if (!dock.contains(s) && !more.contains(s)) more.add(s);
    }
    final desktop = _names(raw['desktop']);
    for (final s in Section.values) {
      if (!desktop.contains(s)) desktop.add(s);
    }
    return AppNav._(dock, more, desktop);
  }

  static AppNav get defaults => AppNav.of(null);

  Map<String, dynamic> toJson() => {
        'dock': [for (final s in dock) s.name],
        'more': [for (final s in more) s.name],
        'desktop': [for (final s in desktop) s.name],
      };

  /// A copy with [dock] / [more] / [desktop] replaced (then cleaned again).
  AppNav copyWith({List<Section>? dock, List<Section>? more, List<Section>? desktop}) => AppNav.of({
        kAppNavKey: AppNav._(dock ?? this.dock, more ?? this.more, desktop ?? this.desktop).toJson(),
      });
}

Future<void> openNavigationSettings(BuildContext context, AccountController account) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => NavigationSettingsScreen(account: account)));

class NavigationSettingsScreen extends StatefulWidget {
  const NavigationSettingsScreen({super.key, required this.account});
  final AccountController account;

  @override
  State<NavigationSettingsScreen> createState() => _NavigationSettingsScreenState();
}

class _NavigationSettingsScreenState extends State<NavigationSettingsScreen> {
  late AppNav _nav = AppNav.of(widget.account.view?.state['settings'] as Map<String, dynamic>?);

  void _save(AppNav next) {
    setState(() => _nav = next);
    widget.account.setSetting([kAppNavKey], next.toJson());
  }

  void _toast(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Widget _header(String title, String sub) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 2),
          Text(sub, style: TextStyle(color: MF.textDim)),
        ]),
      );

  Widget _list(List<Section> items, void Function(List<Section>) onChanged, {required Widget Function(Section s, int i) trailing}) {
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      itemCount: items.length,
      onReorderItem: (from, to) {
        final next = [...items];
        next.insert(to, next.removeAt(from));
        onChanged(next);
      },
      itemBuilder: (context, i) {
        final s = items[i];
        return ListTile(
          key: ValueKey(s),
          dense: true,
          leading: ReorderableDragStartListener(index: i, child: const Icon(Icons.drag_indicator_rounded)),
          title: Row(children: [Icon(s.icon, size: 20, color: MF.accent), const SizedBox(width: 10), Expanded(child: Text(s.label))]),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(
              tooltip: 'Move up',
              icon: const Icon(Icons.arrow_upward_rounded, size: 18),
              onPressed: i == 0 ? null : () => onChanged([...items]..insert(i - 1, items[i])..removeAt(i + 1)),
            ),
            IconButton(
              tooltip: 'Move down',
              icon: const Icon(Icons.arrow_downward_rounded, size: 18),
              onPressed: i == items.length - 1 ? null : () => onChanged([...items]..insert(i + 2, items[i])..removeAt(i)),
            ),
            trailing(s, i),
          ]),
        );
      },
    );
  }

  Widget _preview() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(color: MF.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: MF.border)),
      child: Row(children: [
        for (final s in [..._nav.dock, null])
          Expanded(
            child: Column(children: [
              Icon(s?.icon ?? Icons.menu_rounded, size: 22, color: s == _nav.dock.first ? MF.accent : MF.textDim),
              const SizedBox(height: 2),
              Text(s?.label ?? 'More', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: MF.textDim)),
            ]),
          ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final nav = _nav;
    return PresenceScope(
      info: const PresenceInfo(situation: 'settings', values: {'action': 'Arranging navigation'}),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Navigation'),
          actions: [
            TextButton(
              onPressed: () {
                _save(AppNav.defaults);
                _toast('Navigation reset');
              },
              child: const Text('Reset'),
            ),
          ],
        ),
        body: ListView(padding: const EdgeInsets.only(bottom: 48), children: [
          _header('Phone dock', 'Pick $kDockMin–$kDockMax pages for the bottom bar and their order. More is always last.'),
          _preview(),
          _list(
            nav.dock,
            (next) => _save(nav.copyWith(dock: next)),
            trailing: (s, _) => IconButton(
              tooltip: 'Move to More',
              icon: const Icon(Icons.remove_circle_outline_rounded, size: 20),
              onPressed: nav.dock.length <= kDockMin
                  ? null
                  : () => _save(nav.copyWith(dock: [...nav.dock]..remove(s), more: [s, ...nav.more])),
            ),
          ),
          _header('More', 'Everything not in the dock, in this order. New pages join More.'),
          _list(
            nav.more,
            (next) => _save(nav.copyWith(more: next)),
            trailing: (s, _) => IconButton(
              tooltip: 'Add to the dock',
              icon: const Icon(Icons.add_circle_outline_rounded, size: 20),
              onPressed: nav.dock.length >= kDockMax ? null : () => _save(nav.copyWith(dock: [...nav.dock, s], more: [...nav.more]..remove(s))),
            ),
          ),
          _header('Desktop sidebar', 'The order of the pages in the sidebar on wide screens.'),
          _list(nav.desktop, (next) => _save(nav.copyWith(desktop: next)), trailing: (_, __) => const SizedBox.shrink()),
        ]),
      ),
    );
  }
}
