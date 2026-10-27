import 'package:flutter/material.dart';
import '../data/mediaflow_library_repository.dart';
import 'mediaflow_theme.dart';

/// These labels describe snapshot reads, not website-compatible writes.
String nativeCloudSourceLabel(NativeSnapshotSource source,
    {bool refreshing = false}) {
  if (refreshing) return 'Refreshing cloud';
  switch (source) {
    case NativeSnapshotSource.cloud: return 'Cloud read-only';
    case NativeSnapshotSource.cloudNotCached: return 'Cloud · cache warning';
    case NativeSnapshotSource.offline: return 'Offline copy';
    case NativeSnapshotSource.recoveredPrevious: return 'Recovered copy';
    case NativeSnapshotSource.offlineMemory: return 'Memory-only copy';
    case NativeSnapshotSource.invalidCloud: return 'Cloud data invalid';
    case NativeSnapshotSource.unavailable: return 'Cloud unavailable';
    case NativeSnapshotSource.checkingCloud: return 'Checking cloud';
    case NativeSnapshotSource.idle: return 'Not loaded';
  }
}

bool nativeCloudSourceOnline(NativeSnapshotSource source) =>
    source == NativeSnapshotSource.cloud ||
    source == NativeSnapshotSource.cloudNotCached;

/// A tappable status surface; always makes write limitations explicit.
class MfCloudIndicator extends StatelessWidget {
  const MfCloudIndicator({
    super.key, required this.repository, this.onTap, this.compact = false,
  });

  final SupabaseMediaFlowLibraryRepository repository;
  final VoidCallback? onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<NativeSnapshotSource>(
        valueListenable: repository.source,
        builder: (context, source, _) => ValueListenableBuilder<bool>(
          valueListenable: repository.refreshing,
          builder: (context, refreshing, _) {
            final tokens = MediaFlowTokens.of(context);
            final online = nativeCloudSourceOnline(source);
            final color = online ? tokens.healthy
                : source == NativeSnapshotSource.checkingCloud || refreshing
                    ? tokens.due : tokens.overused;
            return Tooltip(
              message: 'Existing MediaFlow cloud data is readable. '
                  'This beta does not upload Library, Logging, History or XP edits.',
              child: Material(
                color: color.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(999),
                child: InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(999),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: compact ? 10 : 12, vertical: 8),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(refreshing ? Icons.sync : online
                        ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
                        color: color, size: 16),
                      const SizedBox(width: 7),
                      Text(nativeCloudSourceLabel(source,
                        refreshing: refreshing),
                        style: TextStyle(color: color,
                          fontWeight: FontWeight.w700,
                          fontSize: compact ? 11 : 12)),
                    ]),
                  ),
                ),
              ),
            );
          },
        ),
      );
}
