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

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/account_controller.dart';
import '../data/app_prefs.dart';
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
              child: SizedBox(
                // Every option the same size (website v397): fixed width,
                // narrower on small phones, one line each for title and note.
                width: math.min(300.0, MediaQuery.sizeOf(context).width - 32),
                height: 60,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
                  child: Row(children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(color: MF.accentSoft, borderRadius: BorderRadius.circular(12)),
                      child: Icon(icon, color: MF.accent, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                        Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: MF.textDim, fontSize: 12)),
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

/// The website's Background Processes widget (v441): minimised to one bar
/// (name, how many jobs run, overall %) or expanded to a card per job with
/// its progress, numbers and actions. Open/minimised and left/right are the
/// account's `v441RecoveryUI` settings, shared with the website.
class BackgroundProcesses extends StatelessWidget {
  const BackgroundProcesses({super.key, required this.account, required this.onOpen, this.onSettings});
  final AccountController account;
  final void Function(String mode) onOpen;
  final VoidCallback? onSettings;

  void _set(Map<String, dynamic>? settings, Map<String, dynamic> changes) =>
      account.setSetting(['v441RecoveryUI'], {...recoveryUiPrefs(settings), ...changes});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([RecoveryRunner.instance, account]),
      builder: (context, _) {
        final settings = asMap(account.view?.state['settings']);
        if (!backgroundProcessesShown(settings)) return const SizedBox.shrink();
        final prefs = recoveryUiPrefs(settings);
        final expanded = prefs['expanded'] == true;
        final left = prefs['position'] == 'left';
        final r = RecoveryRunner.instance;
        double pctOf(RecoveryJob? j) => j == null || j.ids.isEmpty ? 0 : (j.done / j.ids.length).clamp(0, 1).toDouble();
        final active = [r.cover, r.metadata].whereType<RecoveryJob>().where((j) => j.running).length;
        final overall = math.max(pctOf(r.cover), pctOf(r.metadata));
        final width = math.min(340.0, MediaQuery.sizeOf(context).width - 24);
        final phone = MediaQuery.sizeOf(context).width < 900;

        final procPrefs = processPrefs(settings);
        final bar = GestureDetector(
          // v565: drag the widget anywhere by its bar (website v555).
          onPanStart: (_) => ProcessesUi.dragStart(),
          onPanUpdate: (d) => ProcessesUi.dragBy(d.delta),
          onPanEnd: (_) => ProcessesUi.dragEnd(procPrefs),
          child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _set(settings, {'expanded': !expanded}),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
            child: Row(children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(color: MF.accentSoft, borderRadius: BorderRadius.circular(11)),
                child: Icon(Icons.layers_rounded, color: MF.accent, size: 19),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  const Text('Background Processes', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
                  Text(
                    active == 0 ? 'Cover & metadata recovery' : '$active active recovery process${active == 1 ? '' : 'es'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: MF.textDim, fontSize: 11),
                  ),
                ]),
              ),
              _CountUp(value: overall * 100, style: TextStyle(fontWeight: FontWeight.w900, color: MF.accent, fontSize: 15)),
              const SizedBox(width: 4),
              AnimatedRotation(
                turns: expanded ? 0.5 : 0,
                duration: const Duration(milliseconds: 250),
                child: Icon(Icons.keyboard_arrow_up_rounded, color: MF.textDim),
              ),
              IconButton(
                tooltip: 'Minimise to an icon',
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.remove_rounded, color: MF.textDim, size: 20),
                onPressed: () => ProcessesUi.setMinimized(true),
              ),
            ]),
          ),
        ));

        final content = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _ProcessCard(
            icon: Icons.image_search_rounded,
            title: 'Cover Recovery',
            job: r.cover,
            pct: pctOf(r.cover),
            statusText: _status(r.cover, 'Recovering missing covers'),
            stats: r.cover == null
                ? 'Ready to find missing covers'
                : '${fmt(r.cover!.done)} / ${fmt(r.cover!.total)} titles · ${fmt(r.cover!.applied)} recovered'
                    '${r.cover!.coverReviews.isEmpty ? '' : ' · ${fmt(r.cover!.coverReviews.length)} awaiting review'}',
            actions: [
              _Act(Icons.tune_rounded, 'Setup', () => onOpen('cover')),
              if (r.cover?.running == true) _pauseAct(r.cover!),
              if (r.cover?.coverReviews.isNotEmpty == true) _Act(Icons.search_rounded, 'Review (${r.cover!.coverReviews.length})', () => onOpen('cover')),
              if (r.cover?.running == true) _Act(Icons.stop_rounded, 'Stop', r.stopCover),
            ],
            onTitle: () => onOpen('cover'),
          ),
          const SizedBox(height: 8),
          _ProcessCard(
            icon: Icons.dataset_rounded,
            title: 'Metadata Recovery',
            job: r.metadata,
            pct: pctOf(r.metadata),
            statusText: _status(r.metadata, 'Recovering missing fields'),
            stats: r.metadata == null
                ? 'Select Library titles to preview or recover'
                : '${fmt(r.metadata!.done)} / ${fmt(r.metadata!.total)} titles · ${fmt(r.metadata!.fieldsFilled)} missing fields recovered'
                    '${r.metadata!.errors.isEmpty ? '' : ' · ${r.metadata!.errors.length} warnings'}',
            actions: [
              _Act(Icons.search_rounded, 'New Recovery', () => onOpen('metadata')),
              if (r.metadata?.running == true) _pauseAct(r.metadata!),
              if (r.metadata?.metadataReviews.isNotEmpty == true)
                _Act(Icons.fact_check_rounded, 'Review (${r.metadata!.metadataReviews.length})', () => onOpen('metadata')),
              if (r.metadata?.running == true) _Act(Icons.stop_rounded, 'Stop', r.stopMetadata),
            ],
            onTitle: () => onOpen('metadata'),
          ),
          const SizedBox(height: 6),
          Row(children: [
            if (onSettings != null)
              TextButton.icon(onPressed: onSettings, icon: const Icon(Icons.settings_rounded, size: 16), label: const Text('Recovery Settings')),
            const Spacer(),
            TextButton.icon(
              onPressed: () => _set(settings, {'visibility': 'hidden', 'expanded': false}),
              icon: const Icon(Icons.close_rounded, size: 16),
              label: const Text('Hide widget'),
            ),
          ]),
        ]);

        final fabBottom = (phone ? 80.0 : 0.0) + 16 + MediaQuery.paddingOf(context).bottom;
        return ValueListenableBuilder<bool>(
          valueListenable: ProcessesUi.minimized,
          builder: (context, minimized, _) {
            if (minimized) {
              // v565: a slightly smaller icon next to the +, with progress and count.
              final idleHidden = procPrefs['idle'] == 'hide' && active == 0 && prefs['visibility'] != 'always';
              if (idleHidden) return const SizedBox.shrink();
              return Align(
                alignment: Alignment.bottomRight,
                child: Padding(
                  padding: EdgeInsets.only(right: 16 + 56 + 12, bottom: fabBottom + 5),
                  child: _MiniProcesses(icon: procPrefs['icon'] ?? 'both', active: active, pct: overall, onTap: () => ProcessesUi.setMinimized(false)),
                ),
              );
            }
            return LayoutBuilder(builder: (context, box) {
              ProcessesUi.area = box.biggest;
              final panel = KeyedSubtree(
                key: ProcessesUi.panelKey,
                child: Material(
              color: MF.surface,
              elevation: 10,
              shadowColor: Colors.black54,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: MF.border)),
              clipBehavior: Clip.antiAlias,
              child: SizedBox(
                width: width,
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.bottomCenter,
                  child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    if (expanded)
                      ConstrainedBox(
                        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.6),
                        child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(10, 10, 10, 0), child: content),
                      ),
                    bar,
                  ]),
                ),
              ),
            ),
              );
              return ValueListenableBuilder<Offset?>(
                valueListenable: ProcessesUi.pos,
                builder: (context, pos, _) {
                  if (pos == null) {
                    return Align(
                      alignment: left ? Alignment.bottomLeft : Alignment.bottomRight,
                      // Above the + (and the phone's bottom bar), never on top of them.
                      child: Padding(padding: EdgeInsets.fromLTRB(12, 12, 12, fabBottom + 80), child: panel),
                    );
                  }
                  final c = ProcessesUi.clamp(pos);
                  return Stack(children: [Positioned(left: c.dx, top: c.dy, child: panel)]);
                },
              );
            });
          },
        );
      },
    );
  }

  static String fmt(num n) => n.round().toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');

  static String _status(RecoveryJob? j, String working) {
    if (j == null) return 'No active job';
    if (j.running) return j.paused ? 'Paused · checkpoint preserved' : working;
    if (j.stopped) return 'Stopped';
    return 'Recovery complete';
  }

  static _Act _pauseAct(RecoveryJob j) => j.paused
      ? _Act(Icons.play_arrow_rounded, 'Resume', RecoveryRunner.instance.resumeAll)
      : _Act(Icons.pause_rounded, 'Pause', RecoveryRunner.instance.pauseAll);
}

