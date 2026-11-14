// Settings → Storage: which covers to keep on this device for offline use.

import 'package:flutter/material.dart';

import '../logic/choice_layout.dart' show filterCategories;
import '../data/account_controller.dart';
import '../data/app_prefs.dart';
import '../data/offline_covers.dart';
import '../state/models.dart';
import 'theme.dart';
import 'widgets.dart';

class OfflineCoversEditor extends StatelessWidget {
  const OfflineCoversEditor({super.key, required this.account});
  final AccountController account;

  Future<void> _pickCategories(BuildContext context, AccountView view) async {
    final chosen = {...OfflineCovers.categories};
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, set) => AlertDialog(
          title: const Text('Categories to keep offline'),
          content: SizedBox(
            width: 420,
            child: ListView(shrinkWrap: true, children: [
              for (final c in filterCategories(view))
                CheckboxListTile(
                  value: chosen.contains(c.id),
                  onChanged: (v) => set(() => v == true ? chosen.add(c.id) : chosen.remove(c.id)),
                  secondary: CategoryBadge(c, size: 28),
                  title: Text(c.name),
                ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (ok == true) await AppPrefs.instance.set('offlineCoverCategories', chosen.toList());
  }

  Future<void> _pickTitles(BuildContext context, AccountView view) async {
    final chosen = {...OfflineCovers.titles};
    var query = '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(builder: (d, set) {
        final q = query.toLowerCase();
        final rows = [
          for (final t in view.library)
            if (t.coverUrl.startsWith('http') && (q.isEmpty || t.title.toLowerCase().contains(q))) t,
        ];
        return AlertDialog(
          title: Text('Titles to keep offline (${chosen.length})'),
          content: SizedBox(
            width: 460,
            height: 460,
            child: Column(children: [
              TextField(
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Search titles'),
                onChanged: (v) => set(() => query = v.trim()),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: rows.length,
                  itemBuilder: (_, i) => CheckboxListTile(
                    dense: true,
                    value: chosen.contains(rows[i].id),
                    onChanged: (v) => set(() => v == true ? chosen.add(rows[i].id) : chosen.remove(rows[i].id)),
                    title: Text(rows[i].title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(view.category(rows[i].categoryId).name),
                  ),
                ),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Save')),
          ],
        );
      }),
    );
    if (ok == true) await AppPrefs.instance.set('offlineCoverTitles', chosen.toList());
  }

  @override
  Widget build(BuildContext context) {
    final oc = OfflineCovers.instance;
    return LiveBuilder(
      listenable: Listenable.merge([oc, AppPrefs.instance]),
      builder: (context, _) {
        final view = account.view;
        if (view == null) return const SizedBox.shrink();
        final mode = OfflineCovers.mode;
        final count = OfflineCovers.urlsFor(view).length;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Covers for offline use'),
            subtitle: const Text('Covers you have seen are always kept. Choose more to download ahead of time; new ones are added after each sync.'),
            trailing: CompactDropdown<String>(
              value: mode,
              items: const [('shown', 'Only ones shown'), ('all', 'All titles'), ('categories', 'Chosen categories'), ('titles', 'Chosen titles')],
              onChanged: (v) => AppPrefs.instance.set('offlineCoverMode', v),
              maxWidth: 190,
            ),
          ),
          if (mode == 'categories')
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _pickCategories(context, view),
                icon: const Icon(Icons.category_outlined, size: 18),
                label: Text('${OfflineCovers.categories.length} categories chosen'),
              ),
            ),
          if (mode == 'titles')
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _pickTitles(context, view),
                icon: const Icon(Icons.checklist_rounded, size: 18),
                label: Text('${OfflineCovers.titles.length} titles chosen'),
              ),
            ),
          if (mode != 'shown')
            Row(children: [
              Expanded(
                child: Text(
                  oc.running
                      ? 'Downloading ${oc.done} / ${oc.total}${oc.failed > 0 ? ' · ${oc.failed} unavailable' : ''}'
                      : '$count cover${count == 1 ? '' : 's'} in this choice${oc.total > 0 && oc.failed > 0 ? ' · ${oc.failed} could not be downloaded' : ''}',
                  style: TextStyle(color: MF.textDim, fontSize: 12),
                ),
              ),
              oc.running
                  ? TextButton(onPressed: oc.cancel, child: const Text('Stop'))
                  : FilledButton.tonal(onPressed: () => oc.run(), child: const Text('Download now')),
            ]),
          if (oc.running) LinearProgressIndicator(value: oc.total == 0 ? null : oc.done / oc.total),
        ]);
      },
    );
  }
}
