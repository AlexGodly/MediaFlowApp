// History tabs from the website: Consumption history (v269 week view),
// Recently viewed (v340/v344 + v261 Browsing Behavior Insights) and Ratings
// (v261). The Logs tab stays the app's own.

import 'package:flutter/material.dart';

import '../config.dart';
import '../data/account_controller.dart';
import '../logic/history_views.dart';
import '../state/models.dart';
import '../util/js.dart';
import 'theme.dart';
import 'title_screen.dart' show TitleScreen;
import 'widgets.dart';

typedef EditLog = Future<void> Function(LogRecord log);
typedef DeleteLogs = Future<int?> Function(List<String> ids, String what);
typedef SaveExport = Future<String?> Function(String name, String content);

const _months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
const _weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const _short = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String _hour(int h) => '${h % 12 == 0 ? 12 : h % 12} ${h < 12 ? 'AM' : 'PM'}';
String _time(DateTime d) => '${d.hour % 12 == 0 ? 12 : d.hour % 12}:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'AM' : 'PM'}';

void _openTitle(BuildContext context, AccountController account, Map<String, dynamic>? item) {
  final id = jsStr(item?['id']);
  if (id.isEmpty) return;
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => TitleScreen(account: account, id: id)));
}

Widget _cover(Map<String, dynamic>? item, Category cat, double w) {
  final url = jsStr(item?['coverUrl']);
  final h = w * 1.45;
  final fallback = Container(
    width: w,
    height: h,
    alignment: Alignment.center,
    decoration: BoxDecoration(color: MF.parseColor(cat.color).withAlpha(0x33), borderRadius: BorderRadius.circular(8)),
    child: CategoryBadge(cat, size: w * .6),
  );
  if (!url.startsWith('http')) return fallback;
  return ClipRRect(
    borderRadius: BorderRadius.circular(8),
    child: Image.network(url, width: w, height: h, fit: BoxFit.cover, errorBuilder: (_, __, ___) => fallback),
  );
}

Widget _filterChip(String label, Widget child) => Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: TextStyle(color: MF.textDim, fontSize: 11, fontWeight: FontWeight.w700)),
        child,
      ]),
    );

Widget _drop<T>(T value, List<(T, String)> items, ValueChanged<T> onChanged) => DropdownButton<T>(
      value: items.any((x) => x.$1 == value) ? value : items.first.$1,
      isDense: true,
      underline: const SizedBox.shrink(),
      items: [for (final x in items) DropdownMenuItem(value: x.$1, child: Text(x.$2))],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );

// ---- Consumption history ---------------------------------------------------------------

class ConsumptionHistoryTab extends StatefulWidget {
  const ConsumptionHistoryTab({super.key, required this.account, required this.view, required this.onEdit, required this.onDelete, required this.saveExport});
  final AccountController account;
  final AccountView view;
  final EditLog onEdit;
  final DeleteLogs onDelete;
  final SaveExport saveExport;

  @override
  State<ConsumptionHistoryTab> createState() => _ConsumptionHistoryTabState();
}

class _ConsumptionHistoryTabState extends State<ConsumptionHistoryTab> with AutomaticKeepAliveClientMixin {
  String _category = 'all', _year = 'all', _month = 'all', _period = 'all';
  int _weekPage = 0, _weeksPerPage = 6;
  bool _select = false;
  final Set<String> _selected = {};

  @override
  bool get wantKeepAlive => true;

  AccountView get view => widget.view;

