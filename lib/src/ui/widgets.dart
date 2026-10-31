import 'package:flutter/material.dart';

import '../config.dart';
import '../data/account_controller.dart';
import '../state/models.dart';
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
      child: Image.network(
        url,
        width: width,
        height: height,
        fit: BoxFit.cover,
        cacheWidth: (width * 3).round(),
        errorBuilder: (_, __, ___) => fallback,
        loadingBuilder: (context, child, progress) => progress == null ? child : fallback,
      ),
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
