// Settings → Discord → Custom Status: a PreMiD-style editor for your own
// Rich Presence. Basic (type, name, status line, party), Text (details and
// state with links), Images (big and small, hover text, links), Time
// (absolute or relative start/end), Buttons (up to two) and Profiles (saved
// statuses with schedules, free). Reset / Clear / Apply Status, with a live
// preview of the draft next to what's active. Everything is saved in the
// account (see logic/custom_status.dart), so all devices share it.

import 'dart:async';

import 'package:flutter/material.dart';

import '../data/account_controller.dart';
import '../logic/custom_status.dart';
import '../platform/discord_presence.dart';
import '../util/js.dart';
import 'collections_screen.dart' show pickLibraryTitles;
import 'discord_card.dart';
import 'presence.dart';
import 'theme.dart';
import 'widgets.dart' show progressText;

Future<void> openCustomStatus(BuildContext context, AccountController account) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => CustomStatusScreen(account: account)));

class CustomStatusScreen extends StatefulWidget {
  const CustomStatusScreen({super.key, required this.account});
  final AccountController account;

  @override
  State<CustomStatusScreen> createState() => _CustomStatusScreenState();
}

class _CustomStatusScreenState extends State<CustomStatusScreen> {
  late Map<String, dynamic> _draft;
  Timer? _saveDraft;
  int _rev = 0; // rebuilds the text fields after Reset / load

  AccountController get account => widget.account;
  Map<String, dynamic>? get _settings => asMap(account.view?.state['settings']);
  CustomStatusStore get _store => CustomStatusStore.of(_settings);

  @override
  void initState() {
    super.initState();
    _draft = _store.draft;
  }

  @override
  void dispose() {
    _saveDraft?.cancel();
    if (_saveDraft != null) unawaited(_write({'draft': _draft}));
    super.dispose();
  }

  Future<void> _write(Map<String, dynamic> changes) =>
      account.setSetting([kCustomStatusKey], _store.withChanges(changes, DateTime.now().millisecondsSinceEpoch));

  void _set(String key, Object? value) {
    setState(() => _draft = normalizeStatus({..._draft, key: value}));
    _saveDraft?.cancel();
    _saveDraft = Timer(const Duration(milliseconds: 900), () {
      _saveDraft = null;
      unawaited(_write({'draft': _draft}));
    });
  }

  void _load(Map<String, dynamic> status) {
    setState(() {
      _draft = normalizeStatus(status);
      _rev++;
    });
    unawaited(_write({'draft': _draft}));
  }

  Future<void> _apply() async {
    if (!statusHasContent(_draft)) {
      _toast('Add a name, details, state or image first.');
      return;
    }
    _saveDraft?.cancel();
    _saveDraft = null;
    await _write({'draft': _draft, 'active': {..._draft, 'appliedAt': DateTime.now().millisecondsSinceEpoch}});
    _toast('Custom Status applied on all your devices ✓');
  }

  Future<void> _clear() async {
    await _write({'active': null});
    _toast('Custom Status cleared — back to MediaFlow\'s automatic status');
  }

