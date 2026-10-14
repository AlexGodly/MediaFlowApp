// ignore_for_file: prefer_interpolation_to_compose_strings
import 'dart:convert';

import 'native_cas_protocol.dart';
import 'native_edit_proposals.dart';
import 'native_snapshot_codec.dart';

/// An account-scoped, memory-only draft journal. No persistence, networking,
/// background replay, or cloud writes. Clearing a journal discards its drafts.
class NativeDraftJournal {
  NativeDraftJournal({required this.accountId});

  final String accountId;
  final List<NativeDraftEntry> _entries = [];

  List<NativeDraftEntry> get entries =>
      List<NativeDraftEntry>.unmodifiable(_entries);

  void clear() => _entries.clear();

  void add(NativeDraftEntry entry) {
    if (accountId.isEmpty || entry.proposal.accountId != accountId) {
      throw StateError('Draft account does not match journal owner');
    }
    if (_entries.any((existing) => existing.operationId == entry.operationId)) {
      throw StateError('Duplicate operation ID');
    }
    if (_entries.isNotEmpty &&
        _entries.last.proposal.baseRevision != entry.proposal.baseRevision) {
      throw StateError('Mixed cloud revisions cannot share one draft batch');
    }
    _entries.add(entry);
  }

  bool discard(String operationId) {
    final before = _entries.length;
    _entries.removeWhere((entry) => entry.operationId == operationId);
    return before != _entries.length;
  }

  /// Always starts from the freshly provided cloud row. A stale batch is
  /// quarantined, not silently rebased or replayed onto newer cloud data.
  NativeDraftPreview preview(NativeCloudRow row) {
    if (row.ownerId != accountId || accountId.isEmpty) {
      return const NativeDraftPreview.blocked('Account mismatch');
    }
    if (_entries.isEmpty) {
      return const NativeDraftPreview.blocked('No local drafts');
    }
    if (_entries.any((entry) =>
        entry.proposal.baseRevision != row.updatedAt)) {
      return const NativeDraftPreview.blocked(
        'Cloud revision changed. Review and discard or recreate drafts.',
      );
    }
    final original = row.stateData;
    Map<String, dynamic> current = original;
    for (final entry in _entries) {
      final result = NativeSyncPreflight.prepare(
        row: NativeCloudRow(
          ownerId: accountId,
          updatedAt: row.updatedAt,
          stateData: current,
        ),
        proposal: entry.proposal,
      );
      if (!result.isReadyForSimulation) {
        return NativeDraftPreview.blocked(
          'Draft ' + entry.operationId + ' blocked: ' + result.reason,
        );
      }
      current = result.plan!.proposedStateData;
    }
    if (NativeSnapshotCodec.equivalent(original, current)) {
      return const NativeDraftPreview.blocked('Draft batch has no net change');
    }
    return NativeDraftPreview.ready(
      NativeCasPlan(
        ownerId: accountId,
        expectedUpdatedAt: row.updatedAt,
        expectedStateData: original,
        proposedStateData: current,
      ),
    );
  }
}

class NativeDraftEntry {
  NativeDraftEntry({
    required this.operationId,
    required this.proposal,
  }) {
    if (operationId.isEmpty || operationId.length > 128 ||
        !RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(operationId)) {
      throw const FormatException('Invalid operation ID');
    }
  }

  final String operationId;
  final NativeEditProposal proposal;

  Map<String, Object?> toJson() => {
    'operationId': operationId,
    'proposal': proposal.toJson(),
  };

  factory NativeDraftEntry.fromJson(Map<String, dynamic> json) {
    if (json['proposal'] is! Map) {
      throw const FormatException('Missing draft proposal');
    }
    return NativeDraftEntry(
      operationId: json['operationId']?.toString() ?? '',
      proposal: NativeEditProposal.fromJson(
        Map<String, dynamic>.from(json['proposal'] as Map),
      ),
    );
  }
}

class NativeDraftPreview {
  const NativeDraftPreview.blocked(this.reason) : plan = null;
  const NativeDraftPreview.ready(this.plan) : reason = '';

  final String reason;
  final NativeCasPlan? plan;
  bool get isValid => plan != null;
}

/// A portable, explicit export format for future encrypted storage design.
/// Exporting bytes is not automatic and does not send them to Supabase.
abstract final class NativeDraftFormat {
  static String encode(NativeDraftJournal journal) => jsonEncode({
    'format': 'mediaflow-native-draft-v1',
    'accountId': journal.accountId,
    'entries': journal.entries.map((entry) => entry.toJson()).toList(),
  });

  static NativeDraftJournal decode(String input, String signedInAccountId) {
    final data = jsonDecode(input);
    if (data is! Map || data['format'] != 'mediaflow-native-draft-v1' ||
        data['accountId'] != signedInAccountId ||
        signedInAccountId.isEmpty ||
        data['entries'] is! List) {
      throw const FormatException('Invalid or foreign draft export');
    }
    final entries = data['entries'] as List;
    if (entries.length > 1000) {
      throw const FormatException('Draft export exceeds safe limit');
    }
    final journal = NativeDraftJournal(accountId: signedInAccountId);
    for (final raw in entries) {
      if (raw is! Map) {
        throw const FormatException('Invalid draft entry');
      }
      journal.add(NativeDraftEntry.fromJson(
        Map<String, dynamic>.from(raw),
      ));
    }
    return journal;
  }
}
