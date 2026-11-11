import 'dart:math' as math;
import 'dart:io';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

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
    final url = categoryIconUrl(category.iconUrl);
    final fallback = _fallback(color);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withAlpha(0x2E),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: url.isEmpty ? fallback : NetIcon(url: url, size: size * 0.62, fallback: fallback),
    );
  }

  /// The emoji, or the first letter in the category colour (never 🖼️, the
  /// website's stand-in for a link icon).
  Widget _fallback(Color color) {
    final icon = category.icon;
    if (icon.isNotEmpty && icon != '🖼️' && icon != '🖼' && icon.runes.length <= 3) {
      return Text(icon, style: TextStyle(fontSize: size * 0.48));
    }
    return Text(category.name.isEmpty ? '?' : category.name.characters.first.toUpperCase(),
        style: TextStyle(fontSize: size * 0.45, fontWeight: FontWeight.w800, color: color));
  }
}

/// `v144SafeIconUrl` (plus the website's own relative asset paths).
String categoryIconUrl(String raw) {
  final v = raw.trim();
  if (v.isEmpty) return '';
  if (v.startsWith('./') || v.startsWith('assets/')) return '$kWebsiteUrl${v.replaceFirst(RegExp(r'^\./'), '')}';
  final u = Uri.tryParse(v);
  return u != null && (u.scheme == 'http' || u.scheme == 'https') && u.host.isNotEmpty ? v : '';
}

/// A small image from a link, kept on this device (works offline after the
/// first time); SVG and bitmap images. Shows [fallback] while loading or when
/// the link doesn't work.
class NetIcon extends StatefulWidget {
  const NetIcon({super.key, required this.url, required this.size, required this.fallback});
  final String url;
  final double size;
  final Widget fallback;

  @override
  State<NetIcon> createState() => _NetIconState();
}

class _NetIconState extends State<NetIcon> {
  File? _file;
  bool _svg = false, _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(NetIcon old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) {
      _file = null;
      _failed = false;
      _load();
    }
  }

  static final Map<String, bool> _svgCache = {};

  Future<void> _load() async {
    final url = widget.url;
    final ready = CoverCache.instance.ready[url];
    if (ready != null && _svgCache.containsKey(url)) {
      _file = ready;
      _svg = _svgCache[url]!;
      return;
    }
    final f = await CoverCache.instance.file(url);
    var svg = false;
    if (f != null) {
      svg = _svgCache[url] ??= await _isSvg(f, url);
    }
    if (!mounted || url != widget.url) return;
    setState(() {
      _file = f;
      _svg = svg;
      _failed = f == null;
    });
  }

  static Future<bool> _isSvg(File f, String url) async {
    if (Uri.tryParse(url)?.path.toLowerCase().endsWith('.svg') ?? false) return true;
    try {
      final head = String.fromCharCodes((await f.openRead(0, 256).first).where((c) => c < 128)).trimLeft().toLowerCase();
      return head.startsWith('<svg') || (head.startsWith('<?xml') && head.contains('<svg'));
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = _file;
    if (f == null) return _failed ? widget.fallback : Opacity(opacity: .35, child: widget.fallback);
    final s = widget.size;
    if (_svg) {
      return SvgPicture.file(f, width: s, height: s, fit: BoxFit.contain, placeholderBuilder: (_) => widget.fallback);
    }
    return Image.file(f, width: s, height: s, fit: BoxFit.contain, errorBuilder: (_, __, ___) => widget.fallback);
  }
}

/// The pixel width to decode an image at: its drawn width times the screen's
/// pixel ratio, never more than [max]. Covers decoded at full size (often
/// 1000×1500) used most of the app's memory on desktop (v565).
int? decodeWidth(BuildContext context, double width, {int max = 900}) {
  if (!width.isFinite || width <= 0) return null;
  final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2.0;
  return (width * dpr).ceil().clamp(16, max).toInt();
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
      cacheWidth: decodeWidth(context, widget.width),
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
            Text(body!, textAlign: TextAlign.center, style: TextStyle(color: MF.textDim)),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: MF.border)),
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
                      Text(widget.subtitle!, style: TextStyle(color: MF.textDim, fontSize: 12)),
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

// ---- keeping the app light ---------------------------------------------------------------

/// Whether the page this widget is on is the one on screen (set by the shell).
class PageActivity extends InheritedWidget {
  const PageActivity({super.key, required this.active, required super.child});
  final ValueListenable<bool> active;

  static ValueListenable<bool>? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<PageActivity>()?.active;

  @override
  bool updateShouldNotify(PageActivity old) => old.active != active;
}

/// Like [ListenableBuilder], but a page that is not on screen does not rebuild:
/// it catches up once when it is shown again. Keeps hidden tabs from redoing
/// their work on every account change.
class LiveBuilder extends StatefulWidget {
  const LiveBuilder({super.key, required this.listenable, required this.builder, this.child});
  final Listenable listenable;
  final TransitionBuilder builder;
  final Widget? child;

  @override
  State<LiveBuilder> createState() => _LiveBuilderState();
}

class _LiveBuilderState extends State<LiveBuilder> {
  ValueListenable<bool>? _active;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    widget.listenable.addListener(_changed);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final a = PageActivity.maybeOf(context);
    if (!identical(a, _active)) {
      _active?.removeListener(_activeChanged);
      _active = a;
      a?.addListener(_activeChanged);
    }
  }

  @override
  void didUpdateWidget(LiveBuilder old) {
    super.didUpdateWidget(old);
    if (!identical(old.listenable, widget.listenable)) {
      old.listenable.removeListener(_changed);
      widget.listenable.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.listenable.removeListener(_changed);
    _active?.removeListener(_activeChanged);
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    if (_active == null || _active!.value) {
      setState(() {});
    } else {
      _dirty = true;
    }
  }

  void _activeChanged() {
    if (mounted && _dirty && (_active?.value ?? true)) {
      _dirty = false;
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, widget.child);
}

final Expando<Map<String, Object?>> _memo = Expando('memo');

/// Computes something once per account version ([owner] is the account view,
/// which is replaced whenever the account changes).
T memoFor<T>(Object owner, String key, T Function() compute) {
  final m = _memo[owner] ??= <String, Object?>{};
  if (m.containsKey(key)) return m[key] as T;
  final v = compute();
  m[key] = v;
  return v;
}

/// A page's scrolling list that scrolls across the whole page width while its
/// content stays [maxWidth] wide and centred (v565: with a centred narrow
/// list, the mouse wheel did nothing over the empty sides on desktop).
class PageListView extends StatelessWidget {
  const PageListView({super.key, required this.maxWidth, this.padding = EdgeInsets.zero, required this.children});
  final double maxWidth;
  final EdgeInsets padding;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final extra = box.maxWidth.isFinite ? math.max(0.0, (box.maxWidth - maxWidth) / 2) : 0.0;
        return ListView(
          padding: padding.copyWith(left: padding.left + extra, right: padding.right + extra),
          children: children,
        );
      });
}