  List<Map<String, dynamic>> _filtered() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final all = memoFor(view, 'historyNewestFirst', () {
      final list = [for (final s in asList(view.state['sessions'])) if (asMap(s) != null) asMap(s)!];
      list.sort((a, b) => jsNum(b['timestamp']).compareTo(jsNum(a['timestamp'])));
      return list;
    });
    return [
      for (final s in all)
        if (s['status'] != 'skipped' &&
            (_category == 'all' || jsStr(s['categoryId']) == _category) &&
            (_year == 'all' || '${sessionDate(s).year}' == _year) &&
            (_month == 'all' || '${sessionDate(s).month}' == _month) &&
            switch (_period) {
              'today' => !sessionDate(s).isBefore(today),
              'week' => !sessionDate(s).isBefore(weekStart(now).subtract(const Duration(hours: 12))),
              'month' => !sessionDate(s).isBefore(DateTime(now.year, now.month)),
              _ => true,
            })
          s,
    ];
  }

  Future<void> _export(List<Map<String, dynamic>> sessions) async {
    final logs = {for (final l in view.logs) l.id: l};
    final csv = historyCsv(sessions, (id) => view.category(id).name, kAppVersionLabel, (s) => logs[jsStr(s['id'])]?.xp ?? 0);
    final d = DateTime.now();
    final path = await widget.saveExport(
        'mediaflow-consumption-history-${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}.csv', csv);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(path == null ? 'Could not save the export.' : 'Saved to $path')));
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final lib = memoFor(view, 'libraryLookup', () => LibraryLookup(view.state));
    final sessions = _filtered();
    final weeks = weekGroups(sessions);
    final pages = (weeks.length / _weeksPerPage).ceil().clamp(1, 1 << 20);
    if (_weekPage >= pages) _weekPage = pages - 1;
    final shown = weeks.skip(_weekPage * _weeksPerPage).take(_weeksPerPage).toList();
    final years = {for (final s in asList(view.state['sessions'])) if (asMap(s) != null) sessionDate(asMap(s)!).year}.toList()..sort((a, b) => b - a);
    final latest = latestEvents(sessions, lib);
    final logs = memoFor(view, 'logsById', () => {for (final l in view.logs) l.id: l});
    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 96), children: [
        Text('Consumption history', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
        Text('Watch/read activity, sessions, time and progress logs.', style: TextStyle(color: MF.textDim)),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            _filterChip('Category', _drop<String>(_category, [('all', 'All'), for (final c in view.categories) (c.id, c.name)], (v) => setState(() {
                  _category = v;
                  _weekPage = 0;
                }))),
            _filterChip('Year', _drop<String>(_year, [('all', 'All'), for (final y in years) ('$y', '$y')], (v) => setState(() {
                  _year = v;
                  _weekPage = 0;
                }))),
            _filterChip('Month', _drop<String>(_month, [('all', 'All'), for (var i = 1; i <= 12; i++) ('$i', _months[i - 1])], (v) => setState(() {
                  _month = v;
                  _weekPage = 0;
                }))),
            _filterChip('Period', _drop<String>(_period, const [('all', 'All history'), ('today', 'Today'), ('week', 'This week'), ('month', 'This month')], (v) => setState(() {
                  _period = v;
                  _weekPage = 0;
                }))),
            _filterChip('Weeks per page', _drop<int>(_weeksPerPage, [for (final n in const [2, 4, 6, 8, 12, 16]) (n, '$n')], (v) => setState(() {
                  _weeksPerPage = v;
                  _weekPage = 0;
                }))),
          ]),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text('${fmtNumber(sessions.length)} filtered ${sessions.length == 1 ? 'session' : 'sessions'}', style: TextStyle(color: MF.textDim)),
          OutlinedButton(
            onPressed: () => setState(() {
              _select = !_select;
              _selected.clear();
            }),
            child: Text(_select ? 'Done' : 'Select'),
          ),
          if (_select && _selected.isNotEmpty)
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: MF.bad),
              onPressed: () async {
                final n = await widget.onDelete(_selected.toList(), 'selected');
                if (n != null && mounted) setState(_selected.clear);
              },
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              label: Text('Delete ${_selected.length}'),
            ),
          OutlinedButton.icon(onPressed: () => _export(sessions), icon: const Icon(Icons.download_rounded, size: 18), label: const Text('Export CSV')),
        ]),
        if (latest.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text('LATEST CONSUMED', style: TextStyle(color: MF.textDim, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: .8)),
          const SizedBox(height: 6),
          SizedBox(
            height: 150,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: latest.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, i) {
                final ev = latest[i];
                final cat = view.category(ev.categoryId);
                return InkWell(
                  onTap: () {
                    final log = logs[ev.sessionId];
                    if (ev.item != null) {
                      _openTitle(context, widget.account, ev.item);
                    } else if (log != null) {
                      widget.onEdit(log);
                    }
                  },
                  child: SizedBox(
                    width: 72,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      _cover(ev.item, cat, 72),
                      Text(_latestLabel(ev, cat), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10, color: MF.accent, fontWeight: FontWeight.w800)),
                    ]),
                  ),
                );
              },
            ),
          ),
        ],
        if (shown.isEmpty)
          Padding(padding: const EdgeInsets.all(24), child: Text('No consumption in this view.', textAlign: TextAlign.center, style: TextStyle(color: MF.textDim))),
        for (final g in shown) _week(g, lib, logs),
        if (pages > 1)
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            TextButton.icon(
              onPressed: _weekPage == 0 ? null : () => setState(() => _weekPage--),
              icon: const Icon(Icons.chevron_left_rounded),
              label: const Text('Newer weeks'),
            ),
            Text('${_weekPage + 1} / $pages'),
            TextButton.icon(
              onPressed: _weekPage >= pages - 1 ? null : () => setState(() => _weekPage++),
              icon: const Icon(Icons.chevron_right_rounded),
              label: const Text('Older weeks'),
            ),
          ]),
      ]);
  }

  String _latestLabel(HistoryEvent ev, Category cat) {
    final season = asMap(ev.row['season']);
    if (season != null && jsNumOrNull(season['episode']) != null) {
      final sn = season['number'] == null ? '' : 'S${jsNum(season['number']).toInt().toString().padLeft(2, '0')} ';
      return '${sn}Ep. ${jsNum(season['episode']).toInt()}';
    }
    final p = jsNum(ev.item?['progress']), total = jsNum(ev.item?['total']);
    final abbr = progressAbbr(cat.unit);
    if (abbr == 'Seen' && ((total > 0 && p >= total) || jsStr(ev.item?['status']) == 'completed')) return 'Seen all';
    if (p > 0) return '$abbr ${fmtNumber(p)}';
    if (ev.qty > 0) return '+${fmtNumber(ev.qty)} ${unitLabel(cat.unit, ev.qty)}';
    return fmtMinutes(ev.minutes);
  }

  Widget _week(WeekGroup g, LibraryLookup lib, Map<String, LogRecord> logs) {
    final s = summarizeWeek(g, lib);
    final now = DateTime.now();
    final title = localDayKey(g.start) == localDayKey(weekStart(now))
        ? 'THIS WEEK, YOU CONSUMED'
        : localDayKey(g.start) == localDayKey(weekStart(now).subtract(const Duration(days: 7)))
            ? 'LAST WEEK, YOU CONSUMED'
            : 'WEEK ${isoWeek(g.start)}, YOU CONSUMED';
    final range = 'Week ${isoWeek(g.start)} · ${_short[g.start.month - 1]} ${g.start.day} – ${_short[g.end.month - 1]} ${g.end.day}, ${g.end.year}';
    final days = <String, List<HistoryEvent>>{};
    for (final ev in g.events(lib)) {
      days.putIfAbsent(localDayKey(sessionDate(ev.session)), () => []).add(ev);
    }
    final dayKeys = days.keys.toList()..sort((a, b) => b.compareTo(a));
    Widget metric(String k, String v) => Container(
          width: 150,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: MF.raised, borderRadius: BorderRadius.circular(12)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(k, style: TextStyle(color: MF.textDim, fontSize: 11)),
            Text(v, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          ]),
        );
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: MF.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: MF.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(range, style: TextStyle(color: MF.textDim, fontSize: 12, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text('⌛ $title', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          metric('Total consumed', fmtMinutes(s.total)),
          metric('Days with activity', '${s.activeDays} ${s.activeDays == 1 ? 'day' : 'days'}'),
          metric('Daily average', fmtMinutes(s.average)),
          metric('Most active day', s.mostDay == null ? '—' : _weekdays[s.mostDay!.weekday - 1]),
          metric('Peak hour', s.peakHour == null ? '—' : _hour(s.peakHour!)),
          metric('Longest session', fmtMinutes(s.longest)),
        ]),
        if (s.categories.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final c in s.categories)
              Chip(
                avatar: CategoryBadge(view.category(c.categoryId), size: 22),
                label: Text('${view.category(c.categoryId).name} · ${fmtMinutes(c.minutes)} · ${c.titles} ${c.titles == 1 ? 'title' : 'titles'}'),
                visualDensity: VisualDensity.compact,
              ),
          ]),
        ],
        if (s.top.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text('MOST CONSUMED TITLES', style: TextStyle(color: MF.textDim, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: .8)),
          const SizedBox(height: 6),
          Row(children: [
            for (final t in s.top)
              Expanded(
                child: InkWell(
                  onTap: () => _openTitle(context, widget.account, t.event.item),
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Row(children: [
                      _cover(t.event.item, view.category(t.event.categoryId), 36),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(t.event.title.isEmpty ? view.category(t.event.categoryId).name : t.event.title,
                              maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                          Text('${fmtNumber(t.units)} ${unitLabel(view.category(t.event.categoryId).unit, t.units)}',
                              style: TextStyle(color: MF.textDim, fontSize: 11)),
                        ]),
                      ),
                    ]),
                  ),
                ),
              ),
          ]),
        ],
        for (final day in dayKeys) _day(day, days[day]!, logs),
      ]),
    );
  }

  Widget _day(String key, List<HistoryEvent> events, Map<String, LogRecord> logs) {
    final d = DateTime.parse(key);
    final minutes = events.fold<double>(0, (a, e) => a + e.minutes);
    events.sort((a, b) => jsNum(b.session['timestamp']).compareTo(jsNum(a.session['timestamp'])));
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text('${_weekdays[d.weekday - 1]}, ${_months[d.month - 1]} ${d.day}', style: const TextStyle(fontWeight: FontWeight.w800))),
          Text(fmtMinutes(minutes), style: TextStyle(color: MF.textDim)),
        ]),
        for (final ev in events)
          () {
            final cat = view.category(ev.categoryId);
            final log = logs[ev.sessionId];
            final selected = _selected.contains(ev.sessionId);
            return InkWell(
              onTap: _select
                  ? () => setState(() => selected ? _selected.remove(ev.sessionId) : _selected.add(ev.sessionId))
                  : () => _openTitle(context, widget.account, ev.item),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(children: [
                  if (_select) Checkbox(value: selected, onChanged: (_) => setState(() => selected ? _selected.remove(ev.sessionId) : _selected.add(ev.sessionId))),
                  _cover(ev.item, cat, 40),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(ev.title.isEmpty ? cat.name : ev.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text(
                        [
                          cat.name,
                          if (ev.qty > 0) '${fmtNumber(ev.qty)} ${unitLabel(cat.unit, ev.qty)}',
                          fmtMinutes(ev.minutes),
                          _time(sessionDateTime(ev.session)),
                        ].join(' · '),
                        style: TextStyle(color: MF.textDim, fontSize: 12),
                      ),
                    ]),
                  ),
                  if (!_select && log != null)
                    PopupMenuButton<String>(
                      onSelected: (v) => v == 'edit' ? widget.onEdit(log) : widget.onDelete([log.id], 'this'),
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'edit', child: Text('Edit')),
                        PopupMenuItem(value: 'delete', child: Text('Delete')),
                      ],
                    ),
                ]),
              ),
            );
          }(),
      ]),
    );
  }
}

