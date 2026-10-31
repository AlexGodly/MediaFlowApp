import 'dart:io';

import 'package:flutter/material.dart';

import '../config.dart';
import '../data/account_controller.dart';
import '../data/app_prefs.dart';
import '../data/cover_cache.dart';
import '../logic/resume.dart';
import '../state/models.dart';
import '../util/js.dart';
import 'theme.dart';

String fmtNumber(num v) {
  final whole = v == v.roundToDouble();
  final s = whole ? v.round().toString() : v.toStringAsFixed(1);
  final neg = s.startsWith('-');
  final digits = neg ? s.substring(1) : s;
  final parts = digits.split('.');
  final buf = StringBuffer();
  for (var i = 0; i < parts[0].length; i++) {
    if (i > 0 && (parts[0].length - i) % 3 == 0) buf.write(',');
    buf.write(parts[0][i]);
  }
  return '${neg ? '-' : ''}$buf${parts.length > 1 ? '.${parts[1]}' : ''}';
}

String fmtMinutes(num minutes) {
  final m = minutes.round();
  if (m < 60) return '${m}m';
  final h = m ~/ 60, r = m % 60;
  return r == 0 ? '${h}h' : '${h}h ${r}m';
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String fmtDay(String iso) {
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  final base = '${_months[d.month - 1]} ${d.day}';
  return d.year == now.year ? base : '$base, ${d.year}';
}

String isoDay(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String statusLabel(String status) => switch (status) {
      'active' => 'In progress',
      'planned' => 'Planned',
      'completed' => 'Completed',
      'paused' => 'Paused',
      'dropped' => 'Dropped',
      _ => status.isEmpty ? 'Planned' : '${status[0].toUpperCase()}${status.substring(1)}',
    };

Color statusColor(String status) => switch (status) {
      'active' => MF.accent,
      'completed' => MF.good,
      'paused' => MF.textDim,
      'dropped' => MF.bad,
      _ => const Color(0xFF7FA6E8),
    };

String progressText(LibraryTitle t, Category c) {
  final p = fmtNumber(t.progress);
  final total = t.total;
  return total == null ? '$p ${unitLabel(c.unit, t.progress)}' : '$p / ${fmtNumber(total)} ${unitLabel(c.unit, total)}';
}

/// Category icon: the category's emoji (or image) on a tinted square.
class CategoryBadge extends StatelessWidget {
  const CategoryBadge(this.category, {super.key, this.size = 36});
  final Category category;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = MF.parseColor(category.color);
    Widget child;
    final iconUrl = category.iconUrl;
    if (iconUrl.isNotEmpty) {
      final url = iconUrl.startsWith('http') ? iconUrl : '$kWebsiteUrl${iconUrl.replaceFirst(RegExp(r'^\./'), '')}';
      child = Image.network(url, width: size * 0.62, height: size * 0.62,
          errorBuilder: (_, __, ___) => _emoji(color));
    } else {
      child = _emoji(color);
    }
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withAlpha(0x2E),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: child,
    );
  }

  Widget _emoji(Color color) {
    final icon = category.icon;
    if (icon.isNotEmpty && icon.runes.length <= 3) {
      return Text(icon, style: TextStyle(fontSize: size * 0.48));
    }
    return Text(category.name.isEmpty ? '?' : category.name[0],
        style: TextStyle(fontSize: size * 0.45, fontWeight: FontWeight.w800, color: color));
  }
}

/// Title cover with a category fallback.
class Cover extends StatelessWidget {
  const Cover({super.key, required this.title, required this.category, this.width = 46});
  final LibraryTitle title;
  final Category category;
  final double width;

  @override
  Widget build(BuildContext context) {
    final height = width * 1.45;
    final fallback = Container(
      width: width,
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: MF.raised, borderRadius: BorderRadius.circular(8)),
      child: CategoryBadge(category, size: width * 0.72),
    );
    final url = title.coverUrl;
    if (url.isEmpty || !url.startsWith('http')) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: CachedCoverImage(url: url, width: width, height: height, fallback: fallback),
    );
  }
}

/// A cover from the device cache (downloaded once, then shown offline too).
class CachedCoverImage extends StatefulWidget {
  const CachedCoverImage({super.key, required this.url, required this.width, required this.height, required this.fallback});
  final String url;
  final double width;
  final double height;
  final Widget fallback;

  @override
  State<CachedCoverImage> createState() => _CachedCoverImageState();
}

class _CachedCoverImageState extends State<CachedCoverImage> {
  File? _file;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(CachedCoverImage old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) _resolve();
  }

  void _resolve() {
    final url = widget.url;
    _file = CoverCache.instance.ready[url];
    if (_file != null) return;
    CoverCache.instance.file(url).then((f) {
      if (mounted && widget.url == url && f != null) setState(() => _file = f);
    });
  }

  @override
  Widget build(BuildContext context) {
    final f = _file;
    if (f == null) return widget.fallback;
    return Image.file(
      f,
      width: widget.width,
      height: widget.height,
      fit: BoxFit.cover,
      cacheWidth: (widget.width * 3).round(),
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => widget.fallback,
    );
  }
}

