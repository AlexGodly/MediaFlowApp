// Settings → Data & Cloud (website v366 "cloud" category): Full Data Backup,
// Settings Preset, Collections and Personal Order transfers, and Automatic
// Backups. Every file is in the website's format, so the website opens what
// the app saves and the other way round.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../data/account_controller.dart';
import '../data/app_prefs.dart';
import '../logic/collections_logic.dart' show orderExport, orderImport;
import '../logic/data_transfer.dart';
import '../logic/exchange_import.dart';
import '../platform/auto_backup.dart';
import '../platform/file_io.dart';
import '../state/models.dart';
import '../util/js.dart';
import 'theme.dart';
import 'widgets.dart';

void _toast(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), behavior: SnackBarBehavior.floating));

String _when(DateTime d) {
  String z(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${z(d.month)}-${z(d.day)} ${z(d.hour)}:${z(d.minute)}';
}

String _pretty(Object data) => const JsonEncoder.withIndent('  ').convert(data);

Future<bool> _confirm(BuildContext context, String title, String body, String action, {bool danger = false}) async =>
    await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          FilledButton(
            style: danger ? FilledButton.styleFrom(backgroundColor: MF.bad) : null,
            onPressed: () => Navigator.pop(d, true),
            child: Text(action),
          ),
        ],
      ),
    ) ==
    true;

Future<Object?> _readJson(BuildContext context) async {
  final f = await pickTextFile();
  if (f == null) return null;
  try {
    return jsonDecode(f.text);
  } catch (_) {
    if (context.mounted) _toast(context, '${f.name} is not a JSON file.');
    return null;
  }
}

/// Collections → Import (website v281 format).
Future<void> importCollectionsFile(BuildContext context, AccountController account) async {
  final data = await _readJson(context);
  if (data == null || !context.mounted) return;
  final file = readCollectionsFile(data);
  if (file.error != null) return _toast(context, file.error!);
  final ok = await _confirm(
    context,
    'Import Collections data?',
    'Merge ${fmtNumber(file.rows.length)} collection${file.rows.length == 1 ? '' : 's'} with your current Collections.'
        '${file.deleted.isNotEmpty ? ' This file also has ${fmtNumber(file.deleted.length)} deletion marker${file.deleted.length == 1 ? '' : 's'}; they can remove older matching collections but never a newer edited copy.' : ''}'
        '${file.hasSettings ? ' Collection display and filter settings from this export are applied too.' : ''}',
    'Import collections',
  );
  if (!ok) return;
  ({int imported, int removed, int skipped})? r;
  await account.edit((copy, now) => r = importCollections(copy, data, now, () => mediaFlowUid(now)), label: 'Import Collections');
  if (!context.mounted || r == null) return;
  _toast(context,
      '${fmtNumber(r!.imported)} collections imported · ${fmtNumber(r!.removed)} older collections removed${r!.skipped > 0 ? ' · ${fmtNumber(r!.skipped)} older copies skipped' : ''}');
}


/// Collections → Export (website v281 format).
Future<void> exportCollectionsFile(BuildContext context, AccountController account) async {
  final view = account.view;
  if (view == null) return;
  final now = DateTime.now();
  final path = await saveTextFile(collectionsFileName(now), _pretty(buildCollectionsExport(view.state, now)));
  if (path != null && context.mounted) {
    _toast(context, '${fmtNumber(asList(view.state['collections']).length)} collections exported ✓');
    await account.actionXp('data', 'export', 'Export · Collections');
  }
}

class DataCloudSection extends StatelessWidget {
  const DataCloudSection({super.key, required this.account, required this.view});
  final AccountController account;
  final AccountView view;

  Future<void> _save(BuildContext context, String name, Object data, String done) async {
    final path = await saveTextFile(name, _pretty(data));
    if (!context.mounted) return;
    if (path != null) {
      _toast(context, '$done ✓');
      await account.actionXp('data', 'export', 'Export · $name');
    }
  }

