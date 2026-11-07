// The website's floating + (v397 dock, v436 / v447 recovery actions, v460
// Background Processes toggle): one + on every main screen that opens a fan
// of numbered quick actions over a dimmed background.
//
//  01 Add to Logging        — the Log page with the Logging Library open
//  02 Add to Library        — a new title
//  03 Add Collection        — a new collection, then Collections
//  04 New Cover Recovery    ┐ hidden by Settings → "Recovery shortcuts in the
//  05 New Metadata Recovery │ + menu" (website `v447RecoveryShortcuts.floating`)
//  06 New Combined Recovery ┘
//  07 Show / Hide Background Processes (website `v441RecoveryUI.visibility`)
// Screens can add their own action while it makes sense (Log: "Save & get
// next task" while the form is open).

import 'package:flutter/material.dart';

import '../data/account_controller.dart';
import '../data/recovery_runner.dart';
import '../util/js.dart';
import 'theme.dart';

/// An extra action a screen offers in the + menu.
class DockAction {
  const DockAction(this.label, this.subtitle, this.icon, this.onTap);
  final String label, subtitle;
  final IconData icon;
  final VoidCallback onTap;
}

/// What the + menu asks the app to do.
class DockCommands {
  DockCommands({required this.openLogging, required this.openCollections});
  final VoidCallback openLogging, openCollections;
}

class FloatingDock {
  FloatingDock._();

  /// Extra actions from the screen on view (e.g. Log's "Save & get next task").
  static final ValueNotifier<List<DockAction>> extras = ValueNotifier(const []);

  /// Asks the Log page to open the Logging Library (website `mf397Action('logging')`).
  static final ValueNotifier<int> openLoggingLibrary = ValueNotifier(0);
}

/// Website `mf447Prefs()`: which recovery shortcuts are shown.
Map<String, bool> recoveryShortcuts(Map<String, dynamic>? settings) {
  const keys = ['floating', 'library', 'editor', 'details', 'collections', 'order', 'widget'];
  final data = asMap(settings?['v447RecoveryShortcuts']) ?? const {};
  return {for (final k in keys) k: data[k] != false};
}

/// Website `mf441Prefs()`.
Map<String, dynamic> recoveryUiPrefs(Map<String, dynamic>? settings) {
  final current = asMap(settings?['v441RecoveryUI']) ?? const <String, dynamic>{};
  const defaults = {'visibility': 'auto', 'position': 'right', 'expanded': false, 'showFinished': false};
  return {
    ...defaults,
    ...current,
    'visibility': const ['auto', 'always', 'hidden'].contains(current['visibility']) ? current['visibility'] : 'auto',
    'position': const ['left', 'right'].contains(current['position']) ? current['position'] : 'right',
    'expanded': current['expanded'] == true,
    'showFinished': current['showFinished'] == true,
  };
}

/// Website `mf441Show`: whether the Background Processes widget is visible.
bool backgroundProcessesShown(Map<String, dynamic>? settings) {
  final p = recoveryUiPrefs(settings);
  if (p['visibility'] == 'hidden') return false;
  if (p['visibility'] == 'always') return true;
  final r = RecoveryRunner.instance;
  final active = r.cover?.running == true || r.metadata?.running == true;
  return active || (p['showFinished'] == true && (r.cover != null || r.metadata != null));
}

class DockButton extends StatelessWidget {
  const DockButton({
    super.key,
    required this.account,
    required this.commands,
    required this.onAddTitle,
    required this.onAddCollection,
    required this.onRecovery,
    this.extras = false,
  });
  final AccountController account;

  /// Include the screen's own actions ([FloatingDock.extras]).
  final bool extras;
  final DockCommands commands;
  final VoidCallback onAddTitle;
  final Future<void> Function() onAddCollection;

  /// cover | metadata | both
  final void Function(String mode) onRecovery;