// ---- Recently viewed ---------------------------------------------------------------

class RecentlyViewedTab extends StatefulWidget {
  const RecentlyViewedTab({super.key, required this.account, required this.view});
  final AccountController account;
  final AccountView view;

  @override
  State<RecentlyViewedTab> createState() => _RecentlyViewedTabState();
}

class _RecentlyViewedTabState extends State<RecentlyViewedTab> with AutomaticKeepAliveClientMixin {
  String _category = 'all', _period = 'all';
  final _q = TextEditingController();
  int _page = 0;
  static const _size = 50;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final view = widget.view;
    final lib = memoFor(view, 'libraryLookup', () => LibraryLookup(view.state));
    final all = recentRows(view.state, lib, category: _category, periodDays: int.tryParse(_period) ?? 0, query: _q.text);
    final pages = (all.length / _size).ceil().clamp(1, 1 << 20);
    if (_page >= pages) _page = pages - 1;
    final rows = all.skip(_page * _size).take(_size).toList();
    final insights = browsingInsights(all, (id) => view.category(id).name);
    final days = <String, List<RecentEntry>>{};
    for (final r in rows) {
      days.putIfAbsent(localDayKey(DateTime.fromMillisecondsSinceEpoch(r.timestamp)), () => []).add(r);
    }
    final today = DateTime.now();
    String dayLabel(String key) {
      final d = DateTime.parse(key);
      if (key == localDayKey(today)) return 'Today';
      if (key == localDayKey(today.subtract(const Duration(days: 1)))) return 'Yesterday';
      return '${_months[d.month - 1]} ${d.day}${d.year == today.year ? '' : ', ${d.year}'}';
    }

    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 96), children: [
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.end, children: [
          _filterChip('Category', _drop<String>(_category, [('all', 'All media'), for (final c in view.categories) (c.id, c.name)], (v) => setState(() {
                _category = v;
                _page = 0;
              }))),
          _filterChip('Period', _drop<String>(_period, const [('all', 'All time'), ('7', 'Last 7 days'), ('30', 'Last 30 days'), ('365', 'Last year')], (v) => setState(() {
                _period = v;
                _page = 0;
              }))),
        ]),
        const SizedBox(height: 8),
        TextField(
          controller: _q,
          decoration: const InputDecoration(hintText: 'Search recently viewed…', prefixIcon: Icon(Icons.search_rounded), isDense: true),
          onChanged: (_) => setState(() => _page = 0),
        ),
        const SizedBox(height: 6),
        Text('${fmtNumber(all.length)} titles', style: TextStyle(color: MF.textDim)),
        if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text('No matching recent activity. Adjust the filters; older category-only logs stay in Consumption history and Logs.',
                textAlign: TextAlign.center, style: TextStyle(color: MF.textDim)),
          ),
        for (final key in days.keys) ...[
          const SizedBox(height: 14),
          Row(children: [
            Text(dayLabel(key), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            const SizedBox(width: 8),
            Text(_weekdays[DateTime.parse(key).weekday - 1], style: TextStyle(color: MF.textDim)),
            const Spacer(),
            Text('${days[key]!.length} ${days[key]!.length == 1 ? 'title' : 'titles'}', style: TextStyle(color: MF.textDim, fontSize: 12)),
          ]),
          for (final part in const ['Night', 'Morning', 'Afternoon', 'Evening'].reversed)
            if (days[key]!.any((r) => daypart(r.timestamp) == part)) ...[
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 4),
                child: Text(part, style: TextStyle(color: MF.textDim, fontWeight: FontWeight.w800, fontSize: 12)),
              ),
              for (final r in days[key]!.where((r) => daypart(r.timestamp) == part)) _card(r),
            ],
        ],
        if (pages > 1)
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            IconButton(onPressed: _page == 0 ? null : () => setState(() => _page--), icon: const Icon(Icons.chevron_left_rounded)),
            Text('Page ${_page + 1} of $pages'),
            IconButton(onPressed: _page >= pages - 1 ? null : () => setState(() => _page++), icon: const Icon(Icons.chevron_right_rounded)),
          ]),
        if (insights != null) _insights(insights),
      ]);
  }

  Widget _card(RecentEntry r) {
    final ev = r.event;
    final cat = widget.view.category(ev.categoryId);
    final t = DateTime.fromMillisecondsSinceEpoch(r.timestamp);
    return InkWell(
      onTap: () => _openTitle(context, widget.account, ev.item),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          _cover(ev.item, cat, 44),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${cat.name} · ${_time(t)}', style: TextStyle(color: MF.textDim, fontSize: 11)),
              Text(ev.title, style: const TextStyle(fontWeight: FontWeight.w800)),
              Text([if (ev.qty > 0) '${fmtNumber(ev.qty)} ${unitLabel(cat.unit, ev.qty)}', fmtMinutes(ev.minutes)].join(' · '),
                  style: TextStyle(color: MF.textDim, fontSize: 12)),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _insights(BrowsingInsights i) {
    Widget card(String k, String v, String sub) => Container(
          width: 160,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: MF.raised, borderRadius: BorderRadius.circular(12)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(k, style: TextStyle(color: MF.textDim, fontSize: 11)),
            Text(v, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            Text(sub, style: TextStyle(color: MF.textDim, fontSize: 11)),
          ]),
        );
    return Container(
      margin: const EdgeInsets.only(top: 18),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: MF.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: MF.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Browsing Behavior Insights', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
        Text('Based on your filtered recently viewed items', style: TextStyle(color: MF.textDim, fontSize: 12)),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          card('Peak hour', '${i.peakHour.toString().padLeft(2, '0')}:00', '${i.peakCount} items'),
          card('Browsing personality', i.personality, '${i.personalityPct}% of activity'),
          card('Most active day', i.mostDay, '${i.mostDayCount} items'),
          card('What you browse', i.topCategory, '${i.topCategoryPct}%'),
        ]),
        const SizedBox(height: 10),
        for (final e in i.dayparts.entries)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(children: [
              SizedBox(width: 80, child: Text(e.key, style: const TextStyle(fontSize: 12))),
              Expanded(child: LinearProgressIndicator(value: e.value / 100, minHeight: 6, borderRadius: BorderRadius.circular(4))),
              SizedBox(width: 44, child: Text('${e.value}%', textAlign: TextAlign.end, style: const TextStyle(fontSize: 12))),
            ]),
          ),
      ]),
    );
  }
}

