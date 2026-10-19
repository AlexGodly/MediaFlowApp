import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../data/mediaflow_library_repository.dart';
import '../../data/mediaflow_models.dart';
import '../../design_system/mediaflow_theme.dart';
import '../../design_system/mediaflow_components.dart';

enum WebsiteWorkspaceKind { oldSystem, recovery, freshReleases }

/// Website-style native workspaces that use the account's actual decoded
/// cloud Library. Never impersonates recovery/fresh-episode provider results.
class NativeWebsiteCatalogWorkspace extends StatefulWidget {
  const NativeWebsiteCatalogWorkspace({
    super.key, required this.repository, required this.kind,
  });
  final MediaFlowLibraryRepository repository;
  final WebsiteWorkspaceKind kind;
  @override
  State<NativeWebsiteCatalogWorkspace> createState() =>
      _NativeWebsiteCatalogWorkspaceState();
}

class _NativeWebsiteCatalogWorkspaceState
    extends State<NativeWebsiteCatalogWorkspace> {
  late Future<MediaFlowCatalog> future;
  String query = '';
  bool onlyMissing = true;
  int page = 0;
  static const count = 25;

  @override
  void initState() { super.initState(); future = widget.repository.load(); }
  void refresh() => setState(() {
    future = widget.repository.reload(); page = 0;
  });

  Widget panel(String label, Widget child, {String? description}) =>
      MfPanel(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: Theme.of(context).textTheme.titleLarge),
          if (description != null) ...[
            const SizedBox(height: 5),
            Text(description, style: Theme.of(context).textTheme.bodySmall),
          ],
          const SizedBox(height: 12),
          child,
        ]));

  Widget summary(String value, String label, IconData icon) => SizedBox(
    width: 170,
    child: MfPanel(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: MediaFlowTokens.of(context).accent),
        const SizedBox(height: 8),
        Text(value, style: Theme.of(context).textTheme.headlineMedium),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ])));

  Widget cover(MediaFlowTitle title) {
    final uri = Uri.tryParse(title.coverUrl);
    final trusted = uri != null && uri.scheme == 'https' &&
        uri.host.isNotEmpty && uri.userInfo.isEmpty;
    Widget fallback() => const Icon(Icons.auto_stories_outlined);
    return ClipRRect(borderRadius: BorderRadius.circular(8),
      child: SizedBox(width: 46, height: 65,
        child: ColoredBox(color: MediaFlowTokens.of(context).raised,
          child: trusted ? Image.network(title.coverUrl, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => fallback()) : fallback())));
  }

  Widget search() => TextField(
    decoration: const InputDecoration(
      labelText: 'Search Library', prefixIcon: Icon(Icons.search)),
    onChanged: (text) => setState(() {
      query = text.trim().toLowerCase(); page = 0;
    }));

  Widget pager(int length) {
    final total = ((length + count - 1) ~/ count).clamp(1, 999999).toInt();
    final current = page.clamp(0, total - 1).toInt();
    if (total <= 1) return const SizedBox.shrink();
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(icon: const Icon(Icons.chevron_left),
          tooltip: 'Previous page',
          onPressed: current == 0 ? null :
              () => setState(() => page = current - 1)),
        Text('Page ' + (current + 1).toString() +
            ' / ' + total.toString()),
        IconButton(icon: const Icon(Icons.chevron_right),
          tooltip: 'Next page',
          onPressed: current == total - 1 ? null :
              () => setState(() => page = current + 1)),
      ]);
  }

  Widget header(String title, String description) => MfPageHeader(
    title: title, subtitle: description,
    trailing: IconButton(
      onPressed: refresh, tooltip: 'Refresh from cloud',
      icon: const Icon(Icons.refresh)));

  Widget oldSystem(MediaFlowCatalog data) {
    final consumed = data.library.fold<double>(0,
        (sum, t) => sum + t.progress);
    final minutes = data.sessions.fold<double>(0,
        (sum, s) => sum + s.minutes);
    return ListView(children: [
      header('Old System', 'Original category overview from your cloud'),
      const SizedBox(height: 14),
      Wrap(spacing: 10, runSpacing: 10, children: [
        summary(data.categories.length.toString(), 'Categories',
          Icons.category_outlined),
        summary(data.library.length.toString(), 'Library titles',
          Icons.local_library_outlined),
        summary(consumed.floor().toString(), 'Progress units',
          Icons.playlist_add_check),
        summary(minutes.floor().toString(), 'Logged minutes',
          Icons.timer_outlined),
      ]),
      const SizedBox(height: 14),
      panel('Category balance', Column(children: [
        for (final cat in data.categories) ...[
          Builder(builder: (context) {
            final items = data.library.where(
              (t) => t.categoryId == cat.id).toList();
            final done = items.where(
              (t) => t.status == 'completed').length;
            final logs = data.sessions.where(
              (s) => s.categoryId == cat.id).length;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(children: [
                Text(cat.icon, style: const TextStyle(fontSize: 21)),
                const SizedBox(width: 10),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(cat.name),
                    const SizedBox(height: 5),
                    LinearProgressIndicator(value: items.isEmpty ? 0
                      : done / items.length, minHeight: 5),
                  ])),
                const SizedBox(width: 10),
                Column(crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(done.toString() + ' / ' + items.length.toString()),
                    Text(logs.toString() + ' logs',
                      style: Theme.of(context).textTheme.bodySmall),
                  ]),
              ]),
            );
          }),
          const Divider(height: 1),
        ],
      ]), description: 'Cloud-derived category consumption and progress.'),
    ]);
  }

  bool missing(MediaFlowTitle t) {
    final uri = Uri.tryParse(t.coverUrl);
    return uri == null || uri.host.isEmpty ||
        (uri.scheme != 'http' && uri.scheme != 'https');
  }

  Widget recovery(MediaFlowCatalog data) {
    final allMissing = data.library.where(missing).length;
    final noIds = data.library.where((t) =>
        t.externalIds.isEmpty).length;
    final found = data.library.where((t) =>
        (!onlyMissing || missing(t)) &&
        (query.isEmpty || t.searchText.contains(query))).toList();
    final pages = ((found.length + count - 1) ~/ count).clamp(1, 999999);
    final current = page.clamp(0, pages - 1).toInt();
    return ListView(children: [
      header('Background Processes', 'Missing cover and metadata diagnostics'),
      const SizedBox(height: 12),
      Wrap(spacing: 10, runSpacing: 10, children: [
        summary(allMissing.toString(), 'Missing covers',
          Icons.broken_image_outlined),
        summary(noIds.toString(), 'Missing external IDs',
          Icons.fingerprint),
        summary(data.library.length.toString(), 'Library titles',
          Icons.local_library),
      ]),
      const SizedBox(height: 12),
      panel('Library cover recovery', Column(children: [
        search(),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Missing covers only'),
          value: onlyMissing,
          onChanged: (value) => setState(() {
            onlyMissing = value; page = 0;
          })),
        for (final t in found.skip(current * count).take(count))
          ListTile(
            contentPadding: EdgeInsets.zero, dense: true,
            leading: cover(t),
            title: Text(t.title, maxLines: 2,
              overflow: TextOverflow.ellipsis),
            subtitle: Text(data.categoryById[t.categoryId]?.name
              ?? 'Library'),
            trailing: Icon(missing(t)
              ? Icons.image_not_supported_outlined
              : Icons.check_circle_outline, size: 19)),
        if (found.isEmpty) const Padding(
          padding: EdgeInsets.all(20),
          child: Text('No matching titles.')),
        pager(found.length),
      ]), description: 'A real, read-only scan. Cover/metadata provider '
        'recovery has not yet been ported to Flutter.'),
      const SizedBox(height: 10),
      OutlinedButton.icon(
        onPressed: () {
          Clipboard.setData(ClipboardData(text:
            'MediaFlow native recovery summary\n' +
            'Library: ' + data.library.length.toString() + '\n' +
            'Missing covers: ' + allMissing.toString() + '\n' +
            'Titles missing external IDs: ' + noIds.toString()));
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Diagnostic summary copied.')));
        },
        icon: const Icon(Icons.copy_outlined),
        label: const Text('Copy diagnostics')),
    ]);
  }

  Widget freshReleases(MediaFlowCatalog data) {
    final found = data.library.where((t) =>
      (t.status == 'active' || t.status == 'planned') &&
      (t.total == null || t.total! <= 0 || t.progress < t.total!) &&
      (query.isEmpty || t.searchText.contains(query))).toList();
    final pages = ((found.length + count - 1) ~/ count).clamp(1, 999999);
    final current = page.clamp(0, pages - 1).toInt();
    return ListView(children: [
      header('Fresh Episodes', 'Your unfinished Library titles'),
      const SizedBox(height: 12),
      panel('Fresh release candidates', Column(children: [
        const MfBadge(label: 'Unverified candidates',
          icon: Icons.info_outline),
        const SizedBox(height: 10),
        const Text('These titles may have future units. The website Smart '
            'Fresh Episodes Engine and its providers are not yet active '
            'in Flutter, so no release date or fresh-episode count '
            'is being claimed.'),
        const SizedBox(height: 12),
        search(),
        const SizedBox(height: 10),
        for (final t in found.skip(current * count).take(count))
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: cover(t),
            title: Text(t.title, maxLines: 2,
              overflow: TextOverflow.ellipsis),
            subtitle: Text(
              (data.categoryById[t.categoryId]?.name ?? 'Library') +
              ' · ' + t.progress.floor().toString() +
              ' / ' + (t.total?.floor().toString() ?? '?')),
            trailing: const Icon(Icons.schedule_outlined)),
        if (found.isEmpty) const Padding(
          padding: EdgeInsets.all(20),
          child: Text('No candidates found.')),
        pager(found.length),
      ]), description: found.length.toString() +
        ' title candidates, based on your signed-in Library.'),
    ]);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<MediaFlowCatalog>(
    future: future,
    builder: (context, snap) {
      if (snap.hasError) return MfEmptyState(
        icon: Icons.cloud_off,
        title: 'Cloud is unavailable',
        message: 'No empty account or fabricated data was created.',
        action: OutlinedButton(onPressed: refresh,
          child: const Text('Retry')));
      if (!snap.hasData) return const Center(
        child: CircularProgressIndicator());
      return switch (widget.kind) {
        WebsiteWorkspaceKind.oldSystem => oldSystem(snap.data!),
        WebsiteWorkspaceKind.recovery => recovery(snap.data!),
        WebsiteWorkspaceKind.freshReleases => freshReleases(snap.data!),
      };
    });
}