  Future<void> _open(BuildContext context) async {
    final settings = asMap(account.view?.state['settings']);
    final shortcuts = recoveryShortcuts(settings);
    final shown = backgroundProcessesShown(settings);
    final actions = <(String, String, IconData, VoidCallback)>[
      ('Add to Logging', 'Open Logging Library', Icons.playlist_add_rounded, commands.openLogging),
      ('Add to Library', 'Create a new title', Icons.library_add_rounded, onAddTitle),
      ('Add Collection', 'Create & open collection', Icons.create_new_folder_rounded, () => onAddCollection()),
      if (shortcuts['floating'] == true) ...[
        ('New Cover Recovery', 'Configure & start a recovery job', Icons.image_search_rounded, () => onRecovery('cover')),
        ('New Metadata Recovery', 'Configure in the unified workspace', Icons.storage_rounded, () => onRecovery('metadata')),
        ('New Combined Recovery', 'Configure in the unified workspace', Icons.layers_rounded, () => onRecovery('both')),
      ],
      (
        shown ? 'Hide Background Processes' : 'Show Background Processes',
        shown ? 'Hide the widget · recovery jobs keep running' : 'Display recovery progress and controls',
        shown ? Icons.visibility_off_rounded : Icons.visibility_rounded,
        () async {
          final p = recoveryUiPrefs(asMap(account.view?.state['settings']));
          await account.setSetting(['v441RecoveryUI'], {...p, 'visibility': shown ? 'hidden' : 'always'});
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(shown ? 'Background Processes hidden; recovery jobs continue.' : 'Background Processes shown.'),
            ));
          }
        },
      ),
      if (extras)
        for (final x in FloatingDock.extras.value) (x.label, x.subtitle, x.icon, x.onTap),
    ];
    final picked = await Navigator.of(context).push<VoidCallback>(PageRouteBuilder(
      opaque: false,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: .45),
      barrierLabel: 'Close quick actions',
      transitionDuration: const Duration(milliseconds: 220),
      reverseTransitionDuration: const Duration(milliseconds: 160),
      pageBuilder: (c, anim, _) => _Fan(actions: actions, animation: anim),
    ));
    picked?.call();
  }

  @override
  Widget build(BuildContext context) {
    if (asMap(account.view?.state['settings'])?['v405ShowFloatingAdd'] == false) return const SizedBox.shrink();
    return FloatingActionButton(
      heroTag: 'mediaflow-dock',
      tooltip: 'MediaFlow quick actions',
      onPressed: () => _open(context),
      child: const Icon(Icons.add_rounded, size: 30),
    );
  }
}

class _Fan extends StatelessWidget {
  const _Fan({required this.actions, required this.animation});
  final List<(String, String, IconData, VoidCallback)> actions;
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    return Stack(children: [
      Positioned(
        right: 16,
        bottom: pad.bottom + 16 + (MediaQuery.sizeOf(context).width >= 900 ? 0 : 80),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (var i = 0; i < actions.length; i++)
            _FanItem(
              index: i,
              count: actions.length,
              animation: animation,
              label: actions[i].$1,
              subtitle: actions[i].$2,
              icon: actions[i].$3,
              onTap: () => Navigator.of(context).pop(actions[i].$4),
            ),
          const SizedBox(height: 8),
          FloatingActionButton(
            heroTag: 'mediaflow-dock',
            tooltip: 'Close quick actions',
            onPressed: () => Navigator.of(context).pop(),
            child: RotationTransition(
              turns: Tween(begin: 0.0, end: 0.125).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutBack)),
              child: const Icon(Icons.add_rounded, size: 30),
            ),
          ),
        ]),
      ),
    ]);
  }
}