/// Small status pill for the app bar; tap to sync now.
class SyncIndicator extends StatelessWidget {
  const SyncIndicator({super.key, required this.account});
  final AccountController account;

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (account.status) {
      SyncState.loading => ('Loading', MF.textDim, Icons.hourglass_top_rounded),
      SyncState.syncing => ('Syncing', MF.warn, Icons.sync_rounded),
      SyncState.synced => account.pendingCount > 0
          ? ('${account.pendingCount} waiting', MF.warn, Icons.cloud_upload_outlined)
          : ('Synced', MF.good, Icons.cloud_done_outlined),
      SyncState.offline => account.pendingCount > 0
          ? ('Offline · ${account.pendingCount} saved', MF.warn, Icons.cloud_off_outlined)
          : ('Offline', MF.textDim, Icons.cloud_off_outlined),
      SyncState.error => ('Sync problem', MF.bad, Icons.error_outline_rounded),
    };
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Tooltip(
        message: account.message ?? 'Tap to sync now',
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: account.sync,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: color),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
            ]),
          ),
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.body});
  final IconData icon;
  final String title;
  final String? body;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 48, color: MF.textDim),
          const SizedBox(height: 12),
          Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          if (body != null) ...[
            const SizedBox(height: 6),
            Text(body!, textAlign: TextAlign.center, style: const TextStyle(color: MF.textDim)),
          ],
        ]),
      ),
    );
  }
}

/// A small boxed dropdown that is as wide as its longest choice but never wider
/// than the space it has (long labels end in "…" instead of overflowing).
class CompactDropdown<T> extends StatelessWidget {
  const CompactDropdown({super.key, required this.value, required this.items, required this.onChanged, this.maxWidth = 280});

  final T value;
  final List<(T, String)> items;
  final ValueChanged<T> onChanged;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final selected = items.any((i) => i.$1 == value) ? value : items.first.$1;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: IntrinsicWidth(
        child: DropdownButtonHideUnderline(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(color: MF.raised, borderRadius: BorderRadius.circular(10), border: Border.all(color: MF.border)),
            child: DropdownButton<T>(
              value: selected,
              isDense: true,
              isExpanded: true,
              items: [
                for (final i in items)
                  DropdownMenuItem(
                    value: i.$1,
                    child: Text(i.$2, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                  ),
              ],
              onChanged: (v) {
                if (v != null) onChanged(v);
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// A titled card that can be collapsed; its open/closed state is remembered on
/// this device under [prefKey].
class SectionCard extends StatefulWidget {
  const SectionCard({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.icon,
    this.prefKey,
    this.initiallyOpen = true,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget child;
  final String? prefKey;
  final bool initiallyOpen;
  final Widget? trailing;

  @override
  State<SectionCard> createState() => _SectionCardState();
}

class _SectionCardState extends State<SectionCard> {
  late bool _open = widget.prefKey == null
      ? widget.initiallyOpen
      : AppPrefs.instance.get<bool>('open.${widget.prefKey}', widget.initiallyOpen);

  void _toggle() {
    setState(() => _open = !_open);
    if (widget.prefKey != null) AppPrefs.instance.set('open.${widget.prefKey}', _open);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: MF.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: MF.border)),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          InkWell(
            onTap: _toggle,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
              child: Row(children: [
                if (widget.icon != null) ...[Icon(widget.icon, color: MF.accent), const SizedBox(width: 12)],
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(widget.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                    if (widget.subtitle != null)
                      Text(widget.subtitle!, style: const TextStyle(color: MF.textDim, fontSize: 12)),
                  ]),
                ),
                if (widget.trailing != null) widget.trailing!,
                Icon(_open ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: MF.textDim),
              ]),
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: widget.child,
            ),
        ]),
      ),
    );
  }
}

/// Opens the website's logging form minutes field with [minutes] (Stopwatch /
/// Runtime Calculator "Use for minutes"). Returns false when no log is open.
Future<bool> useMinutesForOpenLog(AccountController account, int minutes) async {
  final view = account.view;
  if (view == null) return false;
  final logging = readLogging(view.state);
  final task = asMap(logging?['currentTask']);
  if (logging == null || logging['active'] != true || task == null) return false;
  final draft = Map<String, dynamic>.from(asMap(logging['logDraft']) ?? const {});
  draft['minutes'] = minutes;
  final now = DateTime.now().millisecondsSinceEpoch;
  final at = jsNum(logging['modifiedAt']).toInt();
  await account.saveDraft(activeLogging(
    task: task,
    logDraft: draft,
    entryDraft: asMap(logging['entryDraft']) ?? <String, dynamic>{},
    modifiedAt: now > at ? now : at + 1,
    ui: logging['ui'],
  ));
  return true;
}