class _Act {
  const _Act(this.icon, this.label, this.onTap);
  final IconData icon;
  final String label;
  final VoidCallback onTap;
}

class _ProcessCard extends StatelessWidget {
  const _ProcessCard({
    required this.icon,
    required this.title,
    required this.job,
    required this.pct,
    required this.statusText,
    required this.stats,
    required this.actions,
    required this.onTitle,
  });
  final IconData icon;
  final String title, statusText, stats;
  final RecoveryJob? job;
  final double pct;
  final List<_Act> actions;
  final VoidCallback onTitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: MF.raised, borderRadius: BorderRadius.circular(14), border: Border.all(color: MF.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          onTap: onTitle,
          borderRadius: BorderRadius.circular(10),
          child: Row(children: [
            Icon(icon, color: MF.accent, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                Text(statusText, style: TextStyle(color: MF.textDim, fontSize: 11)),
              ]),
            ),
            _CountUp(value: pct * 100, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
          ]),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: pct),
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOutCubic,
            builder: (context, v, _) => Stack(children: [
              Container(height: 8, color: MF.border),
              FractionallySizedBox(
                widthFactor: v.clamp(0, 1).toDouble(),
                child: Container(
                  height: 8,
                  decoration: BoxDecoration(gradient: LinearGradient(colors: [MF.accent.withAlpha(0xB0), MF.accent])),
                ),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 6),
        Text(stats, style: TextStyle(color: MF.textDim, fontSize: 11)),
        if (actions.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final a in actions)
              OutlinedButton.icon(
                onPressed: a.onTap,
                style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 10)),
                icon: Icon(a.icon, size: 16),
                label: Text(a.label, style: const TextStyle(fontSize: 12)),
              ),
          ]),
        ],
      ]),
    );
  }
}

