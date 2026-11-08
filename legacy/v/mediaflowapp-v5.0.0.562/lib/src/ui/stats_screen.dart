// Statistics: every section of the website's Statistics page, with the
// website's own show/hide choices (Customize writes them to the account).

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/account_controller.dart';
import '../logic/stats.dart';
import '../state/models.dart';
import '../util/js.dart';
import 'home_shell.dart' show Section;
import 'presence.dart';
import 'theme.dart';
import 'widgets.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key, required this.account});
  final AccountController account;

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  int? _year;
  String? _month;

  AccountController get account => widget.account;

  Future<void> _customize() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: MF.surface,
      builder: (c) => LiveBuilder(
        listenable: account,
        builder: (c, _) {
          final state = account.view?.state ?? const <String, dynamic>{};
          return Column(children: [
            const ListTile(
              title: Text('Statistics sections', style: TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text('Shown or hidden on the website too. Hiding a section never deletes data.'),
            ),
            Expanded(
              child: ListView(children: [
                for (final comp in kStatsComponents)
                  SwitchListTile(
                    title: Text(comp.$2),
                    value: statsComponentVisible(state, comp.$1),
                    onChanged: (v) async {
                      await account.setSetting(['v186ControlCenter', 'statsComponents', 'values', comp.$1], v);
                      await account.setSetting(['v186ControlCenter', 'statsComponents', 'modifiedAt'], DateTime.now().millisecondsSinceEpoch);
                    },
                  ),
              ]),
            ),
          ]);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Statistics'),
        actions: [
          IconButton(tooltip: 'Customize sections', icon: const Icon(Icons.tune_rounded), onPressed: _customize),
          SyncIndicator(account: account),
        ],
      ),
      body: LiveBuilder(
        listenable: account,
        builder: (context, _) {
          final view = account.view;
          if (view == null) return const SizedBox.shrink();
          final m = memoFor(view, 'stats', () => StatsModel(view.state, DateTime.now()));
          PresenceHub.instance.section(Section.stats, PresenceInfo(situation: 'stats', values: {'level': '${m.level.level}', 'streak': '${m.streak}'}));
          bool on(String k) => statsComponentVisible(view.state, k);
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                children: [
                  if (on('profile')) _profile(view, m),
                  if (on('achievements')) _achievements(m),
                  if (on('leveling')) _leveling(m),
                  if (on('activeTime') && m.activeMs > 0) _activeTime(m),
                  _wrap([
                    if (on('today')) _period('Today', m.today),
                    if (on('week')) _period('This week', m.week),
                    if (on('month')) _period('This month', m.month),
                  ]),
                  _wrap([
                    if (on('lifetime')) _big('LIFETIME', fmtMinutes(m.life.minutes), 'Total time consumed'),
                    if (on('units')) _big('UNITS', fmtNumber(m.totalUnits), 'Episodes, chapters, movies & issues'),
                    if (on('streak')) _big('STREAK', '${m.streak} 🔥', 'Current consecutive days'),
                  ]),
                  if (on('sevenDayMinutes')) _card('7-DAY MINUTES', BarChart(bars: [for (final d in m.last7) (d.label, d.minutes, fmtMinutes(d.minutes))])),
                  if (on('sevenDaySessions')) _card('7-DAY SESSIONS', BarChart(bars: [for (final d in m.last7) (d.label, d.tasks.toDouble(), '${d.tasks}')])),
                  if (on('thirtyDayMinutes'))
                    _card('30-DAY DAILY MINUTES', BarChart(bars: [for (final d in m.last30) (d.label, d.minutes, fmtMinutes(d.minutes))], labelEvery: 5)),
                  if (on('ninetyDayActivity'))
                    _card('90-DAY ACTIVITY', BarChart(bars: [for (final d in m.last90) (d.label, d.minutes, fmtMinutes(d.minutes))], labelEvery: 1, thin: true)),
                  if (on('categoryMix')) _categoryMix(view, m),
                  if (on('mediaTypeMix')) _card('MEDIA TYPE MIX', _records([for (final x in m.mediaTypeMix) (x.$1, fmtMinutes(x.$2))])),
                  if (on('libraryStatus')) _card('LIBRARY STATUS', _records([for (final x in m.libraryStatus) (x.$1, '${x.$2}')])),
                  if (on('priorityDistribution')) _card('PRIORITY DISTRIBUTION', _records([for (final x in m.priorities) (x.$1, '${x.$2}')])),
                  if (on('repeatConsumption')) ...[_repeats(m)],
                  if (on('libraryHealth'))
                    _card('LIBRARY HEALTH', _records([
                      ('Library titles', '${m.library.length}'),
                      ('Active titles', '${m.library.where((i) => i['status'] == 'active').length}'),
                      ('Completed titles', '${m.library.where((i) => i['status'] == 'completed').length}'),
                      ('Total units logged', fmtNumber(m.totalUnits)),
                    ])),
                  if (on('advancedMetrics'))
                    _card('ADVANCED METRICS', _records([
                      ('Average daily minutes (7d)', fmtMinutes(m.avgDaily7)),
                      ('Average session', fmtMinutes(m.avgSession)),
                      ('Most active day', m.mostActiveDay == null ? '—' : _longDay(m.mostActiveDay!)),
                      ('Peak day minutes', fmtMinutes(m.peakDay)),
                      ('Lifetime sessions', '${m.logicalSessions}'),
                    ])),
                  if (on('heatmap')) _heatmap(m),
                  if (on('monthlyRecap')) _recap(view, m),
                  if (on('categoryBalance')) _categoryBalance(view, m),
                  if (on('saturation')) _saturation(view, m),
                  if (on('records')) _recordsCard(view, m),
                  if (on('ratings')) _ratings(m),
                  if (on('completionTimeline')) _timeline(view, m),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ---- building blocks ----

  Widget _card(String label, Widget child, {Widget? trailing}) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Material(
          color: MF.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: MF.border)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(
                  child: Text(label, style: TextStyle(color: MF.textDim, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
                ),
                if (trailing != null) trailing,
              ]),
              const SizedBox(height: 10),
              child,
            ]),
          ),
        ),
      );

  Widget _wrap(List<Widget> tiles) {
    if (tiles.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: LayoutBuilder(builder: (context, c) {
        final perRow = c.maxWidth > 640 ? tiles.length : 1;
        final w = (c.maxWidth - (perRow - 1) * 12) / perRow;
        return Wrap(spacing: 12, runSpacing: 12, children: [for (final t in tiles) SizedBox(width: w, child: t)]);
      }),
    );
  }

  Widget _tile(List<Widget> children) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: MF.surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: MF.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );

  Widget _period(String label, Totals t) => _tile([
        Text(label, style: TextStyle(color: MF.textDim, fontSize: 12, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text(fmtMinutes(t.minutes), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
        const SizedBox(height: 4),
        Text(t.unitsText(), style: TextStyle(color: MF.textDim, fontSize: 12)),
      ]);

  Widget _big(String label, String value, String hint) => _tile([
        Text(label, style: TextStyle(color: MF.textDim, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
        const SizedBox(height: 6),
        Text(value, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
        Text(hint, style: TextStyle(color: MF.textDim, fontSize: 12)),
      ]);

  Widget _records(List<(String, String)> rows) => rows.isEmpty
      ? Text('No data yet.', style: TextStyle(color: MF.textDim))
      : Column(children: [
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(children: [
                Expanded(child: Text(r.$1, style: TextStyle(color: MF.textDim))),
                const SizedBox(width: 10),
                Flexible(child: Text(r.$2, textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w800))),
              ]),
            ),
        ]);

  Widget _barRow(Widget label, double pct, Color color, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          SizedBox(width: 130, child: label),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(value: pct.clamp(0, 1).toDouble(), minHeight: 9, color: color, backgroundColor: MF.raised),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(width: 64, child: Text(value, textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
        ]),
      );

  Widget _catLabel(AccountView view, Map<String, dynamic> raw) {
    final cat = view.category(jsStr(raw['id']));
    return Row(children: [
      CategoryBadge(cat, size: 20),
      const SizedBox(width: 6),
      Expanded(child: Text(cat.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
    ]);
  }

  Color _catColor(AccountView view, Object? id) {
    final hex = view.category(jsStr(id)).color.replaceAll('#', '');
    final v = int.tryParse(hex.length == 6 ? 'FF$hex' : hex, radix: 16);
    return v == null ? MF.accent : Color(v);
  }

  String _longDay(String iso) {
    const wd = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    const mo = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final d = DateTime.parse('${iso}T12:00:00');
    return '${wd[d.weekday - 1]}, ${mo[d.month - 1]} ${d.day}';
  }

  String _date(double ms) {
    const mo = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final d = DateTime.fromMillisecondsSinceEpoch(ms.toInt());
    return '${mo[d.month - 1]} ${d.day}, ${d.year}';
  }

  // ---- sections ----

  Widget _profile(AccountView view, StatsModel m) {
    final name = view.profileName.isEmpty ? (account.email.split('@').first) : view.profileName;
    return _card(
      'PROFILE',
      Row(children: [
        CircleAvatar(
          radius: 30,
          backgroundColor: MF.accentSoft,
          child: Text(name.isEmpty ? '?' : name[0].toUpperCase(), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            Text(account.email, style: TextStyle(color: MF.textDim, fontSize: 13)),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              _pill('${m.titles} titles'),
              _pill('${m.logicalSessions} sessions'),
              _pill('${fmtMinutes(m.life.minutes)} consumed'),
            ]),
          ]),
        ),
      ]),
    );
  }

  Widget _pill(String t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: MF.raised, borderRadius: BorderRadius.circular(20)),
        child: Text(t, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
      );

  Widget _achievements(StatsModel m) {
    final a = m.achievements;
    final items = [
      (fmtNumber(a.completed), 'Completed titles'),
      (fmtNumber(a.episodes), 'Episodes watched'),
      (fmtNumber(a.movies), 'Movies completed / logged'),
      (fmtNumber(a.chapters), 'Chapters read'),
      (fmtNumber(a.issues), 'Issues read'),
      (fmtNumber(a.minutes.round()), 'Minutes consumed'),
    ];
    return _card(
      'LIFETIME ACHIEVEMENTS',
      Wrap(spacing: 10, runSpacing: 10, children: [
        for (final x in items)
          Container(
            width: 132,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: MF.raised, borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(x.$1, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
              Text(x.$2, style: TextStyle(color: MF.textDim, fontSize: 12)),
            ]),
          ),
      ]),
    );
  }

  Widget _leveling(StatsModel m) {
    final l = m.level;
    final left = l.needed - l.current;
    return _card(
      'LEVELING',
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Level ${l.level}', style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900)),
        Text('${fmtNumber(l.xp)} lifetime XP', style: TextStyle(color: MF.textDim)),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(value: l.pct / 100, minHeight: 10, backgroundColor: MF.raised),
        ),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(child: Text('${fmtNumber(l.current)} / ${fmtNumber(l.needed)} XP', style: const TextStyle(fontSize: 12))),
          Text('${l.pct}%', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
        ]),
        Text(left <= 0 ? 'Ready for the next level' : '${fmtNumber(left)} XP to Level ${l.level + 1}',
            style: TextStyle(color: MF.textDim, fontSize: 12)),
      ]),
    );
  }

  Widget _activeTime(StatsModel m) {
    String mins(double ms) => fmtMinutes((ms / 60000).round());
    const names = {'android': 'Android', 'ios': 'iOS', 'windows': 'Windows', 'macos': 'macOS', 'linux': 'Linux'};
    final platforms = [
      for (final e in m.xp.m.entries)
        if (e.key.startsWith('appMs.') && e.value > 0) (names[e.key.substring(6)] ?? e.key.substring(6), e.value),
    ]..sort((a, b) => b.$2.compareTo(a.$2));
    return _card('ACTIVE TIME SPENT IN MEDIAFLOW', _records([
      ('Time spent', mins(m.activeMs)),
      ('On the website', mins(m.xp['websiteActiveMs'])),
      ('In the MediaFlow app', mins(m.xp['appActiveMs'])),
      for (final p in platforms) ('   ${p.$1}', mins(p.$2)),
      ('XP from active time', '+${fmtNumber(m.xp['activeTimeXP'])} XP'),
    ]));
  }

  Widget _categoryMix(AccountView view, StatsModel m) {
    final rows = m.categoryMix;
    final max = rows.fold<double>(1, (a, x) => math.max(a, x.minutes));
    return _card(
      '30-DAY CATEGORY MIX',
      rows.isEmpty
          ? Text('No data yet.', style: TextStyle(color: MF.textDim))
          : Column(children: [
              for (final x in rows) _barRow(_catLabel(view, x.cat), x.minutes / max, _catColor(view, x.cat['id']), fmtMinutes(x.minutes)),
            ]),
    );
  }

  Widget _repeats(StatsModel m) {
    final r = m.repeats;
    if (r.episodes + r.chapters + r.issues + r.movies == 0) return const SizedBox.shrink();
    return _card('↻ REPEAT CONSUMPTION', _records([
      ('Repeat sessions', fmtNumber(r.sessions)),
      ('Episodes rewatched', fmtNumber(r.episodes)),
      ('Chapters reread', fmtNumber(r.chapters)),
      ('Issues reread', fmtNumber(r.issues)),
      ('Movies rewatched', fmtNumber(r.movies)),
      ('Repeat time', fmtMinutes(r.minutes)),
    ]));
  }

  Widget _heatmap(StatsModel m) {
    final years = m.heatmapYears;
    final year = years.contains(_year) ? _year! : (years.isEmpty ? DateTime.now().year : years.first);
    final h = m.heatmap(year);
    final jan1 = DateTime(year);
    final lead = (jan1.weekday + 6) % 7; // Monday-first, like the website
    final daysInYear = DateTime(year, 12, 31).difference(jan1).inDays + 1;
    final cells = <Widget>[
      for (var i = 0; i < lead; i++) const SizedBox(width: 12, height: 12),
      for (var i = 0; i < daysInYear; i++)
        () {
          final d = DateTime(year, 1, 1 + i);
          final k = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
          final v = h.days[k];
          final minutes = v?.minutes ?? 0;
          final level = minutes == 0 ? 0 : math.min(4, (minutes / h.max * 4).ceil());
          final tip = [
            _date(d.millisecondsSinceEpoch.toDouble()),
            if (minutes > 0) '${fmtMinutes(minutes)} · ${v!.sessions} log${v.sessions == 1 ? '' : 's'}',
            if (v != null && v.started.isNotEmpty) 'Started: ${v.started.take(6).join(', ')}',
            if (v != null && v.finished.isNotEmpty) 'Finished: ${v.finished.take(6).join(', ')}',
          ].join('\n');
          return Tooltip(
            message: tip,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: level == 0 ? MF.raised : MF.accent.withValues(alpha: 0.2 + 0.2 * level),
                borderRadius: BorderRadius.circular(3),
                border: v != null && (v.started.isNotEmpty || v.finished.isNotEmpty)
                    ? Border.all(color: v.finished.isNotEmpty ? MF.good : const Color(0xFF7FB2FF), width: 1.5)
                    : null,
              ),
            ),
          );
        }(),
    ];
    final columns = <Widget>[];
    for (var c = 0; c * 7 < cells.length; c++) {
      columns.add(Padding(
        padding: const EdgeInsets.only(right: 3),
        child: Column(children: [
          for (final cell in cells.skip(c * 7).take(7)) Padding(padding: const EdgeInsets.only(bottom: 3), child: cell),
        ]),
      ));
    }
    return _card(
      'CONSUMPTION HEATMAP · $year',
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          reverse: year == DateTime.now().year,
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: columns),
        ),
        const SizedBox(height: 8),
        Text('Each square is one day. Intensity is based on minutes logged that day; outlined squares mark titles started (blue) or finished (green).',
            style: TextStyle(color: MF.textDim, fontSize: 12)),
      ]),
      trailing: CompactDropdown<int>(value: year, items: [for (final y in years) (y, '$y')], onChanged: (y) => setState(() => _year = y)),
    );
  }

  Widget _recap(AccountView view, StatsModel m) {
    final months = m.recapMonths;
    final now = DateTime.now();
    final current = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final selected = months.contains(_month) ? _month! : (months.contains(current) ? current : months.first);
    final r = m.recap(selected);
    const mo = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    String label(String k) {
      final p = k.split('-');
      return '${mo[int.parse(p[1]) - 1]} ${p[0]}';
    }

    return _card(
      'MONTHLY RECAP',
      Wrap(spacing: 10, runSpacing: 10, children: [
        _recapTile(fmtMinutes(r.minutes), 'spent'),
        _recapTile(r.top == null ? '—' : view.category(jsStr(r.top!['id'])).name, 'top category · ${fmtMinutes(r.topMinutes)}'),
        _recapTile('${r.finished}', 'titles finished'),
        _recapTile('${r.longest}', 'longest active-day streak'),
      ]),
      trailing: CompactDropdown<String>(
        value: selected,
        items: [for (final k in months) (k, label(k))],
        onChanged: (v) => setState(() => _month = v),
        maxWidth: 180,
      ),
    );
  }

  Widget _recapTile(String value, String label) => Container(
        width: 150,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: MF.raised, borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          Text(label, style: TextStyle(color: MF.textDim, fontSize: 12)),
        ]),
      );

  Widget _categoryBalance(AccountView view, StatsModel m) {
    final rows = m.categoryBalance;
    return _card(
      'CATEGORY BALANCE — LAST 7 DAYS',
      rows.isEmpty
          ? Text('No enabled categories.', style: TextStyle(color: MF.textDim))
          : Column(children: [
              for (final x in rows) _barRow(_catLabel(view, x.cat), x.pct / 100, _catColor(view, x.cat['id']), fmtMinutes(x.minutes)),
            ]),
    );
  }

  Widget _saturation(AccountView view, StatsModel m) {
    final rows = m.saturation;
    return _card(
      'RECENT SATURATION',
      rows.isEmpty
          ? Text('No enabled categories.', style: TextStyle(color: MF.textDim))
          : Column(children: [
              for (final x in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    Expanded(child: _catLabel(view, x.cat)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: Color(x.color).withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
                      child: Text(x.label, style: TextStyle(color: Color(x.color), fontSize: 11, fontWeight: FontWeight.w800)),
                    ),
                  ]),
                ),
            ]),
    );
  }

  Widget _recordsCard(AccountView view, StatsModel m) {
    String cat(({Map<String, dynamic> cat, double minutes})? x) => x == null ? '—' : '${view.category(jsStr(x.cat['id'])).name} — ${fmtMinutes(x.minutes)}';
    String streak(Map<String, dynamic>? c, int n) => c == null ? '—' : '${view.category(jsStr(c['id'])).name} × $n';
    final s = m.categoryStreaks;
    final neglected = m.mostNeglected;
    final life = m.life;
    return _card('RECORDS', _records([
      ('Most consumed category', cat(m.mostConsumed)),
      ('Least consumed category', cat(m.leastConsumed)),
      ('Current category streak', streak(s.current, s.currentCount)),
      ('Longest streak ever', streak(s.longest, s.longestCount)),
      ('Most neglected category', neglected.$1 == null ? '—' : '${view.category(jsStr(neglected.$1!['id'])).name} — ${neglected.$2}'),
      ('Average daily consumption', fmtMinutes(m.averageDaily)),
      ('Average task completion rate', '${m.completionRate}%'),
      (
        'Total lifetime',
        [
          fmtMinutes(totalsFor(m.consumption).minutes),
          '${fmtNumber(life.units['episodes']!)} ep',
          '${fmtNumber(life.units['chapters']!)} ch',
          '${fmtNumber(life.units['movies']!)} mv',
          '${fmtNumber(life.units['issues']!)} is',
        ].join(' · ')
      ),
    ]));
  }

  Widget _ratings(StatsModel m) {
    final dist = m.ratingDistribution;
    final max = dist.fold<int>(1, (a, x) => math.max(a, x.$2));
    return _card(
      'RATINGS',
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 10, runSpacing: 10, children: [
          _recapTile('${m.ratedCount}', 'Rated titles'),
          _recapTile(m.ratedCount == 0 ? '—' : m.averageRating.toStringAsFixed(2), 'Average rating / 10'),
          _recapTile('${m.rated8}', 'Rated 8+'),
          _recapTile('${m.rated95}', 'Rated 9.5+'),
        ]),
        const SizedBox(height: 12),
        for (final x in dist) _barRow(Text('${x.$1}/10', style: const TextStyle(fontSize: 13)), x.$2 / max, MF.accent, '${x.$2}'),
      ]),
    );
  }

  Widget _timeline(AccountView view, StatsModel m) {
    final rows = m.completionTimeline;
    return _card(
      'TITLE COMPLETION TIMELINE',
      rows.isEmpty
          ? Text('No completed titles have a recorded completion date yet.', style: TextStyle(color: MF.textDim))
          : Column(children: [
              for (final x in rows.take(_timelineShown))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(children: [
                    Container(width: 10, height: 10, decoration: BoxDecoration(color: _catColor(view, x.categoryId), shape: BoxShape.circle)),
                    const SizedBox(width: 10),
                    SizedBox(width: 96, child: Text(_date(x.completedAt), style: TextStyle(color: MF.textDim, fontSize: 12))),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(x.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                        Text(view.category(jsStr(x.categoryId)).name, style: TextStyle(color: MF.textDim, fontSize: 12)),
                      ]),
                    ),
                  ]),
                ),
              if (rows.length > _timelineShown)
                TextButton(onPressed: () => setState(() => _timelineShown += 50), child: Text('Show more (${rows.length - _timelineShown} left)')),
            ]),
    );
  }

  int _timelineShown = 50;
}

