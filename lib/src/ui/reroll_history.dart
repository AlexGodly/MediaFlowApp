// The website's "Current rerolls" window (v180 `v180RerollHistoryHtml`, with the
// v301 scrolling layout): every title MediaFlow recommended for the current
// task, which ones count for Respect XP, and the current pick. Read-only apart
// from Edit, which opens the title.

import 'package:flutter/material.dart';

import '../data/account_controller.dart';
import '../logic/rec_submit.dart' show respectSlotLimit;
import '../logic/recommend.dart';
import '../state/models.dart';
import '../util/js.dart';
import 'presence.dart';
import 'theme.dart';
import 'title_screen.dart' show openTitle;
import 'widgets.dart';

/// Title rerolls so far for [task] (recommendations shown minus the first).
int titleRerollCount(Map<String, dynamic>? task) {
  final n = asList(task?['v180RecommendationHistory']).length - 1;
  return n < 0 ? 0 : n;
}

Future<void> showRerollHistory(BuildContext context, AccountController account) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: MF.surface,
    builder: (c) => PresenceScope(
      info: PresenceInfo(
        situation: 'upNext',
        values: {'rerolls': '${titleRerollCount(asMap(account.view?.state['currentTask']))}'},
      ),
      child: SizedBox(
      height: MediaQuery.sizeOf(c).height * 0.85,
      child: LiveBuilder(
        listenable: account,
        builder: (c, _) {
          final view = account.view;
          final task = asMap(view?.state['currentTask']);
          if (view == null || task == null) {
            return Center(child: Text('There is no current title-reroll history.', style: TextStyle(color: MF.textDim)));
          }
          return _RerollHistory(
            view: view,
            task: task,
            onEdit: (id) {
              Navigator.pop(c);
              if (context.mounted) openTitle(context, account, id);
            },
          );
        },
      ),
    )),
  );
}

class _RerollHistory extends StatelessWidget {
  const _RerollHistory({required this.view, required this.task, required this.onEdit});
  final AccountView view;
  final Map<String, dynamic> task;
  final ValueChanged<String> onEdit;

  @override
  Widget build(BuildContext context) {
    final r = Recommender(view.state, now: DateTime.now().millisecondsSinceEpoch);
    final history = [
      for (final h in asList(task['v180RecommendationHistory']))
        if (asMap(h) != null) asMap(h)!,
    ];
    final slotLimit = respectSlotLimit(r, task);
    final rerolls = history.isEmpty ? 0 : history.length - 1;
    final cat = view.category(jsStr(task['categoryId']));
    final perTitle =
        RegExp(r'(^|[^a-z])(movies?|films?|books?|titles?)([^a-z]|$)', caseSensitive: false).hasMatch(cat.unit.toLowerCase());
    final target = perTitle ? '$slotLimit title${slotLimit == 1 ? '' : 's'}' : '1 exact title';

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Current rerolls', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Row(children: [
                CategoryBadge(cat, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${cat.name} · $rerolls title reroll${rerolls == 1 ? '' : 's'} · '
                    '${history.length} recommendation${history.length == 1 ? '' : 's'} shown',
                    style: TextStyle(color: MF.textDim, fontSize: 13),
                  ),
                ),
              ]),
            ]),
          ),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ]),
      ),
      Container(
        margin: const EdgeInsets.fromLTRB(16, 6, 16, 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: MF.raised, borderRadius: BorderRadius.circular(14)),
        child: Text.rich(
          TextSpan(style: TextStyle(color: MF.textDim, fontSize: 13, height: 1.35), children: [
            const TextSpan(text: 'This task can earn exact-title Respect XP from the '),
            TextSpan(text: 'first $target', style: TextStyle(color: MF.text, fontWeight: FontWeight.w800)),
            const TextSpan(
              text: ' MediaFlow recommends. You can reroll as much as you want without a reroll penalty. '
                  'Extra recommendations stay available to watch, but a title shown after the task\'s Respect '
                  'slots does not retroactively replace a missed earlier recommendation.',
            ),
          ]),
        ),
      ),
      Expanded(
        child: history.isEmpty
            ? Center(child: Text('No recommendation history yet.', style: TextStyle(color: MF.textDim)))
            : Scrollbar(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  itemCount: history.length,
                  itemBuilder: (context, index) {
                    final entry = history[index];
                    final item = r.findLibraryItem(jsStr(entry['libraryId']), jsStr(entry['title']));
                    final title = cleanTitle(item?['title'] ?? entry['title']);
                    final shown = title.isEmpty ? 'Unavailable title' : title;
                    final eligible = index < slotLimit;
                    final current = jsStr(task['libraryId']) == jsStr(entry['libraryId']) && index == history.length - 1;
                    final cover = LibraryTitle(item ?? <String, dynamic>{'title': shown, 'categoryId': cat.id});
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: MF.raised,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: current ? MF.accent : MF.raised),
                      ),
                      child: Row(children: [
                        Cover(title: cover, category: cat, width: 44),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Tooltip(
                              message: shown,
                              child: Text(shown, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                            ),
                            const SizedBox(height: 6),
                            Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                              _meta('Recommendation #${index + 1}'),
                              _meta(index == 0 ? 'Initial pick' : 'Reroll #$index'),
                              _badge(eligible ? 'Respect slot ${index + 1}/$slotLimit' : 'Extra reroll', eligible ? MF.good : MF.textDim),
                              if (current) _badge('Current', MF.accent),
                            ]),
                          ]),
                        ),
                        if (item != null && jsStr(item['id']).isNotEmpty)
                          TextButton(
                            onPressed: () => onEdit(jsStr(item['id'])),
                            child: const Text('Edit'),
                          ),
                      ]),
                    );
                  },
                ),
              ),
      ),
    ]);
  }

  Widget _meta(String text) => Text(text, style: TextStyle(color: MF.textDim, fontSize: 12));

  Widget _badge(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
        child: Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800)),
      );
}