/// A percentage that counts to its new value (website `mf397PercentTo`).
class _CountUp extends StatelessWidget {
  const _CountUp({required this.value, required this.style});
  final double value;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(end: value),
        duration: const Duration(milliseconds: 550),
        curve: Curves.easeOutCubic,
        builder: (context, v, _) => Text('${v.round()}%', style: style),
      );
}


/// v565 `mf565Processes` (account setting, shared with the website).
Map<String, String> processPrefs(Map<String, dynamic>? settings) {
  final raw = asMap(settings?['mf565Processes']) ?? const <String, dynamic>{};
  String pick(String k, List<String> ok, String def) => ok.contains(raw[k]) ? raw[k] as String : def;
  return {
    'position': pick('position', const ['remember', 'default'], 'remember'),
    'edges': pick('edges', const ['stay', 'snap'], 'stay'),
    'icon': pick('icon', const ['both', 'ring', 'count', 'plain'], 'both'),
    'idle': pick('idle', const ['hide', 'show'], 'hide'),
  };
}

/// Where the Background Processes widget is and whether it is minimised —
/// per device, like the website's localStorage (v555).
class ProcessesUi {
  ProcessesUi._();
  static final ValueNotifier<bool> minimized = ValueNotifier(AppPrefs.instance.get<bool>('mf565ProcMin', false));
  static final ValueNotifier<Offset?> pos = ValueNotifier(_load());
  static final GlobalKey panelKey = GlobalKey();
  static Size area = Size.zero;
  static bool _remember = true;

