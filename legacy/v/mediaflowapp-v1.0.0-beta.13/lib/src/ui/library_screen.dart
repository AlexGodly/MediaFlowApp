import 'package:flutter/material.dart';

import '../data/account_controller.dart';
import '../state/models.dart';
import 'log_sheet.dart';
import 'theme.dart';
import 'widgets.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, required this.account});
  final AccountController account;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _search = TextEditingController();
  String _status = 'all';
  String _category = '';

  static const _statuses = [
    ('all', 'All'),
    ('active', 'In progress'),
    ('planned', 'Planned'),
    ('completed', 'Completed'),
    ('paused', 'Paused'),
    ('dropped', 'Dropped'),
  ];

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<LibraryTitle> _filtered(AccountView view) {
    final q = _search.text.trim().toLowerCase();
    final out = view.library.where((t) {
      if (_status != 'all' && t.status != _status) return false;
      if (_category.isNotEmpty && t.categoryId != _category) return false;
      if (q.isNotEmpty && !t.title.toLowerCase().contains(q)) return false;
      return true;
    }).toList();
    int recency(LibraryTitle t) => t.modifiedAt > 0 ? t.modifiedAt : t.createdAt;
    out.sort((a, b) {
      // In-progress titles first, then most recently touched.
      final ar = a.status == 'active' ? 0 : 1, br = b.status == 'active' ? 0 : 1;
      if (ar != br) return ar - br;
      return recency(b).compareTo(recency(a));
    });
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final view = widget.account.view!;
    final titles = _filtered(view);
    final usedCategories = view.categories.where((c) => view.library.any((t) => t.categoryId == c.id)).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Library'),
        actions: [SyncIndicator(account: widget.account)],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Search ${fmtNumber(view.library.length)} titles',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => setState(_search.clear),
                    ),
            ),
          ),
        ),
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              for (final s in _statuses)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(s.$2),
                    selected: _status == s.$1,
                    onSelected: (_) => setState(() => _status = s.$1),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _CategoryPicker(
                  categories: usedCategories,
                  value: _category,
                  onChanged: (v) => setState(() => _category = v),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: titles.isEmpty
              ? EmptyState(
                  icon: Icons.video_library_outlined,
                  title: view.library.isEmpty ? 'Your Library is empty' : 'No matching titles',
                  body: view.library.isEmpty
                      ? 'Add titles on the MediaFlow website; they appear here after syncing.'
                      : 'Try a different search or filter.',
                )
              : RefreshIndicator(
                  onRefresh: widget.account.sync,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 96),
                    itemCount: titles.length,
                    itemBuilder: (context, i) => _TitleRow(
                      title: titles[i],
                      category: view.category(titles[i].categoryId),
                      onTap: () => showTitleSheet(context, widget.account, titles[i].id),
                    ),
                  ),
                ),
        ),
      ]),
    );
  }
}

class _CategoryPicker extends StatelessWidget {
  const _CategoryPicker({required this.categories, required this.value, required this.onChanged});
  final List<Category> categories;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final selected = categories.where((c) => c.id == value).toList();
    return PopupMenuButton<String>(
      tooltip: 'Filter by category',
      onSelected: onChanged,
      itemBuilder: (context) => [
        const PopupMenuItem(value: '', child: Text('All categories')),
        for (final c in categories)
          PopupMenuItem(
            value: c.id,
            child: Row(children: [CategoryBadge(c, size: 26), const SizedBox(width: 10), Flexible(child: Text(c.name))]),
          ),
      ],
      child: Chip(
        avatar: const Icon(Icons.category_outlined, size: 18),
        label: Text(selected.isEmpty ? 'All categories' : selected.first.name),
        backgroundColor: value.isEmpty ? MF.raised : MF.accentSoft,
      ),
    );
  }
}

class _TitleRow extends StatelessWidget {
  const _TitleRow({required this.title, required this.category, required this.onTap});
  final LibraryTitle title;
  final Category category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final total = title.total;
    final fraction = total == null || total <= 0 ? null : (title.progress / total).clamp(0.0, 1.0);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
        child: Row(children: [
          Cover(title: title, category: category),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title.title,
                  maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 3),
              Text('${category.name} · ${progressText(title, category)}',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: MF.textDim, fontSize: 12.5)),
              if (fraction != null) ...[
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: fraction,
                    minHeight: 4,
                    backgroundColor: MF.raised,
                    color: statusColor(title.status),
                  ),
                ),
              ],
            ]),
          ),
          const SizedBox(width: 10),
          Text(statusLabel(title.status),
              style: TextStyle(color: statusColor(title.status), fontSize: 12, fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }
}