/// A simple bar chart: (label, value, tooltip) per bar.
class BarChart extends StatelessWidget {
  const BarChart({super.key, required this.bars, this.labelEvery = 1, this.thin = false, this.height = 140});
  final List<(String, double, String)> bars;
  final int labelEvery;
  final bool thin;
  final double height;

  @override
  Widget build(BuildContext context) {
    final max = bars.fold<double>(0, (a, b) => math.max(a, b.$2));
    return SizedBox(
      height: height + 34,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (var i = 0; i < bars.length; i++)
          Expanded(
            child: Tooltip(
              message: '${bars[i].$1.isEmpty ? '' : '${bars[i].$1}: '}${bars[i].$3}',
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                Container(
                  height: max == 0 ? 2 : math.max(2, bars[i].$2 / max * height),
                  margin: EdgeInsets.symmetric(horizontal: thin ? 0.5 : 2),
                  decoration: BoxDecoration(
                    color: bars[i].$2 > 0 ? MF.accent : MF.raised,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(thin ? 1 : 4)),
                  ),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  height: 28,
                  child: (i % labelEvery == 0 || i == bars.length - 1) && bars[i].$1.isNotEmpty
                      ? OverflowBox(
                          maxWidth: 60,
                          child: Text(bars[i].$1, textAlign: TextAlign.center, maxLines: 2, style: TextStyle(color: MF.textDim, fontSize: 10)),
                        )
                      : null,
                ),
              ]),
            ),
          ),
      ]),
    );
  }
}