  static Offset? _load() {
    final raw = AppPrefs.instance.get<String>('mf565ProcPos', '');
    final parts = raw.split(',');
    if (parts.length != 2) return null;
    final x = double.tryParse(parts[0]), y = double.tryParse(parts[1]);
    return x == null || y == null ? null : Offset(x, y);
  }

  static void setMinimized(bool v) {
    minimized.value = v;
    unawaited(AppPrefs.instance.set('mf565ProcMin', v));
  }

  static Size _panelSize() {
    final box = panelKey.currentContext?.findRenderObject();
    return box is RenderBox && box.hasSize ? box.size : const Size(340, 64);
  }

  /// Kept fully on screen, 8 px from every edge.
  static Offset clamp(Offset p) {
    final s = _panelSize();
    final maxX = math.max(8.0, area.width - s.width - 8), maxY = math.max(8.0, area.height - s.height - 8);
    return Offset(p.dx.clamp(8.0, maxX), p.dy.clamp(8.0, maxY));
  }

  static void dragStart() {
    if (pos.value != null) return;
    // Start from where the widget is drawn now.
    final box = panelKey.currentContext?.findRenderObject();
    final parent = box is RenderBox ? box.parent : null;
    if (box is RenderBox && box.hasSize && parent is RenderBox) {
      pos.value = box.localToGlobal(Offset.zero, ancestor: parent);
    } else {
      pos.value = Offset(area.width - 352, area.height - 200);
    }
  }

  static void dragBy(Offset d) => pos.value = clamp((pos.value ?? Offset.zero) + d);

  static void dragEnd(Map<String, String> prefs) {
    var p = pos.value;
    if (p == null) return;
    if (prefs['edges'] == 'snap') {
      final s = _panelSize();
      p = Offset(p.dx + s.width / 2 < area.width / 2 ? 8 : math.max(8, area.width - s.width - 8), p.dy);
      pos.value = clamp(p);
    }
    _remember = prefs['position'] != 'default';
    unawaited(AppPrefs.instance.set('mf565ProcPos', _remember ? '${pos.value!.dx.round()},${pos.value!.dy.round()}' : ''));
  }

  /// "Always at the default spot": forget the position on the next start.
  static void applyPrefs(Map<String, String> prefs) {
    if (prefs['position'] == 'default' && AppPrefs.instance.get<String>('mf565ProcPos', '').isNotEmpty) {
      unawaited(AppPrefs.instance.set('mf565ProcPos', ''));
    }
  }
}

/// The minimised Background Processes icon: progress ring and/or job count.
class _MiniProcesses extends StatelessWidget {
  const _MiniProcesses({required this.icon, required this.active, required this.pct, required this.onTap});
  final String icon;
  final int active;
  final double pct;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ring = (icon == 'both' || icon == 'ring') && active > 0;
    final count = (icon == 'both' || icon == 'count') && active > 0;
    return Tooltip(
      message: active == 0 ? 'Background Processes' : 'Background Processes · $active running · ${(pct * 100).round()}%',
      child: SizedBox(
        width: 54,
        height: 54,
        child: Stack(clipBehavior: Clip.none, children: [
          Positioned.fill(
            child: Material(
              color: MF.surface,
              elevation: 8,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: MF.border)),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: onTap,
                child: Icon(Icons.layers_rounded, color: MF.accent, size: 22),
              ),
            ),
          ),
          if (ring)
            Positioned.fill(
              child: IgnorePointer(
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: CircularProgressIndicator(value: pct.clamp(0, 1).toDouble(), strokeWidth: 3, color: MF.accent, backgroundColor: MF.accentSoft),
                ),
              ),
            ),
          if (count)
            Positioned(
              top: -6,
              right: -6,
              child: Container(
                constraints: const BoxConstraints(minWidth: 20),
                height: 20,
                padding: const EdgeInsets.symmetric(horizontal: 5),
                alignment: Alignment.center,
                decoration: BoxDecoration(color: MF.accent, borderRadius: BorderRadius.circular(10), border: Border.all(color: MF.background, width: 2)),
                child: Text('$active', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
              ),
            ),
        ]),
      ),
    );
  }
}
