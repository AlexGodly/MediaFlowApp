// ignore_for_file: prefer_interpolation_to_compose_strings
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'cloud/mediaflow_cloud.dart';
import 'logging/log_draft.dart';

const _ink = Color(0xFF0C1019);
const _surface = Color(0xFF171F2B);
const _accent = Color(0xFFF0B85D);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const url = String.fromEnvironment('SUPABASE_URL',
    defaultValue: 'https://wgeijxfdpgehesxialxm.supabase.co');
  const key = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'sb_publishable_d2P0qZlvGZOSqcUzEg3BNg_3wQsHY_M');
  if (url.isEmpty || key.isEmpty) {
    runApp(const MaterialApp(home: Scaffold(body: Center(
      child: Text('Configure MediaFlow public Supabase URL and key.')))));
    return;
  }
  await Supabase.initialize(url: url, publishableKey: key);
  runApp(const FreshMediaFlowApp());
}

class FreshMediaFlowApp extends StatefulWidget {
  const FreshMediaFlowApp({super.key});
  @override
  State<FreshMediaFlowApp> createState() => _FreshMediaFlowAppState();
}

class _FreshMediaFlowAppState extends State<FreshMediaFlowApp> {
  StreamSubscription<AuthState>? _changes;
  @override
  void initState() {
    super.initState();
    _changes = Supabase.instance.client.auth.onAuthStateChange.listen((state) {
      if (mounted) setState(() {});
    });
  }
  @override
  void dispose() {
    _changes?.cancel();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    final client = Supabase.instance.client;
    final owner = client.auth.currentUser?.id;
    final theme = ThemeData(
      useMaterial3: true, brightness: Brightness.dark,
      scaffoldBackgroundColor: _ink,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _accent, brightness: Brightness.dark,
        surface: _surface, primary: _accent),
      appBarTheme: const AppBarTheme(
        backgroundColor: _ink, elevation: 0,
        scrolledUnderElevation: 0),
      cardTheme: CardThemeData(
        color: _surface, margin: const EdgeInsets.only(bottom: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
      inputDecorationTheme: InputDecorationTheme(
        filled: true, fillColor: const Color(0xFF101722),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
    );
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'MediaFlow',
      theme: theme,
      home: owner == null
        ? SignInPage(client: client)
        : LoggingPage(key: ValueKey(owner), client: client, ownerId: owner),
    );
  }
}

class SignInPage extends StatefulWidget {
  const SignInPage({super.key, required this.client});
  final SupabaseClient client;
  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  final email = TextEditingController();
  final password = TextEditingController();
  bool loading = false, showPassword = false;
  String? error;

  @override
  void dispose() {
    email.dispose(); password.dispose(); super.dispose();
  }

  Future<void> connect() async {
    if (loading) return;
    if (email.text.trim().isEmpty || password.text.isEmpty) {
      setState(() => error = 'Enter your MediaFlow account email and password.');
      return;
    }
    setState(() { loading = true; error = null; });
    try {
      await widget.client.auth.signInWithPassword(
        email: email.text.trim(), password: password.text);
    } on AuthException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) setState(() => error = 'Connection failed. Check your network and retry.');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(22),
        child: Card(child: Padding(padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Icon(Icons.auto_stories_outlined, color: _accent, size: 44),
            const SizedBox(height: 15),
            Text('MEDIAFLOW', textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                letterSpacing: 2.1, fontWeight: FontWeight.w800)),
            const SizedBox(height: 5),
            const Text('Cloud connection · Logging',
              textAlign: TextAlign.center),
            const SizedBox(height: 25),
            TextField(
              key: const Key('signin-email'),
              controller: email, keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(
                labelText: 'Email', prefixIcon: Icon(Icons.alternate_email))),
            const SizedBox(height: 12),
            TextField(
              key: const Key('signin-password'),
              controller: password, obscureText: !showPassword,
              onSubmitted: (_) => connect(),
              autofillHints: const [AutofillHints.password],
              decoration: InputDecoration(
                labelText: 'Password', prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(showPassword ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => showPassword = !showPassword)))),
            const SizedBox(height: 16),
            if (error != null) ...[
              Text(error!, style: const TextStyle(color: Colors.orangeAccent)),
              const SizedBox(height: 10),
            ],
            FilledButton.icon(
              key: const Key('signin-submit'),
              onPressed: loading ? null : connect,
              icon: loading
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.cloud_done_outlined),
              label: Text(loading ? 'Connecting…' : 'Connect to MediaFlow Cloud')),
            const SizedBox(height: 15),
            Text('Uses your existing account. No new library or database is created.',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center),
          ])))))),
    ));
}