  Future<void> _exportBackup(BuildContext context) {
    final now = DateTime.now();
    final data = buildFullBackup(view.state, now, appVersion: kAppVersionLabel);
    final c = asMap(asMap(data['backupManifest'])?['counts'])!;
    return _save(context, backupFileName(now), data,
        'Complete backup · ${fmtNumber(jsNum(c['libraryTitles']))} titles · ${fmtNumber(jsNum(c['historyLogs']))} logs');
  }

  Future<void> _importBackup(BuildContext context) async {
    final data = await _readJson(context);
    if (data == null || !context.mounted) return;
    final error = validateBackup(data);
    if (error != null) return _toast(context, error);
    final d = asMap(data)!;
    final s = backupSummary(d);
    final ok = await _confirm(
      context,
      'Restore this backup?',
      'It has ${fmtNumber(s.titles)} titles, ${fmtNumber(s.logs)} History logs and ${fmtNumber(s.collections)} collections'
          '${s.version.isEmpty ? '' : ' (MediaFlow v${s.version})'}.\n\n'
          'Everything in the backup replaces what your account has now. A safety backup of your current account is saved first.',
      'Restore backup',
      danger: true,
    );
    if (!ok || !context.mounted) return;
    // Safety copy of the current account before anything is replaced.
    try {
      final dir = await AutoBackup.folder();
      await dir.create(recursive: true);
      final now = DateTime.now();
      await File('${dir.path}${Platform.pathSeparator}before-restore-${autoBackupFileName(now)}')
          .writeAsString(_pretty(buildFullBackup(view.state, now, appVersion: kAppVersionLabel)), flush: true);
    } catch (_) {
      if (!context.mounted) return;
      final go = await _confirm(context, 'No safety backup', 'MediaFlow could not save a safety backup of your current account. Restore anyway?',
          'Restore anyway', danger: true);
      if (!go) return;
    }
    await account.edit((copy, now) => applyFullBackup(copy, d), label: 'Restore Full Data Backup', undoable: false);
    if (context.mounted) _toast(context, 'Backup restored: ${fmtNumber(s.titles)} titles · ${fmtNumber(s.logs)} logs ✓');
  }

  Future<void> _importPreset(BuildContext context) async {
    final data = await _readJson(context);
    if (data == null || !context.mounted) return;
    final error = validateSettingsPreset(data);
    if (error != null) return _toast(context, error);
    final ok = await _confirm(context, 'Import Settings Preset?',
        'Your settings and category configuration are replaced by the preset. Your Library, History and XP are not changed.', 'Import preset');
    if (!ok) return;
    await account.edit((copy, now) => applySettingsPreset(copy, asMap(data)!), label: 'Import Settings Preset');
    if (context.mounted) _toast(context, 'Settings Preset imported ✓');
  }

  Future<void> _importCollections(BuildContext context) => importCollectionsFile(context, account);

  Future<void> _importOrder(BuildContext context) async {
    final data = await _readJson(context);
    if (data == null || !context.mounted) return;
    ({int imported, int skipped, String? error})? r;
    await account.edit((s, now) => r = orderImport(s, data, now), label: 'Import Personal Order');
    if (!context.mounted || r == null) return;
    _toast(context, r!.error ?? 'Order imported: ${r!.imported} title${r!.imported == 1 ? '' : 's'}${r!.skipped > 0 ? ' · ${r!.skipped} unmatched skipped' : ''} ✓');
  }

