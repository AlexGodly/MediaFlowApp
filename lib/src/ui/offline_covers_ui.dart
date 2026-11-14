// Settings → Storage: which covers to keep on this device for offline use.

import 'package:flutter/material.dart';

import '../logic/choice_layout.dart' show filterCategories;
import '../data/account_controller.dart';
import '../data/app_prefs.dart';
import '../data/offline_covers.dart';
import '../state/models.dart';
import 'theme.dart';
import 'title_picker.dart' show pickLibraryTitles;
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

  /// 10.0.0: the full title picker (search, filters, sort, views, pages,
  /// Select visible / all matches / Deselect all, "Only selected").
  Future<void> _pickTitles(BuildContext context, AccountView view) async {
    final picked = await pickLibraryTitles(context, view,
        title: 'Titles to keep offline', initial: {...OfflineCovers.titles}, confirm: 'Save', allowEmpty: true);
    if (picked != null) await AppPrefs.instance.set('offlineCoverTitles', picked);
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
