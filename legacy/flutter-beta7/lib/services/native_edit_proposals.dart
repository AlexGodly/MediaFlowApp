import 'dart:convert';

/// A local, immutable edit proposal. This does NOT submit changes to Supabase.
/// A write transport must be implemented separately with server-side atomic
/// compare-and-swap before proposals can ever be committed.
enum NativeEditKind { setTitlePriority, setTitleStatus, reorderPersonalOrder }

class NativeEditProposal {
  NativeEditProposal({
    required this.kind,
    required this.accountId,
    required this.baseRevision,
    required this.createdAt,
    required this.payload,
  });

  final NativeEditKind kind;
  final String accountId, baseRevision;
  final DateTime createdAt;
  final Map<String, Object?> payload;

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'accountId': accountId,
    'baseRevision': baseRevision,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'payload': payload,
  };

  factory NativeEditProposal.fromJson(Map<String, dynamic> json) {
    final kindName = json['kind'];
    final kind = NativeEditKind.values.where((item) => item.name == kindName);
    if (kind.isEmpty) throw const FormatException('Unknown native edit kind');
    final payload = json['payload'];
    if (payload is! Map) throw const FormatException('Invalid edit payload');
    final createdAt = DateTime.tryParse(json['createdAt']?.toString() ?? '');
    if (createdAt == null) throw const FormatException('Invalid edit date');
    return NativeEditProposal(
      kind: kind.first,
      accountId: json['accountId']?.toString() ?? '',
      baseRevision: json['baseRevision']?.toString() ?? '',
      createdAt: createdAt,
      payload: Map<String, Object?>.from(payload),
    );
  }
}

class NativeEditPreview {
  const NativeEditPreview({
    required this.valid,
    required this.message,
    this.updatedState,
  });

  final bool valid;
  final String message;
  final Map<String, dynamic>? updatedState;
}

/// Pure, copy-on-write simulator: never modifies input data or contacts cloud.
/// A revision mismatch is a hard failure, not a silent last-writer-wins merge.
NativeEditPreview previewNativeEdit({
  required Map<String, dynamic> state,
  required String accountId,
  required String revision,
  required NativeEditProposal proposal,
}) {
  if (accountId.isEmpty || proposal.accountId != accountId) {
    return const NativeEditPreview(valid: false, message: 'Account mismatch');
  }
  if (revision.isEmpty || proposal.baseRevision != revision) {
    return const NativeEditPreview(valid: false, message: 'Cloud revision changed');
  }
  if (proposal.createdAt.isAfter(DateTime.now().add(const Duration(minutes: 5)))) {
    return const NativeEditPreview(valid: false, message: 'Invalid proposal timestamp');
  }
  final copy = Map<String, dynamic>.from(jsonDecode(jsonEncode(state)) as Map);
  switch (proposal.kind) {
    case NativeEditKind.setTitlePriority:
    case NativeEditKind.setTitleStatus:
      final id = proposal.payload['titleId'];
      final value = proposal.payload['value'];
      final field = proposal.kind == NativeEditKind.setTitlePriority
          ? 'priority' : 'status';
      final allowed = field == 'priority'
          ? {'low', 'medium', 'high'}
          : {'active', 'completed', 'planned', 'paused', 'dropped'};
      if (id is! String || id.isEmpty || value is! String ||
          !allowed.contains(value)) {
        return const NativeEditPreview(valid: false, message: 'Invalid title edit');
      }
      final rawLibrary = copy['library'];
      if (rawLibrary is! List) {
        return const NativeEditPreview(valid: false, message: 'Missing Library');
      }
      final matches = rawLibrary.whereType<Map>().where((item) => item['id'] == id);
      if (matches.length != 1) {
        return const NativeEditPreview(valid: false, message: 'Title not found or duplicated');
      }
      matches.single[field] = value;
      break;
    case NativeEditKind.reorderPersonalOrder:
      final requested = proposal.payload['titleIds'];
      final rawPlan = copy['orderPlan'];
      if (requested is! List || requested.any((id) => id is! String) ||
          rawPlan is! Map || rawPlan['titleIds'] is! List) {
        return const NativeEditPreview(valid: false, message: 'Invalid order data');
      }
      final previous = (rawPlan['titleIds'] as List).map((v) => v.toString()).toList();
      final next = requested.cast<String>();
      if (next.length != previous.length ||
          next.toSet().length != next.length ||
          previous.toSet().length != previous.length ||
          !next.toSet().containsAll(previous)) {
        return const NativeEditPreview(valid: false,
            message: 'Reordering cannot add, remove, or duplicate titles');
      }
      rawPlan['titleIds'] = next;
      break;
  }
  return NativeEditPreview(
    valid: true,
    message: 'Local simulation only; cloud data was not modified',
    updatedState: copy,
  );
}