  void _toast(String t) => ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(t)));

  @override
  Widget build(BuildContext context) {
    final d = DiscordPresence.instance;
    return PresenceScope(
      info: const PresenceInfo(situation: 'settings'),
      child: ListenableBuilder(
        listenable: Listenable.merge([account, d]),
        builder: (context, _) {
          final current = currentCustomStatus(_settings, DateTime.now());
          final wide = MediaQuery.sizeOf(context).width >= 760;
          final preview = d.customActivity(_draft, DateTime.now().millisecondsSinceEpoch);
          final active = current == null ? null : d.customActivity(current.status, current.appliedAt);
          Widget card(String label, Widget body, {String? badge}) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Icon(Icons.visibility_rounded, size: 16, color: MF.accent),
                  const SizedBox(width: 6),
                  Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
                  const Spacer(),
                  if (badge != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: MF.accentSoft, borderRadius: BorderRadius.circular(10)),
                      child: Text(badge, style: TextStyle(color: MF.accent, fontSize: 11, fontWeight: FontWeight.w800)),
                    ),
                ]),
                const SizedBox(height: 6),
                body,
              ]);
          final previews = [
            card('Preview', DiscordActivityCard(activity: statusHasContent(_draft) ? preview : null, empty: 'Nothing to show yet'), badge: 'Editing'),
            card('Active', DiscordActivityCard(activity: active),
                badge: current == null ? null : current.source == 'manual' ? 'Applied' : 'Scheduled · ${current.source.substring(9)}'),
          ];
          return DefaultTabController(
            length: 6,
            child: Scaffold(
              appBar: AppBar(
                title: const Text('Custom Status'),
                actions: [
                  IconButton(
                    tooltip: 'Reset the editor',
                    icon: const Icon(Icons.restart_alt_rounded),
                    onPressed: () => _load(blankStatus()),
                  ),
                  IconButton(tooltip: 'Clear the active status', icon: const Icon(Icons.close_rounded), onPressed: current == null ? null : _clear),
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilledButton.icon(onPressed: _apply, icon: const Icon(Icons.check_rounded), label: const Text('Apply Status')),
                  ),
                ],
                bottom: const TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [
                  Tab(icon: Icon(Icons.settings_rounded, size: 18), text: 'Basic'),
                  Tab(icon: Icon(Icons.notes_rounded, size: 18), text: 'Text'),
                  Tab(icon: Icon(Icons.image_rounded, size: 18), text: 'Images'),
                  Tab(icon: Icon(Icons.schedule_rounded, size: 18), text: 'Time'),
                  Tab(icon: Icon(Icons.link_rounded, size: 18), text: 'Buttons'),
                  Tab(icon: Icon(Icons.bookmark_rounded, size: 18), text: 'Profiles'),
                ]),
              ),
              body: Column(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: wide
                      ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Expanded(child: previews[0]),
                          const SizedBox(width: 12),
                          Expanded(child: previews[1]),
                        ])
                      : Column(children: [previews[0], const SizedBox(height: 10), previews[1]]),
                ),
                if (!d.enabled)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text('Discord is off on this device (Settings → Discord). Your status is still saved for your other devices.',
                        style: TextStyle(color: MF.textDim, fontSize: 12)),
                  ),
                Expanded(
                  child: TabBarView(key: ValueKey(_rev), children: [
                    _basic(d),
                    _text(d),
                    _images(d),
                    _time(d),
                    _buttons(d),
                    _profiles(),
                  ]),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }

  // ---- fields ----

  Widget _page(List<Widget> children) => ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 40), children: children);

  Widget _field(String key, String label, {String? help, int maxLength = 128, TextInputType? type}) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: TextFormField(
          initialValue: jsStr(_draft[key]),
          maxLength: maxLength,
          keyboardType: type,
          decoration: InputDecoration(labelText: label, helperText: help, helperMaxLines: 3, counterText: ''),
          onChanged: (v) => _set(key, v),
        ),
      );

  Widget _numberField(String key, String label, {String? help}) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: TextFormField(
          initialValue: jsNum(_draft[key]) > 0 ? '${jsNum(_draft[key]).toInt()}' : '',
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: label, helperText: help, helperMaxLines: 2),
          onChanged: (v) => _set(key, int.tryParse(v.trim()) ?? 0),
        ),
      );

  Widget _dropdown(String key, String label, List<(String, String)> options, {String? help}) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: DropdownButtonFormField<String>(
          initialValue: options.any((o) => o.$1 == _draft[key]) ? _draft[key] as String : options.first.$1,
          isExpanded: true,
          decoration: InputDecoration(labelText: label, helperText: help, helperMaxLines: 2),
          items: [for (final o in options) DropdownMenuItem(value: o.$1, child: Text(o.$2))],
          onChanged: (v) => _set(key, v),
        ),
      );

  Widget _note(String text) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.info_outline_rounded, size: 15, color: MF.textMute),
          const SizedBox(width: 6),
          Expanded(child: Text(text, style: TextStyle(color: MF.textMute, fontSize: 12))),
        ]),
      );

  Widget _basic(DiscordPresence d) => _page([
        _dropdown('type', 'Activity type', const [
          ('playing', 'Playing'),
          ('listening', 'Listening to'),
          ('watching', 'Watching'),
          ('competing', 'Competing in'),
        ]),
        _field('name', 'Activity name', help: 'The main name of your activity (empty: MediaFlow). Placeholders like {title} work.'),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _fromTitle,
            icon: const Icon(Icons.video_library_rounded, size: 18),
            label: const Text('Use a Library title (name, progress and cover)'),
          ),
        ),
        _dropdown('display', 'Status display type', const [
          ('name', 'Name'),
          ('state', 'State'),
          ('details', 'Details'),
        ], help: 'Which text appears in member lists and DMs.'),
        if (d.supportsParty) ...[
          const SizedBox(height: 14),
          const Text('Party', style: TextStyle(fontWeight: FontWeight.w800)),
          Row(children: [
            Expanded(child: _numberField('partyCurrent', 'Current size')),
            const SizedBox(width: 12),
            Expanded(child: _numberField('partyMax', 'Max size')),
          ]),
          _note('Shown next to the state, e.g. "(2 of 4)". Discord only shows a party on Playing.'),
        ],
        const SizedBox(height: 14),
        _note('Placeholders work in every text: {title}, {progress}, {total}, {unit}, {category}, {level}, {streak}, {xp}, {library}… '
            'They follow what you\'re doing in MediaFlow; pieces with nothing to show disappear.'),
      ]);

  Widget _text(DiscordPresence d) => _page([
        _field('details', 'Details', help: 'The first line, e.g. an artist or what you\'re doing.'),
        if (d.supportsLinks) _field('detailsUrl', 'Details link (https://)', maxLength: 512, type: TextInputType.url),
        const SizedBox(height: 8),
        _field('state', 'State', help: 'The second line, e.g. a song or episode.'),
        if (d.supportsLinks) _field('stateUrl', 'State link (https://)', maxLength: 512, type: TextInputType.url),
      ]);

  Widget _images(DiscordPresence d) => _page([
        _field('largeImage', 'Large image (https:// link)', maxLength: 512, type: TextInputType.url,
            help: 'A direct image link, or an asset name if you use a custom application.'),
        _imageTools(large: true),
        _field('largeText', 'Large image text', help: 'Shown when hovering over the large image.'),
        if (d.supportsLinks) _field('largeUrl', 'Large image link (https://)', maxLength: 512, type: TextInputType.url),
        const Divider(height: 32),
        _field('smallImage', 'Small image (https:// link)', maxLength: 512, type: TextInputType.url),
        _imageTools(large: false),
        _field('smallText', 'Small image text'),
        if (d.supportsLinks) _field('smallUrl', 'Small image link (https://)', maxLength: 512, type: TextInputType.url),
        const Divider(height: 32),
        Row(children: [
          const Expanded(child: Text('Image library', style: TextStyle(fontWeight: FontWeight.w800))),
          TextButton.icon(onPressed: () => _openLibrary(), icon: const Icon(Icons.photo_library_rounded, size: 18), label: Text('${_store.images.length} saved')),
        ]),
        _note('Save image links once and pick them for any status. The library is saved in your account, on every device.'),
      ]);

  Widget _imageTools({required bool large}) {
    final key = large ? 'largeImage' : 'smallImage';
    final url = jsStr(_draft[key]);
    return Wrap(spacing: 4, runSpacing: 0, children: [
      TextButton.icon(
        onPressed: () => _setImage(key, DiscordPresence.logoUrl, text: 'MediaFlow'),
        icon: const Icon(Icons.auto_awesome_rounded, size: 18),
        label: const Text('MediaFlow logo'),
      ),
      TextButton.icon(
        onPressed: () => _coverFromLibrary(large: large),
        icon: const Icon(Icons.video_library_rounded, size: 18),
        label: const Text('A title\'s cover'),
      ),
      TextButton.icon(
        onPressed: () => _openLibrary(pickFor: key),
        icon: const Icon(Icons.photo_library_rounded, size: 18),
        label: const Text('From my library'),
      ),
      if (url.startsWith('https://') && !_store.images.any((m) => m['url'] == url))
        TextButton.icon(
          onPressed: () => _saveImage(url),
          icon: const Icon(Icons.bookmark_add_rounded, size: 18),
          label: const Text('Save to library'),
        ),
      if (url.isNotEmpty)
        TextButton.icon(onPressed: () => _setImage(key, ''), icon: const Icon(Icons.clear_rounded, size: 18), label: const Text('Remove')),
    ]);
  }

  void _setImage(String key, String url, {String? text}) {
    final textKey = key == 'largeImage' ? 'largeText' : 'smallText';
    setState(() {
      _draft = normalizeStatus({..._draft, key: url, if (text != null && jsStr(_draft[textKey]).isEmpty) textKey: text});
      _rev++;
    });
    unawaited(_write({'draft': _draft}));
  }

  Future<String?> _askName(String title, String initial) async {
    final c = TextEditingController(text: initial);
    final name = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(title),
        content: TextField(controller: c, autofocus: true, maxLength: 80, decoration: const InputDecoration(labelText: 'Name')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(d, c.text), child: const Text('Save')),
        ],
      ),
    );
    c.dispose();
    return name;
  }

  Future<void> _saveImage(String url) async {
    final name = await _askName('Save image', Uri.tryParse(url)?.pathSegments.lastOrNull ?? 'Image');
    if (name == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    await _write({'images': _store.withImage(url, name, mediaFlowUid(now), now)});
    if (mounted) setState(() {});
    _toast('Saved to your image library ✓');
  }

  /// The image library: search, pick (when [pickFor] is set), rename, delete, add.
  Future<void> _openLibrary({String? pickFor}) async {
    var query = '';
    await showDialog<void>(
      context: context,
      builder: (d) => StatefulBuilder(builder: (d, set) {
        final all = _store.images;
        final q = query.toLowerCase();
        final rows = [for (final m in all) if (q.isEmpty || jsStr(m['name']).toLowerCase().contains(q) || jsStr(m['url']).toLowerCase().contains(q)) m];
        Future<void> save(List<Map<String, dynamic>> list) async {
          await _write({'images': list});
          set(() {});
        }

        return AlertDialog(
          title: Text(pickFor == null ? 'Image library' : 'Pick an image'),
          content: SizedBox(
            width: 480,
            height: 460,
            child: Column(children: [
              TextField(
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Search saved images'),
                onChanged: (v) => set(() => query = v.trim()),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: rows.isEmpty
                    ? Center(child: Text(all.isEmpty ? 'No saved images yet.' : 'Nothing matches.', style: TextStyle(color: MF.textDim)))
                    : ListView.builder(
                        itemCount: rows.length,
                        itemBuilder: (_, i) {
                          final m = rows[i];
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: Image.network(jsStr(m['url']), width: 44, height: 44, fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const SizedBox(width: 44, height: 44, child: Icon(Icons.broken_image_rounded))),
                            ),
                            title: Text(jsStr(m['name']), maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(jsStr(m['url']), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
                            onTap: pickFor == null
                                ? null
                                : () {
                                    Navigator.pop(d);
                                    _setImage(pickFor, jsStr(m['url']), text: jsStr(m['name']));
                                  },
                            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                              IconButton(
                                tooltip: 'Edit',
                                icon: const Icon(Icons.edit_rounded, size: 18),
                                onPressed: () async {
                                  final name = await _askName('Rename image', jsStr(m['name']));
                                  if (name == null) return;
                                  await save([for (final x in all) x['url'] == m['url'] ? {...x, 'name': name.trim().isEmpty ? 'Image' : name.trim()} : x]);
                                },
                              ),
                              IconButton(
                                tooltip: 'Delete',
                                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                                onPressed: () => save([for (final x in all) if (x['url'] != m['url']) x]),
                              ),
                            ]),
                          );
                        },
                      ),
              ),
            ]),
          ),
          actions: [
            TextButton.icon(
              onPressed: () async {
                final c = TextEditingController();
                final url = await showDialog<String>(
                  context: d,
                  builder: (x) => AlertDialog(
                    title: const Text('Add an image link'),
                    content: TextField(controller: c, autofocus: true, decoration: const InputDecoration(labelText: 'https:// link')),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(x), child: const Text('Cancel')),
                      FilledButton(onPressed: () => Navigator.pop(x, c.text.trim()), child: const Text('Next')),
                    ],
                  ),
                );
                c.dispose();
                if (url == null || !url.startsWith('https://')) return;
                await _saveImage(url);
                set(() {});
              },
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add'),
            ),
            TextButton(onPressed: () => Navigator.pop(d), child: const Text('Close')),
          ],
        );
      }),
    );
    if (mounted) setState(() {});
  }

  /// Fills the status from a Library title: its name, progress, category and cover.
  Future<void> _fromTitle() async {
    final view = account.view;
    if (view == null) return;
    final ids = await pickLibraryTitles(context, view, title: 'Use a Library title', single: true);
    if (ids == null || ids.isEmpty) return;
    final t = view.library.where((x) => x.id == ids.first).firstOrNull;
    if (t == null) return;
    final cat = view.category(t.categoryId);
    _load({
      ..._draft,
      'name': t.title,
      'details': t.title,
      'state': '${cat.name} · ${progressText(t, cat)}',
      if (t.coverUrl.startsWith('https://')) 'largeImage': t.coverUrl,
      'largeText': t.title,
      'display': 'details',
    });
    _toast('Filled from ${t.title}');
  }

  Future<void> _coverFromLibrary({required bool large}) async {
    final view = account.view;
    if (view == null) return;
    final ids = await pickLibraryTitles(context, view, title: 'Use a cover', single: true);
    if (ids == null || ids.isEmpty) return;
    final t = view.library.where((x) => x.id == ids.first).firstOrNull;
    if (t == null) return;
    if (!t.coverUrl.startsWith('https://')) {
      _toast('${t.title} has no cover link.');
      return;
    }
    _setImage(large ? 'largeImage' : 'smallImage', t.coverUrl, text: t.title);
  }

  Widget _time(DiscordPresence d) {
    final mode = jsStr(_draft['timeMode']);
    String fmt(int ms) {
      if (ms <= 0) return 'Not set';
      final t = DateTime.fromMillisecondsSinceEpoch(ms);
      String two(int v) => v.toString().padLeft(2, '0');
      return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
    }

    Future<void> pick(String key) async {
      final now = DateTime.now();
      final cur = jsNum(_draft[key]).toInt();
      final base = cur > 0 ? DateTime.fromMillisecondsSinceEpoch(cur) : now;
      final date = await showDatePicker(context: context, initialDate: base, firstDate: DateTime(now.year - 5), lastDate: DateTime(now.year + 5));
      if (date == null || !mounted) return;
      final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(base));
      if (time == null) return;
      _set(key, DateTime(date.year, date.month, date.day, time.hour, time.minute).millisecondsSinceEpoch);
    }

    return _page([
      SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'none', label: Text('No time')),
          ButtonSegment(value: 'absolute', label: Text('Absolute')),
          ButtonSegment(value: 'relative', label: Text('Relative')),
        ],
        selected: {mode},
        onSelectionChanged: (s) => _set('timeMode', s.first),
      ),
      if (mode == 'absolute') ...[
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.hourglass_top_rounded),
          title: const Text('Start time'),
          subtitle: Text('${fmt(jsNum(_draft['start']).toInt())} · when the activity started'),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(icon: const Icon(Icons.edit_calendar_rounded), onPressed: () => pick('start')),
            IconButton(icon: const Icon(Icons.delete_outline_rounded), onPressed: () => _set('start', 0)),
          ]),
        ),
        if (d.supportsEnd)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.hourglass_bottom_rounded),
            title: const Text('End time'),
            subtitle: Text('${fmt(jsNum(_draft['end']).toInt())} · shows a countdown (a progress bar on Listening)'),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(icon: const Icon(Icons.edit_calendar_rounded), onPressed: () => pick('end')),
              IconButton(icon: const Icon(Icons.delete_outline_rounded), onPressed: () => _set('end', 0)),
            ]),
          ),
        _note('An end time in the past ends the status and MediaFlow\'s automatic status comes back.'),
      ],
      if (mode == 'relative') ...[
        _numberField('relStart', 'Started … minutes before applying', help: '0 = starts when you apply it'),
        if (d.supportsEnd) _numberField('relEnd', 'Ends … minutes after applying', help: '0 = no end'),
        _note('Worked out when you press Apply Status (or when a schedule starts).'),
      ],
    ]);
  }

  Widget _buttons(DiscordPresence d) {
    if (!d.supportsButtons) return _page([_note('This build\'s Discord SDK has no buttons.')]);
    final buttons = [for (final b in asList(_draft['buttons']).map(asMap).whereType<Map<String, dynamic>>()) b];
    // Unfinished buttons (no label or link yet) are kept in the editor only.
    return _ButtonsEditor(
      key: ValueKey('b$_rev'),
      initial: buttons,
      onChanged: (list) => _set('buttons', list),
    );
  }

  // ---- profiles ----

  Widget _profiles() {
    final profiles = _store.profiles;
    Future<void> saveProfiles(List<Map<String, dynamic>> list) => _write({'profiles': list});
    return _page([
      Row(children: [
        const Expanded(child: Text('Saved statuses — free, synced to all your devices.', style: TextStyle(fontWeight: FontWeight.w700))),
        FilledButton.tonalIcon(
          onPressed: () async {
            final name = await _ask('Profile name', '');
            if (name == null) return;
            await saveProfiles([
              ...profiles,
              {'id': 'p${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}', 'name': name.isEmpty ? 'Profile' : name, 'status': _draft, 'schedule': normalizeSchedule(null)},
            ]);
          },
          icon: const Icon(Icons.bookmark_add_rounded),
          label: const Text('Save current'),
        ),
      ]),
      if (profiles.isEmpty) _note('Save the status you\'re editing as a profile to reuse it or put it on a schedule.'),
      for (var i = 0; i < profiles.length; i++) _profileCard(profiles, i, saveProfiles),
    ]);
  }

  Widget _profileCard(List<Map<String, dynamic>> profiles, int i, Future<void> Function(List<Map<String, dynamic>>) save) {
    final p = profiles[i];
    final sched = p['schedule'] as Map<String, dynamic>;
    final status = p['status'] as Map<String, dynamic>;
    List<Map<String, dynamic>> replaced(Map<String, dynamic> next) => [for (var j = 0; j < profiles.length; j++) j == i ? next : profiles[j]];
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final activeDays = (sched['days'] as List).cast<int>();
    String scheduleText() {
      if (sched['enabled'] != true) return 'No schedule';
      final when = sched['kind'] == 'once'
          ? (jsStr(sched['date']).isEmpty ? 'pick a date' : jsStr(sched['date']))
          : activeDays.isEmpty
              ? 'Every day'
              : activeDays.map((d) => days[d - 1]).join(', ');
      return '$when · ${sched['from']}–${sched['to']}';
    }

    Future<String?> time(String current) async {
      final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: int.parse(current.substring(0, 2)), minute: int.parse(current.substring(3))));
      return t == null ? null : '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    }

    return Card(
      margin: const EdgeInsets.only(top: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(jsStr(p['name']), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
            TextButton(
              onPressed: () async {
                _load(status);
                await _write({'draft': status, 'active': {...status, 'appliedAt': DateTime.now().millisecondsSinceEpoch}});
                _toast('${p['name']} applied ✓');
              },
              child: const Text('Apply'),
            ),
            PopupMenuButton<String>(
              onSelected: (v) async {
                switch (v) {
                  case 'load':
                    _load(status);
                  case 'update':
                    await save(replaced({...p, 'status': _draft}));
                  case 'rename':
                    final name = await _ask('Profile name', jsStr(p['name']));
                    if (name != null) await save(replaced({...p, 'name': name.isEmpty ? 'Profile' : name}));
                  case 'duplicate':
                    await save([
                      ...profiles,
                      {...p, 'id': 'p${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}', 'name': '${p['name']} copy', 'schedule': normalizeSchedule(null)},
                    ]);
                  case 'delete':
                    await save([for (var j = 0; j < profiles.length; j++) if (j != i) profiles[j]]);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'load', child: Text('Edit in the editor')),
                PopupMenuItem(value: 'update', child: Text('Replace with the editor\'s status')),
                PopupMenuItem(value: 'rename', child: Text('Rename')),
                PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
                PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
          ]),
          Text(
            [jsStr(status['name']), jsStr(status['details']), jsStr(status['state'])].where((x) => x.isNotEmpty).join(' · '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: MF.textDim, fontSize: 12),
          ),
          SwitchListTile(
            contentPadding: const EdgeInsets.only(right: 8),
            dense: true,
            title: const Text('Schedule'),
            subtitle: Text(scheduleText()),
            value: sched['enabled'] == true,
            onChanged: (v) => save(replaced({...p, 'schedule': {...sched, 'enabled': v}})),
          ),
          if (sched['enabled'] == true) ...[
            SegmentedButton<String>(
              segments: const [ButtonSegment(value: 'daily', label: Text('Repeat')), ButtonSegment(value: 'once', label: Text('One day'))],
              selected: {jsStr(sched['kind'])},
              onSelectionChanged: (s) => save(replaced({...p, 'schedule': {...sched, 'kind': s.first}})),
            ),
            const SizedBox(height: 6),
            if (sched['kind'] == 'daily')
              Wrap(spacing: 4, children: [
                for (var d = 1; d <= 7; d++)
                  FilterChip(
                    label: Text(days[d - 1]),
                    selected: activeDays.contains(d),
                    onSelected: (on) => save(replaced({
                      ...p,
                      'schedule': {...sched, 'days': on ? ([...activeDays, d]..sort()) : activeDays.where((x) => x != d).toList()},
                    })),
                  ),
              ])
            else
              TextButton.icon(
                onPressed: () async {
                  final now = DateTime.now();
                  final date = await showDatePicker(context: context, initialDate: now, firstDate: now.subtract(const Duration(days: 1)), lastDate: DateTime(now.year + 3));
                  if (date == null) return;
                  final s = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
                  await save(replaced({...p, 'schedule': {...sched, 'date': s}}));
                },
                icon: const Icon(Icons.event_rounded),
                label: Text(jsStr(sched['date']).isEmpty ? 'Pick a date' : jsStr(sched['date'])),
              ),
            Row(children: [
              TextButton(
                onPressed: () async {
                  final v = await time(jsStr(sched['from']));
                  if (v != null) await save(replaced({...p, 'schedule': {...sched, 'from': v}}));
                },
                child: Text('From ${sched['from']}'),
              ),
              TextButton(
                onPressed: () async {
                  final v = await time(jsStr(sched['to']));
                  if (v != null) await save(replaced({...p, 'schedule': {...sched, 'to': v}}));
                },
                child: Text('Until ${sched['to']}'),
              ),
            ]),
            _note('Runs on whichever of your devices is open with Discord. A status you apply by hand wins over schedules.'),
          ],
        ]),
      ),
    );
  }

  Future<String?> _ask(String title, String initial) {
    final ctl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: TextField(controller: ctl, autofocus: true, maxLength: 60),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, ctl.text.trim()), child: const Text('Save')),
        ],
      ),
    );
  }
}