class _FanItem extends StatelessWidget {
  const _FanItem({
    required this.index,
    required this.count,
    required this.animation,
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });
  final int index, count;
  final Animation<double> animation;
  final String label, subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Items fan out from the + one after another (closest first).
    final start = ((count - 1 - index) * 0.06).clamp(0.0, 0.6);
    final curve = CurvedAnimation(parent: animation, curve: Interval(start, (start + 0.55).clamp(0.0, 1.0), curve: Curves.easeOutCubic));
    return FadeTransition(
      opacity: curve,
      child: SlideTransition(
        position: Tween(begin: const Offset(0.25, 0.35), end: Offset.zero).animate(curve),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: MF.surface,
            elevation: 6,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: MF.border)),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 250, maxWidth: 320),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(color: MF.accentSoft, borderRadius: BorderRadius.circular(12)),
                      child: Icon(icon, color: MF.accent, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
                        Text(subtitle, style: TextStyle(color: MF.textDim, fontSize: 12)),
                      ]),
                    ),
                    const SizedBox(width: 12),
                    Text((index + 1).toString().padLeft(2, '0'), style: TextStyle(color: MF.textMute, fontWeight: FontWeight.w800, fontSize: 12)),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The website's Background Processes widget (v441): running recoveries with
/// progress and Stop; hiding it keeps them running.
class BackgroundProcesses extends StatelessWidget {
  const BackgroundProcesses({super.key, required this.account, required this.onOpen});
  final AccountController account;
  final void Function(String mode) onOpen;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([RecoveryRunner.instance, account]),
      builder: (context, _) {
        final settings = asMap(account.view?.state['settings']);
        if (!backgroundProcessesShown(settings)) return const SizedBox.shrink();
        final r = RecoveryRunner.instance;
        Widget row(String label, RecoveryJob? job, String mode, VoidCallback stop) {
          final pct = job == null || job.ids.isEmpty ? 0.0 : job.done / job.ids.length;
          return InkWell(
            onTap: () => onOpen(mode),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12))),
                  Text(
                    job == null ? 'Idle' : job.running ? (job.paused ? 'Paused' : '${(pct * 100).round()}%') : (job.stopped ? 'Stopped' : 'Done'),
                    style: TextStyle(color: MF.textDim, fontSize: 11),
                  ),
                  if (job?.running == true)
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: job!.paused ? 'Resume' : 'Pause',
                      icon: Icon(job.paused ? Icons.play_arrow_rounded : Icons.pause_rounded, size: 18),
                      onPressed: () => job.paused ? RecoveryRunner.instance.resumeAll() : RecoveryRunner.instance.pauseAll(),
                    ),
                  if (job?.running == true)
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Stop',
                      icon: const Icon(Icons.stop_rounded, size: 18),
                      onPressed: stop,
                    ),
                ]),
                LinearProgressIndicator(value: job == null ? 0 : pct, minHeight: 4, borderRadius: BorderRadius.circular(3)),
                if (job != null)
                  Text(
                    '${job.done} / ${job.ids.length} · ${job.applied} saved · '
                    '${job.kind == 'cover' ? job.coverReviews.length : job.metadataReviews.length} to review',
                    style: TextStyle(color: MF.textMute, fontSize: 10),
                  ),
              ]),
            ),
          );
        }

        return Align(
          alignment: recoveryUiPrefs(settings)['position'] == 'left' ? Alignment.topLeft : Alignment.topRight,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 64, 12, 0),
            child: Material(
              color: MF.surface,
              elevation: 8,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: MF.border)),
              child: SizedBox(
                width: 250,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                  child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Row(children: [
                      Icon(Icons.sync_rounded, size: 16, color: MF.accent),
                      const SizedBox(width: 6),
                      const Expanded(child: Text('Background Processes', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13))),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Hide (jobs keep running)',
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () => account.setSetting(['v441RecoveryUI'], {...recoveryUiPrefs(settings), 'visibility': 'hidden'}),
                      ),
                    ]),
                    row('Cover Recovery', r.cover, 'cover', r.stopCover),
                    row('Metadata Recovery', r.metadata, 'metadata', r.stopMetadata),
                  ]),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