// ---- Ratings -----------------------------------------------------------------------

class RatingsHistoryTab extends StatefulWidget {
  const RatingsHistoryTab({super.key, required this.account, required this.view});
  final AccountController account;
  final AccountView view;

  @override
  State<RatingsHistoryTab> createState() => _RatingsHistoryTabState();
}

class _RatingsHistoryTabState extends State<RatingsHistoryTab> with AutomaticKeepAliveClientMixin {
  String _category = 'all', _year = 'all', _rating = 'all', _sort = 'recent';
  final _q = TextEditingController();
  int _page = 0;
  static const _size = 50;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final view = widget.view;
    final all = ratedTitles(view.state, category: _category, year: _year, rating: _rating, query: _q.text, sort: _sort);
    final years = {
      for (final i in asList(view.state['library']))
        if (asMap(i) != null && jsNum(asMap(i)!['rating']) > 0 && jsTruthy(asMap(i)!['year'])) jsStr(asMap(i)!['year']),
    }.toList()
      ..sort((a, b) => (num.tryParse(b) ?? 0).compareTo(num.tryParse(a) ?? 0));
    final pages = (all.length / _size).ceil().clamp(1, 1 << 20);
    if (_page >= pages) _page = pages - 1;
    final rows = all.skip(_page * _size).take(_size).toList();
    final avg = all.isEmpty ? 0.0 : all.fold<double>(0, (a, i) => a + jsNum(i['rating'])) / all.length;
    final dist = List<int>.filled(11, 0);
    for (final i in all) {
      dist[jsNum(i['rating']).floor().clamp(0, 10)]++;
    }
    final maxD = dist.fold<int>(1, (a, b) => b > a ? b : a);
    void reset() => _page = 0;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 96), children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          _filterChip('Category', _drop<String>(_category, [('all', 'All media'), for (final c in view.categories) (c.id, c.name)], (v) => setState(() {
                _category = v;
                reset();
              }))),
          _filterChip('Rating', _drop<String>(_rating, [('all', 'All ratings'), for (var n = 10; n >= 1; n--) ('$n', '$n stars')], (v) => setState(() {
                _rating = v;
                reset();
              }))),
          _filterChip('Year', _drop<String>(_year, [('all', 'All years'), for (final y in years) (y, y)], (v) => setState(() {
                _year = v;
                reset();
              }))),
          _filterChip('Sort', _drop<String>(_sort, const [('recent', 'Recently updated'), ('rating', 'Rating'), ('title', 'Title')], (v) => setState(() {
                _sort = v;
                reset();
              }))),
        ]),
        const SizedBox(height: 8),
        TextField(
          controller: _q,
          decoration: const InputDecoration(hintText: 'Search ratings…', prefixIcon: Icon(Icons.search_rounded), isDense: true),
          onChanged: (_) => setState(reset),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: MF.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: MF.border)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(avg == 0 ? '—' : avg.toStringAsFixed(1), style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900)),
              Text('average · ${fmtNumber(all.length)} rated', style: TextStyle(color: MF.textDim, fontSize: 12)),
            ]),
            const SizedBox(width: 16),
            Expanded(
              child: SizedBox(
                height: 56,
                child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  for (var n = 1; n <= 10; n++)
                    Expanded(
                      child: Tooltip(
                        message: '$n: ${dist[n]}',
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 1.5),
                          height: 4 + 50 * dist[n] / maxD,
                          decoration: BoxDecoration(color: const Color(0xFFE8A94A), borderRadius: BorderRadius.circular(3)),
                        ),
                      ),
                    ),
                ]),
              ),
            ),
          ]),
        ),
        if (rows.isEmpty)
          Padding(padding: const EdgeInsets.all(24), child: Text('No rated titles in this view.', textAlign: TextAlign.center, style: TextStyle(color: MF.textDim))),
        for (final i in rows)
          InkWell(
            onTap: () => _openTitle(context, widget.account, i),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                _cover(i, view.category(jsStr(i['categoryId'])), 40),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(cleanTitle(i['title']), style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text([view.category(jsStr(i['categoryId'])).name, if (jsTruthy(i['year'])) jsStr(i['year'])].join(' · '),
                        style: TextStyle(color: MF.textDim, fontSize: 12)),
                  ]),
                ),
                Text('★ ${jsNum(i['rating']).toStringAsFixed(1)}', style: const TextStyle(color: Color(0xFFE8A94A), fontWeight: FontWeight.w900)),
              ]),
            ),
          ),
        if (pages > 1)
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            IconButton(onPressed: _page == 0 ? null : () => setState(() => _page--), icon: const Icon(Icons.chevron_left_rounded)),
            Text('Page ${_page + 1} of $pages'),
            IconButton(onPressed: _page >= pages - 1 ? null : () => setState(() => _page++), icon: const Icon(Icons.chevron_right_rounded)),
          ]),
      ]);
  }
}