class LoggingPage extends StatefulWidget {
  const LoggingPage({
    super.key, required this.client, required this.ownerId,
  });
  final SupabaseClient client;
  final String ownerId;
  @override
  State<LoggingPage> createState() => _LoggingPageState();
}

class _LoggingPageState extends State<LoggingPage> {
  final draft = LoggingDraftController();
  MediaFlowCloudSnapshot? snapshot;
  String? error;
  bool loading = false;
  String search = '', category = 'all';
  int page = 0, unitPage = 0;
  static const pageSize = 18;

  @override
  void initState() {
    super.initState();
    unawaited(load());
  }
  @override
  void dispose() { draft.dispose(); super.dispose(); }

  Future<void> load() async {
    if (loading) return;
    setState(() {loading = true; error = null;});
    try {
      final next = await MediaFlowCloudReader(widget.client).load();
      if (next.ownerId != widget.ownerId) {
        throw StateError('Account changed. Refusing to display a different Library.');
      }
      if (mounted) setState(() {snapshot = next; loading = false; page = 0;});
    } catch (e) {
      if (mounted) setState(() {error = e.toString(); loading = false;});
      // Crucial: retain last successful snapshot; never show fake empty account.
    }
  }

  Future<void> signOut() async {
    draft.clear();
    try {
      await widget.client.auth.signOut();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not sign out. Try again.')));
      }
    }
  }

  Widget titleArt(CloudTitle title, {double height = 58}) {
    final uri = Uri.tryParse(title.coverUrl);
    final safe = uri != null && uri.scheme == 'https' &&
        uri.host.isNotEmpty && uri.userInfo.isEmpty;
    Widget fallback() => const Center(child: Icon(Icons.menu_book_outlined,
      color: _accent, size: 26));
    return ClipRRect(borderRadius: BorderRadius.circular(10),
      child: Container(
        width: height * .72, height: height,
        color: const Color(0xFF293143),
        child: safe ? Image.network(title.coverUrl, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => fallback()) : fallback()));
  }

  Widget libraryPicker(MediaFlowCloudSnapshot data) {
    final matches = data.library.where((t) =>
      (search.isEmpty ||
        t.title.toLowerCase().contains(search.toLowerCase())) &&
      (category == 'all' || t.categoryId == category)).toList();
    final totalPages = (matches.length / pageSize).ceil().clamp(1, 10000000).toInt();
    final current = page.clamp(0, totalPages - 1).toInt();
    final displayed = matches.skip(current * pageSize).take(pageSize).toList();
    return Card(child: Padding(padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('YOUR LIBRARY', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        Text('${data.library.length} cloud titles · ${matches.length} matching',
          style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 14),
        TextField(
          key: const Key('library-search'),
          onChanged: (q) => setState(() {search = q; page = 0;}),
          decoration: const InputDecoration(
            hintText: 'Search a title…',
            prefixIcon: Icon(Icons.search), isDense: true)),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          key: const Key('category-filter'),
          initialValue: category, isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Category', isDense: true),
          items: [
            const DropdownMenuItem(value: 'all', child: Text('All categories')),
            for (final c in data.categories.entries)
              DropdownMenuItem(value: c.key, child: Text(c.value,
                overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (value) =>
            setState(() {category = value ?? 'all'; page = 0;})),
        const SizedBox(height: 12),
        for (final t in displayed)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: titleArt(t),
            title: Text(t.title, maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Text('${data.categories[t.categoryId] ?? 'Category'} · '
              '${t.progress}/${t.total ?? '?'} · ${t.status}',
              maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: IconButton(
              tooltip: draft.includes(t.id) ? 'Added to draft' : 'Add title',
              onPressed: draft.includes(t.id) ? null : () {
                if (data.library.where((other) => other.id == t.id).length != 1) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Duplicate Library ID; selection blocked.')));
                  return;
                }
                draft.add(t);
              },
              icon: Icon(draft.includes(t.id)
                ? Icons.check_circle_outline : Icons.add_circle_outline))),
        if (displayed.isEmpty) const Padding(
          padding: EdgeInsets.all(18),
          child: Text('No matching Library titles.')),
        if (totalPages > 1)
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            IconButton(onPressed: current == 0 ? null :
                () => setState(() => page = current - 1),
              icon: const Icon(Icons.chevron_left)),
            Text('${current + 1} / $totalPages'),
            IconButton(onPressed: current == totalPages - 1 ? null :
                () => setState(() => page = current + 1),
              icon: const Icon(Icons.chevron_right)),
          ]),
      ])));
  }

  Future<void> changeTime(TitleLogDraft entry) async {
    final date = await showDatePicker(
      context: context, initialDate: entry.consumedAt,
      firstDate: DateTime(2000), lastDate: DateTime(2100));
    if (date == null || !mounted) return;
    final clock = await showTimePicker(
      context: context, initialTime: TimeOfDay.fromDateTime(entry.consumedAt));
    if (clock == null) return;
    draft.edit(entry.title.id, (value) => value.consumedAt =
      DateTime(date.year, date.month, date.day, clock.hour, clock.minute));
  }

  Widget entryEditor(TitleLogDraft entry) {
    final title = entry.title;
    final maximum = entry.maximum;
    final unitRangeStart = entry.base + unitPage * 20 + 1;
    final unitRangeEnd = (unitRangeStart + 19)
        .clamp(unitRangeStart, entry.base + maximum).toInt();
    return Card(child: Padding(padding: const EdgeInsets.all(15),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          titleArt(title, height: 72),
          const SizedBox(width: 11),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title.title, style: Theme.of(context).textTheme.titleMedium,
                maxLines: 2, overflow: TextOverflow.ellipsis),
              Text('${entry.quantity} selected · '
                'saved ${title.progress}/${title.total ?? '?'}',
                style: Theme.of(context).textTheme.bodySmall),
            ])),
          IconButton(onPressed: () => draft.remove(title.id),
            tooltip: 'Remove', icon: const Icon(Icons.close)),
        ]),
        const SizedBox(height: 12),
        SingleChildScrollView(scrollDirection: Axis.horizontal,
          child: SegmentedButton<LoggingMethod>(
            key: ValueKey('method-${title.id}'),
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: LoggingMethod.perUnit,
                label: Text('Per Unit')),
              ButtonSegment(value: LoggingMethod.lastUnit,
                label: Text('Last Unit')),
              ButtonSegment(value: LoggingMethod.amount,
                label: Text('Amount')),
            ],
            selected: {entry.method},
            onSelectionChanged: (value) => draft.edit(title.id,
              (row) => row.method = value.first))),
        if (title.seasons.isNotEmpty) ...[
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: entry.seasonId,
            key: ValueKey('season-${title.id}'),
            decoration: const InputDecoration(
              labelText: 'Season', isDense: true),
            items: [
              const DropdownMenuItem(value: '', child: Text('Entire title')),
              for (final season in title.seasons)
                DropdownMenuItem(value: season.id,
                  child: Text(season.name)),
            ],
            onChanged: (value) => draft.edit(title.id, (row) {
              row.seasonId = value ?? '';
              unitPage = 0;
            })),
        ],
        const SizedBox(height: 11),
        if (entry.method == LoggingMethod.perUnit) ...[
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (var unit = unitRangeStart;
                unit <= unitRangeEnd && maximum > 0; unit++)
              FilterChip(
                label: Text('$unit'),
                selected: entry.selected.containsKey(unit),
                onSelected: (_) =>
                  draft.edit(title.id, (row) => row.toggle(unit))),
          ]),
          if (maximum > 20)
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              IconButton(
                onPressed: unitPage == 0 ? null :
                    () => setState(() => unitPage--),
                icon: const Icon(Icons.chevron_left)),
              Text('Unit page ${unitPage + 1}'),
              IconButton(
                onPressed: (unitPage + 1) * 20 >= maximum ? null :
                    () => setState(() => unitPage++),
                icon: const Icon(Icons.chevron_right)),
            ]),
        ] else ...[
          Text(entry.method == LoggingMethod.lastUnit
            ? 'Last watched / read unit' : 'Amount consumed'),
          Row(children: [
            IconButton(
              key: ValueKey('decrease-${title.id}'),
              onPressed: entry.selectedQuantity == 0 ? null : () => draft.edit(
                title.id, (row) => row.setQuantity(row.selectedQuantity - 1)),
              icon: const Icon(Icons.remove_circle_outline)),
            Text(entry.method == LoggingMethod.lastUnit
              ? '${entry.base + entry.selectedQuantity}'
              : '${entry.selectedQuantity}',
              style: Theme.of(context).textTheme.titleLarge),
            IconButton(
              key: ValueKey('increase-${title.id}'),
              onPressed: entry.selectedQuantity >= maximum ? null : () => draft.edit(
                title.id, (row) => row.setQuantity(row.selectedQuantity + 1)),
              icon: const Icon(Icons.add_circle_outline)),
          ]),
        ],
        const SizedBox(height: 10),
        Text('Progress preview: ${title.progress} → ${entry.projectedProgress} '
            '· ${entry.quantity} consumed'),
        const SizedBox(height: 5),
        LinearProgressIndicator(
          value: title.total == null || title.total == 0 ? null :
            (entry.projectedProgress / title.total!).clamp(0.0, 1.0).toDouble()),
        const SizedBox(height: 9),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Repeat / rewatch'),
          value: entry.repeat,
          onChanged: (value) => draft.edit(title.id, (row) {
            row.repeat = value;
            row.setQuantity(0);
          })),
        TextButton.icon(
          onPressed: () => changeTime(entry),
          icon: const Icon(Icons.event_outlined),
          label: Text('When consumed · ${entry.consumedAt.toLocal().toString().substring(0, 16)}')),
        TextFormField(
          key: ValueKey('note-${title.id}'),
          initialValue: entry.note,
          onChanged: (value) => entry.note = value,
          decoration: const InputDecoration(
            hintText: 'Optional note', isDense: true),
          maxLines: 2),
      ])));
  }

  void showReview() {
    if (draft.units == 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Select an episode, chapter, or consumed amount first.')));
      return;
    }
    showModalBottomSheet<void>(
      context: context, isScrollControlled: true,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: FractionallySizedBox(heightFactor: .72,
          child: Padding(padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Review Logging', style: Theme.of(sheet).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text('${draft.length} titles · ${draft.units} selected units'),
              const SizedBox(height: 14),
              Expanded(child: ListView(children: [
                for (final entry in draft.titles)
                  ListTile(title: Text(entry.title.title),
                    subtitle: Text('${entry.quantity} units · '
                      '${entry.method.name}')),
              ])),
              const Card(color: Color(0xFF493721), child: Padding(
                padding: EdgeInsets.all(12),
                child: Text('Cloud submission is not enabled in this fresh '
                  'foundation. No Library progress or History was saved. '
                  'A verified atomic logging transaction is required first.'))),
              FilledButton(
                onPressed: () => Navigator.pop(sheet),
                child: const Text('Return to draft')),
            ])))));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Row(mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_stories_outlined, color: _accent),
          SizedBox(width: 10),
          Text('MediaFlow', style: TextStyle(fontWeight: FontWeight.w800)),
        ]), actions: [
          IconButton(
            tooltip: 'Refresh cloud Library',
            onPressed: loading ? null : load,
            icon: const Icon(Icons.cloud_sync_outlined)),
          IconButton(
            tooltip: 'Sign out',
            onPressed: signOut,
            icon: const Icon(Icons.logout)),
        ]),
      body: AnimatedBuilder(
        animation: draft,
        builder: (context, _) => LayoutBuilder(
          builder: (context, size) {
            final wide = size.maxWidth >= 1000;
            final data = snapshot;
            final library = data == null
              ? const <Widget>[]
              : <Widget>[libraryPicker(data)];
            final work = <Widget>[
              Card(child: Padding(padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('ADVANCED LOGGING', style:
                      Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 5),
                    Text('${draft.length} titles · ${draft.units} units in draft'),
                    const SizedBox(height: 10),
                    const Text('Only cloud connection and Logging are included '
                      'in this fresh app.'),
                  ]))),
              if (draft.length == 0) const Card(child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Select a Library title to start logging.')))
              else ...[
                for (final entry in draft.titles) entryEditor(entry),
                FilledButton.icon(
                  key: const Key('review-logging'),
                  onPressed: showReview,
                  icon: const Icon(Icons.fact_check_outlined),
                  label: const Text('Review Logging draft')),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: draft.clear,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Clear draft')),
              ],
            ];
            return ListView(padding: EdgeInsets.symmetric(
              horizontal: size.maxWidth < 450 ? 10 : 20, vertical: 12),
              children: [
                Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Logging', style:
                        Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w800)),
                      Text(widget.client.auth.currentUser?.email ?? 'Connected',
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall),
                    ])),
                  const Chip(label: Text('CLOUD · READ ONLY')),
                ]),
                const SizedBox(height: 12),
                if (loading) const LinearProgressIndicator(),
                if (error != null)
                  Card(color: const Color(0xFF472F2B),
                    child: Padding(padding: const EdgeInsets.all(14),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('Cloud refresh issue',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                        Text(error!, maxLines: 5,
                          overflow: TextOverflow.ellipsis),
                        if (data != null) const Text(
                          'Your last successfully loaded Library remains visible.'),
                        TextButton(onPressed: load, child: const Text('Retry')),
                      ]))),
                if (data == null && loading)
                  const Padding(padding: EdgeInsets.all(50),
                    child: Center(child: CircularProgressIndicator()))
                else if (data == null)
                  const Card(child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('Your account data could not be loaded. '
                      'No empty Library was created.')))
                else if (wide)
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(flex: 5, child: Column(children: library)),
                    const SizedBox(width: 18),
                    Expanded(flex: 6, child: Column(children: work)),
                  ])
                else ...library + work,
              ],
            );
          },
        ),
      ),
    );
  }
}