  Widget _row(BuildContext context, IconData icon, String title, String subtitle, List<Widget> actions) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 20, color: MF.accent),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800))),
          ]),
          const SizedBox(height: 2),
          Text(subtitle, style: TextStyle(color: MF.textDim, fontSize: 12)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 8, children: actions),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _row(context, Icons.inventory_2_rounded, 'Full Data Backup',
          'Everything in your account: Library, History, Collections, Personal Order, XP and settings. Opens on the website too.', [
        FilledButton.tonalIcon(onPressed: () => _exportBackup(context), icon: const Icon(Icons.download_rounded, size: 18), label: const Text('Export')),
        OutlinedButton.icon(onPressed: () => _importBackup(context), icon: const Icon(Icons.upload_rounded, size: 18), label: const Text('Import')),
      ]),
      _row(context, Icons.tune_rounded, 'Settings Preset', 'Configuration only: settings and categories. No Library, History or XP.', [
        FilledButton.tonalIcon(
          onPressed: () => _save(context, presetFileName(now), buildSettingsPreset(view.state, now), 'Settings Preset exported'),
          icon: const Icon(Icons.download_rounded, size: 18),
          label: const Text('Export'),
        ),
        OutlinedButton.icon(onPressed: () => _importPreset(context), icon: const Icon(Icons.upload_rounded, size: 18), label: const Text('Import')),
      ]),
      _row(context, Icons.collections_bookmark_rounded, 'Collections', 'Your Collections, their deletion markers and display settings.', [
        FilledButton.tonalIcon(
          onPressed: () => _save(context, collectionsFileName(now), buildCollectionsExport(view.state, now),
              '${fmtNumber(asList(view.state['collections']).length)} collections exported'),
          icon: const Icon(Icons.download_rounded, size: 18),
          label: const Text('Export'),
        ),
        OutlinedButton.icon(onPressed: () => _importCollections(context), icon: const Icon(Icons.upload_rounded, size: 18), label: const Text('Import')),
      ]),
      _row(context, Icons.format_list_numbered_rounded, 'Personal Order', 'Your Order, its queues and category display.', [
        FilledButton.tonalIcon(
          onPressed: () {
            final ids = asList(asMap(view.state['orderPlan'])?['titleIds']);
            if (ids.isEmpty) return _toast(context, 'Your Order is empty.');
            final d = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
            _save(context, 'MediaFlow_Order_$d.json', orderExport(Map<String, dynamic>.of(view.state), now), '${ids.length} ordered titles exported');
          },
          icon: const Icon(Icons.download_rounded, size: 18),
          label: const Text('Export'),
        ),
        OutlinedButton.icon(onPressed: () => _importOrder(context), icon: const Icon(Icons.upload_rounded, size: 18), label: const Text('Import')),
      ]),
      _ExchangeTools(account: account, view: view),
      const Divider(height: 24),
      _AutoBackupEditor(account: account, view: view),
    ]);
  }
}

class _AutoBackupEditor extends StatefulWidget {
  const _AutoBackupEditor({required this.account, required this.view});
  final AccountController account;
  final AccountView view;

  @override
  State<_AutoBackupEditor> createState() => _AutoBackupEditorState();
}

