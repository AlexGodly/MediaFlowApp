// Choice & filter layout (website v230, 164-v230-choice-filter-layout.js):
// the order and visibility of the category / status / priority choices in
// Set Category, Set Status and the Library filters. settings.v230ChoiceLayout
// = {modifiedAt, <surface>: {source, order, hidden}}.

import '../state/models.dart' show AccountView, Category;
import '../util/js.dart';

const kStatusIds = ['planned', 'active', 'paused', 'completed', 'dropped'];
const kPriorityIds = ['low', 'medium', 'high'];
const kChoiceSurfaces = [
  ('setCategory', 'Set Category choices'),
  ('categoryFilter', 'Library category filter'),
  ('setStatus', 'Set Status choices'),
  ('statusFilter', 'Library status filter'),
  ('setPriority', 'Set Priority choices'),
  ('priorityFilter', 'Library priority filter'),
];

bool _isCategory(String s) => s == 'setCategory' || s == 'categoryFilter';
bool _isStatus(String s) => s == 'setStatus' || s == 'statusFilter';

/// The sources a surface may follow (`v230NormalizeSurface`).
List<(String, String)> choiceSources(String surface) => _isCategory(surface)
    ? const [('custom', 'Custom'), ('categories', 'Categories settings'), ('dynamic', 'Dynamic category row')]
    : surface == 'statusFilter'
        ? const [('custom', 'Custom'), ('setStatus', 'Same as Set Status')]
        : surface == 'priorityFilter'
            ? const [('custom', 'Custom'), ('setPriority', 'Same as Set Priority')]
            : const [('custom', 'Custom')];

List<String> _defaultOrder(String surface, List<String> cats) => _isCategory(surface)
    ? cats
    : surface == 'statusFilter'
        ? const ['active', 'paused', 'completed', 'dropped', 'planned']
        : surface == 'priorityFilter'
            ? const ['high', 'medium', 'low']
            : _isStatus(surface)
                ? kStatusIds
                : kPriorityIds;

List<String> _unique(Object? values, List<String> valid) {
  final allowed = valid.toSet(), seen = <String>{}, out = <String>[];
  for (final raw in asList(values)) {
    final id = jsStr(raw);
    if (id.isEmpty || !allowed.contains(id) || !seen.add(id)) continue;
    out.add(id);
  }
  return out;
}

/// `v230NormalizeSurface`.
({String source, List<String> order, List<String> hidden}) normalizeSurface(Object? raw, String surface, List<String> cats) {
  final m = asMap(raw);
  final valid = _isCategory(surface) ? cats : (_isStatus(surface) ? kStatusIds : kPriorityIds);
  var source = jsStr(m?['source']).isEmpty ? 'custom' : jsStr(m?['source']);
  if (!choiceSources(surface).any((s) => s.$1 == source)) source = 'custom';
  final order = _unique(m == null ? _defaultOrder(surface, cats) : m['order'], valid);
  for (final id in valid) {
    if (!order.contains(id)) order.add(id);
  }
  return (source: source, order: order, hidden: _unique(m?['hidden'], valid));
}

/// `v230VisibleIds`: the choices to show, in order.
List<String> visibleChoices(Map<String, dynamic>? settings, String surface, List<({String id, bool enabled})> categories,
    [Set<String>? seen]) {
  final cats = [for (final c in categories) c.id];
  final cfg = asMap(settings?['v230ChoiceLayout']);
  final own = normalizeSurface(cfg?[surface], surface, cats);
  final guard = seen ?? <String>{};
  List<String> visible(List<String> order, Iterable<String> hidden) {
    final h = hidden.toSet();
    return [for (final id in order) if (!h.contains(id)) id];
  }

  if (guard.add(surface)) {
    if (_isCategory(surface) && own.source == 'categories') {
      return visible(cats, [for (final c in categories) if (!c.enabled) c.id]);
    }
    if (_isCategory(surface) && own.source == 'dynamic') {
      final lib = asMap(settings?['v181Library']);
      final order = lib?['dynamicCategoryOrderMode'] == 'category' ? cats : [for (final x in asList(lib?['categoryOrder'])) jsStr(x)];
      return visible(order, asList(lib?['hiddenCategoryIds']).map(jsStr));
    }
    if (surface == 'statusFilter' && own.source == 'setStatus') return visibleChoices(settings, 'setStatus', categories, guard);
    if (surface == 'priorityFilter' && own.source == 'setPriority') return visibleChoices(settings, 'setPriority', categories, guard);
  }
  return visible(own.order, own.hidden);
}

/// The whole layout with [surface] replaced (and a fresh modifiedAt), for saving.
Map<String, dynamic> withSurface(Map<String, dynamic>? settings, String surface, String source, List<String> order,
    List<String> hidden, List<String> cats, int now) {
  final cfg = asMap(settings?['v230ChoiceLayout']);
  final out = <String, dynamic>{'modifiedAt': now};
  for (final s in kChoiceSurfaces) {
    final n = s.$1 == surface ? normalizeSurface({'source': source, 'order': order, 'hidden': hidden}, s.$1, cats) : normalizeSurface(cfg?[s.$1], s.$1, cats);
    out[s.$1] = {'source': n.source, 'order': n.order, 'hidden': n.hidden};
  }
  return out;
}

/// [choices] reordered and filtered for [surface]; [keep] stays even if hidden
/// (the value already chosen), so a dropdown never loses its selection.
List<(String, String)> applyChoiceLayout(Map<String, dynamic>? settings, String surface,
    List<({String id, bool enabled})> categories, List<(String, String)> choices, {String? keep}) {
  final ids = visibleChoices(settings, surface, categories);
  final byId = {for (final c in choices) c.$1: c};
  final out = [for (final id in ids) if (byId[id] != null) byId[id]!];
  if (keep != null && byId[keep] != null && !ids.contains(keep)) out.add(byId[keep]!);
  return out.isEmpty ? choices : out;
}

/// The view's categories in the shape [visibleChoices] takes.
List<({String id, bool enabled})> choiceCategories(AccountView view) =>
    [for (final c in view.categories) (id: c.id, enabled: c.enabled)];

/// [applyChoiceLayout] for an [AccountView].
List<(String, String)> viewChoices(AccountView view, String surface, List<(String, String)> choices, {String? keep}) =>
    applyChoiceLayout(asMap(view.state['settings']), surface, choiceCategories(view), choices, keep: keep);

// ---- 10.0.0: every list of categories follows the layout ------------------------------

/// The categories as the Library category filter shows them (your order,
/// hidden ones left out; [keep] stays even if hidden). For filters and pickers.
List<Category> filterCategories(AccountView view, {Iterable<String> keep = const []}) =>
    _layoutCategories(view, 'categoryFilter', keep);

/// The categories as Set Category shows them, for choosing where a title goes.
List<Category> setCategories(AccountView view, {Iterable<String> keep = const []}) =>
    _layoutCategories(view, 'setCategory', keep);

List<Category> _layoutCategories(AccountView view, String surface, Iterable<String> keep) {
  final ids = visibleChoices(asMap(view.state['settings']), surface, choiceCategories(view));
  final byId = {for (final c in view.categories) c.id: c};
  final out = [for (final id in ids) if (byId[id] != null) byId[id]!];
  for (final k in keep) {
    final c = byId[k];
    if (c != null && !out.contains(c)) out.add(c);
  }
  return out.isEmpty ? view.categories : out;
}
