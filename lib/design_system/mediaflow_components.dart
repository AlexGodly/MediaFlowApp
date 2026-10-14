import 'package:flutter/material.dart';
import 'mediaflow_theme.dart';

/// Reusable surfaces for v410-native pages. No business logic or persistence.
class MfPanel extends StatelessWidget {
  const MfPanel({super.key, required this.child, this.padding = const EdgeInsets.all(18)});
  final Widget child;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(padding: padding, child: child),
  );
}

class MfPageHeader extends StatelessWidget {
  const MfPageHeader({
    super.key, required this.title, this.subtitle, this.trailing, this.leading,
  });
  final String title;
  final String? subtitle;
  final Widget? trailing, leading;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      if (leading != null) ...[leading!, const SizedBox(width: MediaFlowSpacing.xs)],
      Expanded(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, maxLines: 2, overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.headlineMedium),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      )),
      if (trailing != null) ...[
        const SizedBox(width: MediaFlowSpacing.xs), trailing!,
      ],
    ],
  );
}

class MfBadge extends StatelessWidget {
  const MfBadge({super.key, required this.label, this.icon, this.color});
  final String label;
  final IconData? icon;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final t = MediaFlowTokens.of(context);
    final accent = color ?? t.accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[
          Icon(icon, color: accent, size: 14),
          const SizedBox(width: 5),
        ],
        Text(label, style: TextStyle(
          color: accent, fontSize: 12, fontWeight: FontWeight.w700,
        )),
      ]),
    );
  }
}

class MfEmptyState extends StatelessWidget {
  const MfEmptyState({super.key, required this.title, required this.message,
    this.icon = Icons.inbox_outlined, this.action});
  final String title, message;
  final IconData icon;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Center(child: ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 420),
    child: Padding(
      padding: const EdgeInsets.all(MediaFlowSpacing.xl),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 38, color: MediaFlowTokens.of(context).muted),
        const SizedBox(height: MediaFlowSpacing.md),
        Text(title, textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: MediaFlowSpacing.xs),
        Text(message, textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium),
        if (action != null) ...[
          const SizedBox(height: MediaFlowSpacing.md), action!,
        ],
      ]),
    ),
  ));
}

/// Keyboard- and screen-reader-accessible desktop navigation item.
class MfNavigationTile extends StatelessWidget {
  const MfNavigationTile({
    super.key, required this.icon, required this.label,
    required this.selected, required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final t = MediaFlowTokens.of(context);
    return Semantics(
      button: true,
      selected: selected,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        child: Material(
          color: selected ? t.accent.withValues(alpha: 0.14) : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(MediaFlowRadius.medium),
            side: BorderSide(
              color: selected ? t.accent.withValues(alpha: 0.30) : Colors.transparent,
            ),
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(MediaFlowRadius.medium),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
              child: Row(children: [
                Icon(icon, color: selected ? t.accent : t.muted),
                const SizedBox(width: 12),
                Expanded(child: Text(label,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: selected ? t.text : t.muted,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500))),
                if (selected) Container(width: 3, height: 18,
                  decoration: BoxDecoration(color: t.accent,
                    borderRadius: BorderRadius.circular(3))),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Mobile: scroll-safe modal sheet. Wider windows: centered dialog.
/// Caller owns final confirmation and changes; this component only presents UI.
Future<T?> showMfAdaptiveDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool dismissible = true,
}) {
  final width = MediaQuery.sizeOf(context).width;
  if (width < MediaFlowBreakpoints.tablet) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      isDismissible: dismissible,
      useSafeArea: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(ctx).bottom,
        ),
        child: SingleChildScrollView(child: builder(ctx)),
      ),
    );
  }
  return showDialog<T>(
    context: context,
    barrierDismissible: dismissible,
    builder: (ctx) => Dialog(child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: SingleChildScrollView(child: builder(ctx)),
    )),
  );
}