class _AutoBackupEditorState extends State<_AutoBackupEditor> {
  String? _folder;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadFolder();
  }

  Future<void> _loadFolder() async {
    final d = await AutoBackup.folder();
    if (mounted) setState(() => _folder = d.path);
  }

  Future<void> _set(String key, Object value) => widget.account.setSetting(['backup', key], value);

  static const _intervals = [(5, '5 minutes'), (15, '15 minutes'), (30, '30 minutes'), (60, '1 hour'), (360, '6 hours'), (1440, 'Daily')];

  @override
  Widget build(BuildContext context) {
    final p = AutoBackup.prefs(asMap(widget.view.state['settings']));
    final interval = AutoBackup.intervalMinutes(p);
    final last = jsNum(p['lastBackup']).toInt();
    final desktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Icon(Icons.backup_rounded, size: 20, color: MF.accent),
        const SizedBox(width: 8),
        const Expanded(child: Text('Automatic Backups', style: TextStyle(fontWeight: FontWeight.w800))),
      ]),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: p['enabled'] == true,
        onChanged: (v) => _set('enabled', v),
        title: const Text('Automatic local JSON backup'),
        subtitle: const Text('While MediaFlow is open, it writes a Full Data Backup to the backup folder on this device. '
            'The schedule is shared with the website; the folder belongs to each device.'),
      ),
      Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        const Text('Back up every'),
        CompactDropdown<int>(
          value: _intervals.any((x) => x.$1 == interval) ? interval : 60,
          items: _intervals,
          onChanged: (v) => _set('interval', v),
        ),
        const Text('File mode'),
        CompactDropdown<String>(
          value: p['mode'] == 'multiple' ? 'multiple' : 'single',
          items: const [('single', 'One file (overwrite)'), ('multiple', 'Multiple files')],
          onChanged: (v) => _set('mode', v),
        ),
      ]),
      if (p['mode'] != 'multiple')
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: TextFormField(
            key: ValueKey('bk-${p['fileName']}'),
            initialValue: jsStr(p['fileName']),
            decoration: const InputDecoration(labelText: 'Single-file name'),
            onFieldSubmitted: (v) => _set('fileName', v.trim().isEmpty ? 'mediaflow-backup.json' : v.trim()),
          ),
        ),
      const SizedBox(height: 8),
      Text('Folder: ${_folder ?? '…'}', style: TextStyle(color: MF.textDim, fontSize: 12)),
      Text(last <= 0 ? 'No backup yet' : 'Last backup ${_when(DateTime.fromMillisecondsSinceEpoch(last))}',
          style: TextStyle(color: MF.textDim, fontSize: 12)),
      if (AutoBackup.instance.lastError != null)
        Text('Last attempt failed: ${AutoBackup.instance.lastError}', style: TextStyle(color: MF.bad, fontSize: 12)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        FilledButton.tonalIcon(
          onPressed: _busy
              ? null
              : () async {
                  setState(() => _busy = true);
                  final path = await AutoBackup.instance.saveNow(manual: true);
                  if (!mounted) return;
                  setState(() => _busy = false);
                  _toast(context, path == null ? 'Backup could not be written. Choose another folder if needed.' : 'Backup saved ✓');
                },
          icon: const Icon(Icons.save_alt_rounded, size: 18),
          label: const Text('Back up now'),
        ),
        if (desktop || Platform.isAndroid)
          OutlinedButton.icon(
            onPressed: () async {
              final dir = await pickFolder();
              if (dir == null) return;
              await AppPrefs.instance.set('autoBackupFolder', dir);
              await _loadFolder();
            },
            icon: const Icon(Icons.folder_open_rounded, size: 18),
            label: const Text('Choose backup folder'),
          ),
        if (AppPrefs.instance.get<String>('autoBackupFolder', '').isNotEmpty)
          TextButton(
            onPressed: () async {
              await AppPrefs.instance.set('autoBackupFolder', '');
              await _loadFolder();
            },
            child: const Text('Use the default folder'),
          ),
        if (desktop && _folder != null)
          TextButton(
            onPressed: () async {
              await Directory(_folder!).create(recursive: true);
              await launchUrl(Uri.file(_folder!));
            },
            child: const Text('Open folder'),
          ),
      ]),
      if (Platform.isIOS)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text('Find backups in the Files app → On My iPhone → MediaFlow → MediaFlow Backups.', style: TextStyle(color: MF.textDim, fontSize: 12)),
        ),
    ]);
  }
}

/// Import from / export for other services (website Exchange Hub + Advanced
/// Import's "one category" mode).
class _ExchangeTools extends StatefulWidget {
  const _ExchangeTools({required this.account, required this.view});
  final AccountController account;
  final AccountView view;

  @override
  State<_ExchangeTools> createState() => _ExchangeToolsState();
}

class _ExchangeToolsState extends State<_ExchangeTools> {
  String _service = 'malxml';
  String _into = ''; // '' = MediaFlow decides the category
  bool _busy = false;