/// Up to two buttons with text and an https link.
class _ButtonsEditor extends StatefulWidget {
  const _ButtonsEditor({super.key, required this.initial, required this.onChanged});
  final List<Map<String, dynamic>> initial;
  final ValueChanged<List<Map<String, dynamic>>> onChanged;

  @override
  State<_ButtonsEditor> createState() => _ButtonsEditorState();
}

class _ButtonsEditorState extends State<_ButtonsEditor> {
  late final List<(TextEditingController, TextEditingController)> _rows = [
    for (final b in widget.initial) (TextEditingController(text: jsStr(b['label'])), TextEditingController(text: jsStr(b['url']))),
  ];

  void _emit() => widget.onChanged([for (final r in _rows) {'label': r.$1.text.trim(), 'url': r.$2.text.trim()}]);

  @override
  void dispose() {
    for (final r in _rows) {
      r.$1.dispose();
      r.$2.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 40), children: [
      Row(children: [
        const Expanded(child: Text('Buttons', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
        FilledButton.tonalIcon(
          onPressed: _rows.length >= 2 ? null : () => setState(() => _rows.add((TextEditingController(), TextEditingController()))),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Add Button'),
        ),
      ]),
      Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text('Up to 2. Discord only shows buttons to other people, never on your own profile.', style: TextStyle(color: MF.textMute, fontSize: 12)),
      ),
      for (var i = 0; i < _rows.length; i++)
        Card(
          margin: const EdgeInsets.only(top: 12),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 6, 12),
            child: Column(children: [
              Row(children: [
                Expanded(child: Text('Button ${i + 1}', style: const TextStyle(fontWeight: FontWeight.w800))),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded),
                  onPressed: () {
                    setState(() => _rows.removeAt(i));
                    _emit();
                  },
                ),
              ]),
              TextField(
                controller: _rows[i].$1,
                maxLength: 32,
                decoration: const InputDecoration(labelText: 'Button text', helperText: 'Text displayed on the button'),
                onChanged: (_) => _emit(),
              ),
              TextField(
                controller: _rows[i].$2,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(labelText: 'Button URL', helperText: 'Opens when clicked (must start with https://)'),
                onChanged: (_) => _emit(),
              ),
            ]),
          ),
        ),
    ]);
  }
}