class NativeWebsiteThemeScreen extends StatelessWidget {
  const NativeWebsiteThemeScreen({
    super.key, required this.appearance, required this.onChanged,
  });
  final MediaFlowAppearance appearance;
  final ValueChanged<MediaFlowAppearance> onChanged;
  @override
  Widget build(BuildContext context) {
    final tokens = MediaFlowTokens.of(context);
    return ListView(children: [
      const MfPageHeader(title: 'Theme Studio',
        subtitle: 'Native appearance · website-inspired surfaces'),
      const SizedBox(height: 14),
      MfPanel(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Appearance', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Wrap(spacing: 10, runSpacing: 10, children: [
            for (final value in MediaFlowAppearance.values)
              ChoiceChip(
                selected: appearance == value,
                label: Text(value.name.toUpperCase()),
                avatar: Icon(switch (value) {
                  MediaFlowAppearance.dark => Icons.dark_mode_outlined,
                  MediaFlowAppearance.light => Icons.light_mode_outlined,
                  MediaFlowAppearance.amoled => Icons.contrast_outlined,
                }, size: 17),
                onSelected: (_) => onChanged(value)),
          ]),
          const SizedBox(height: 17),
          Wrap(spacing: 9, children: [
            for (final color in [
              tokens.background, tokens.panel, tokens.raised,
              tokens.border, tokens.accent, tokens.healthy, tokens.due,
            ])
              Container(width: 45, height: 45, decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(8),
                border: Border.all(color: tokens.border))),
          ]),
        ])),
      const SizedBox(height: 14),
      const MfPanel(child: Text(
        'The website’s Legacy, Advanced Cover Intelligence, Custom Theme '
        'Studio and Living Themes engines are not yet native. '
        'Dark, Light and AMOLED changes above are real and apply to this app.')),
    ]);
  }
}

class NativeWebsiteAboutScreen extends StatelessWidget {
  const NativeWebsiteAboutScreen({super.key});
  @override
  Widget build(BuildContext context) => ListView(children: [
    const MfPageHeader(title: 'About MediaFlow',
      subtitle: 'Designed by Alex Godly'),
    const SizedBox(height: 12),
    MfPanel(child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.auto_stories_outlined, size: 45),
        const SizedBox(height: 9),
        Text('MediaFlow',
          style: Theme.of(context).textTheme.headlineLarge),
        const SizedBox(height: 8),
        const Text('Personal media manager for anime, TV, movies, manga, '
            'books, comics and other categories.'),
        const SizedBox(height: 14),
        const MfBadge(label: 'Flutter native · no WebView',
          icon: Icons.devices_outlined),
        const SizedBox(height: 10),
        const Text('Website reference: MediaFlow v507.'),
        const SizedBox(height: 8),
        const Text('Existing cloud Library, Logging drafts, History, '
          'Collections, Personal Order, Statistics, Account, and Settings '
          'use native screens. Website-only cloud writes, recovery engines '
          'and advanced theme effects require separate parity validation.'),
      ])),
  ]);
}