  Future<void> _import() async {
    final f = await pickTextFile(extensions: const ['json', 'xml', 'csv', 'txt']);
    if (f == null || !mounted) return;
    List<dynamic> records;
    Object? json;
    try {
      final isXml = f.name.toLowerCase().endsWith('.xml') || RegExp(r'^\s*<').hasMatch(f.text);
      final isCsv = !isXml && (f.name.toLowerCase().endsWith('.csv') || (!f.name.toLowerCase().endsWith('.json') && f.text.contains(',') && !RegExp(r'^\s*[\[{]').hasMatch(f.text)));
      if (!isXml && !isCsv) json = jsonDecode(f.text);
      records = isXml ? xmlRecords(f.text) : (isCsv ? csvRecords(f.text) : flattenJson(json));
    } catch (_) {
      return _toast(context, 'MediaFlow could not understand ${f.name}.');
    }
    final simkl = _service == 'simkl' && isSimklBackup(json);
    if (_service == 'simkl' && json != null && !simkl) return _toast(context, 'This does not look like a Simkl JSON backup.');
    if (records.isEmpty) return _toast(context, 'No recognizable media records were found.');
    final into = _into.isEmpty ? null : _into;
    final ok = await _confirm(
      context,
      'Import ${f.name}?',
      '${fmtNumber(records.length)} records from ${serviceName(_service)}. Recognized titles are merged into your Library: matching entries are '
          'updated before new titles are created, and missing fields are not made up.'
          '${into == null ? '' : ' Every title goes to ${widget.view.category(into).name}.'}'
          '${simkl ? ' Simkl\'s watched dates are added to History too.' : ''}',
      'Import data',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    ImportResult? r;
    await widget.account.edit((copy, now) {
      var k = 0;
      String uid() => mediaFlowUid(now + k++);
      r = mergeImportRecords(copy, records, _service, now: now, uid: uid, intoCategory: into);
      if (simkl) r!.historyAdded = addSimklHistory(copy, asMap(json)!, uid: uid);
    }, label: '${serviceName(_service)} import', undoable: false);
    if (!mounted) return;
    setState(() => _busy = false);
    _toast(context, '${serviceName(_service)} import complete · ${r?.summary ?? ''}');
  }

  Future<void> _export() async {
    final out = exchangeExport(widget.view.state, _service, DateTime.now());
    final path = await saveTextFile(out.name, out.content);
    if (path != null && mounted) {
      _toast(context, 'Exported for ${serviceName(_service)} ✓');
      await widget.account.actionXp('data', 'export', 'Export · ${serviceName(_service)}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.swap_horiz_rounded, size: 20, color: MF.accent),
          const SizedBox(width: 8),
          const Expanded(child: Text('Other services', style: TextStyle(fontWeight: FontWeight.w800))),
        ]),
        const SizedBox(height: 2),
        Text('MyAnimeList XML, Simkl (with watched History), AniList, Letterboxd, Trakt, TV Time and more, or any CSV / JSON. '
            'Dates, covers, IDs, seasons and details are kept when the file has them.',
            style: TextStyle(color: MF.textDim, fontSize: 12)),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          CompactDropdown<String>(value: _service, items: kExchangeServices, onChanged: (v) => setState(() => _service = v), maxWidth: 200),
          CompactDropdown<String>(
            value: widget.view.categories.any((c) => c.id == _into) ? _into : '',
            items: [('', 'Category: MediaFlow decides'), for (final c in widget.view.categories) (c.id, 'Into ${c.name}')],
            onChanged: (v) => setState(() => _into = v),
            maxWidth: 230,
          ),
          FilledButton.tonalIcon(
            onPressed: _busy ? null : _import,
            icon: _busy
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.upload_rounded, size: 18),
            label: const Text('Import'),
          ),
          OutlinedButton.icon(onPressed: _export, icon: const Icon(Icons.download_rounded, size: 18), label: const Text('Export')),
        ]),
      ]),
    );
  }
}
