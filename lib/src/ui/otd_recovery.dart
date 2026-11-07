// On This Day: recover covers and details for today's titles in one tap
// (website v555 `mf555RecoverOnThisDay`). The website opens its recovery
// workspace for those titles; here the same titles open in one list where
// each title's cover and details can be found (title editor → online search)
// and ratings / IDs refreshed for all of them at once.

import 'dart:async';

import 'package:flutter/material.dart';

import '../data/account_controller.dart';
import '../data/ratings_refresh.dart';
import '../logic/extras.dart';
import '../state/models.dart';
import '../util/js.dart';
import 'presence.dart';
import 'theme.dart';
import 'title_screen.dart' show TitleEditor, openTitle;
import 'widgets.dart';

/// `mf555OnThisDayIds`: today's On This Day titles that are in the Library.
List<String> onThisDayLibraryIds(AccountView view, List<({int years, List<OtdEvent> rows})> groups) {
  final inLibrary = {for (final t in view.library) t.id};
  final ids = <String>[];
  for (final g in groups) {
    for (final row in g.rows) {
      final id = (row.libraryId ?? '').isNotEmpty ? row.libraryId! : jsStr(row.item?['id']);
      if (id.isNotEmpty && inLibrary.contains(id) && !ids.contains(id)) ids.add(id);
    }
  }
  return ids;
}

Future<void> showOnThisDayRecovery(BuildContext context, AccountController account, List<String> ids) {
  if (ids.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('None of today’s On This Day titles are in your Library.')));
    return Future.value();
  }
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: MF.surface,
    builder: (c) => PresenceScope(
      info: const PresenceInfo(details: 'Recovering covers and details', state: 'On This Day'),
      child: SizedBox(
      height: MediaQuery.sizeOf(c).height * 0.8,
      child: LiveBuilder(
        listenable: Listenable.merge([account, RatingsRefresh.instance]),
        builder: (c, _) => _OtdRecovery(account: account, ids: ids, outer: context),
      ),
    )),
  );
}

class _OtdRecovery extends StatefulWidget {
  const _OtdRecovery({required this.account, required this.ids, required this.outer});
  final AccountController account;
  final List<String> ids;
  final BuildContext outer;

  @override
  State<_OtdRecovery> createState() => _OtdRecoveryState();
}

class _OtdRecoveryState extends State<_OtdRecovery> {
  bool _running = false;
  String _result = '';

  Future<void> _refreshAll() async {
    setState(() {
      _running = true;
      _result = '';
    });
    final text = await RatingsRefresh.instance.refreshMany(widget.account, widget.ids);
    if (!mounted) return;
    setState(() {
      _running = false;
      _result = text;
    });
  }

  @override
  Widget build(BuildContext context) {
    final view = widget.account.view;
    final titles = [
      for (final id in widget.ids)
        if (view?.library.where((t) => t.id == id).firstOrNull case final t?) t,
    ];
    final missing = titles.where((t) => jsStr(t.raw['coverUrl']).trim().isEmpty).length;
    final r = RatingsRefresh.instance;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
        child: Row(children: [
          const Expanded(child: Text('On This Day recovery', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900))),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Text(
          '${titles.length} title${titles.length == 1 ? '' : 's'} from today · $missing without a cover. '
          'Tap a title to find its cover and details; refresh ratings and IDs for all of them at once.',
          style: TextStyle(color: MF.textDim, fontSize: 13),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
        child: Row(children: [
          FilledButton.icon(
            onPressed: _running || r.working ? null : () => unawaited(_refreshAll()),
            icon: const Icon(Icons.star_half_rounded),
            label: const Text('Refresh ratings & IDs'),
          ),
          if (_running) ...[
            const SizedBox(width: 8),
            OutlinedButton(onPressed: r.stop, child: const Text('Stop')),
          ],
        ]),
      ),
      if (_running && r.working)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(r.note, style: TextStyle(color: MF.textDim, fontSize: 12)),
        ),
      if (_result.isNotEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(_result, style: TextStyle(color: MF.good, fontSize: 12, fontWeight: FontWeight.w700)),
        ),
      const SizedBox(height: 6),
      Expanded(
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          itemCount: titles.length,
          itemBuilder: (context, i) {
            final t = titles[i];
            final cat = view!.category(t.categoryId);
            final noCover = jsStr(t.raw['coverUrl']).trim().isEmpty;
            final busy = r.titleId == t.id;
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Cover(title: t, category: cat, width: 40),
              title: Text(t.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text(
                [cat.name, if (noCover) 'No cover', if (busy) r.note].join(' · '),
                style: TextStyle(color: noCover ? MF.warn : MF.textDim, fontSize: 12),
              ),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                  tooltip: 'Find cover and details',
                  icon: const Icon(Icons.image_search_rounded),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => TitleEditor(account: widget.account, id: t.id)),
                  ),
                ),
                IconButton(
                  tooltip: 'Open',
                  icon: const Icon(Icons.chevron_right_rounded),
                  onPressed: () {
                    Navigator.pop(context);
                    if (widget.outer.mounted) openTitle(widget.outer, widget.account, t.id);
                  },
                ),
              ]),
            );
          },
        ),
      ),
    ]);
  }
}
