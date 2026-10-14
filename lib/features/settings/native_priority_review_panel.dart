import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/mediaflow_library_repository.dart';
import '../../services/native_sync_review.dart';

/// Real account-scoped encrypted pending review, still strictly READ-ONLY.
/// No apply/upload/commit actions exist. Conflicts require manual discard.
class NativePriorityReviewPanel extends StatefulWidget {
  const NativePriorityReviewPanel({super.key, required this.repository});
  final SupabaseMediaFlowLibraryRepository repository;

  @override
  State<NativePriorityReviewPanel> createState() =>
      _NativePriorityReviewPanelState();
}

class _NativePriorityReviewPanelState
    extends State<NativePriorityReviewPanel> {
  NativeReviewBatch? batch;
  NativeReviewDecision? decision;
  String notice = 'No cloud changes are possible here.';
  bool busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _run(Future<void> Function() callback) async {
    if (busy) return;
    setState(() { busy = true; decision = null; });
    try {
      await callback();
    } on StateError catch (error) {
      if (mounted) setState(() => notice = error.message);
    } on FormatException catch (error) {
      if (mounted) setState(() => notice = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => notice =
            'Cloud or device review is unavailable. Nothing was submitted.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _load() => _run(() async {
    final saved = await widget.repository.loadPriorityReview();
    if (mounted) {
      setState(() {
        batch = saved;
        notice = saved == null ? 'No saved encrypted review.'
            : 'Encrypted review found. Check fresh cloud before trusting it.';
      });
    }
  });

  Future<void> _stage() => _run(() async {
    final saved = await widget.repository.stagePriorityReview();
    if (mounted) {
      setState(() {
        batch = saved;
        notice = 'Priority review encrypted on this device. Not uploaded.';
      });
    }
  });

  Future<void> _inspect() => _run(() async {
    final result = await widget.repository.inspectPriorityReview();
    if (mounted) {
      setState(() {
        decision = result;
        notice = result.simulationOnly
            ? 'Preview verified against fresh cloud. No cloud changes.'
            : 'Review blocked: ${result.status.name}. Nothing uploaded.';
      });
    }
  });

  Future<void> _discard() async {
    if (busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard saved review?'),
        content: const Text('This only deletes the encrypted review and its '
            'device key for this account. It will not delete Library '
            'drafts or change your MediaFlow cloud data.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true),
              child: const Text('Discard saved review')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(() async {
      await widget.repository.discardPriorityReview();
      if (mounted) {
        setState(() {
          batch = null;
          notice = 'Saved review and device-only key discarded.';
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Priority review (preview only)',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        const Text('Stage priority-only Library drafts for encrypted local '
            'review. A fresh, unchanged cloud snapshot is mandatory. '
            'Status, progress, logging, History and XP are NOT supported. '
            'No cloud changes, automatic replay or upload is possible.'),
        const SizedBox(height: 10),
        Text(batch == null
            ? 'No encrypted review loaded.'
            : 'Encrypted review: ${batch!.entries.length} operation(s). '
              'It remains local until you discard it.',
            key: const Key('native-priority-review-count')),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton.icon(
            onPressed: busy ? null : _stage,
            icon: const Icon(Icons.lock_outline),
            label: const Text('Stage priority review'),
          ),
          OutlinedButton.icon(
            onPressed: busy || batch == null ? null : _inspect,
            icon: const Icon(Icons.fact_check_outlined),
            label: const Text('Check fresh cloud'),
          ),
          TextButton.icon(
            onPressed: busy || batch == null ? null : _discard,
            icon: const Icon(Icons.delete_outline),
            label: const Text('Discard saved review'),
          ),
        ]),
        if (busy) const Padding(
          padding: EdgeInsets.only(top: 10),
          child: LinearProgressIndicator(),
        ),
        const SizedBox(height: 10),
        Text(notice, key: const Key('native-priority-review-notice')),
        if (decision != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('Last check: ${decision!.status.name}. '
                'Upload permission: none.',
                key: const Key('native-priority-review-status')),
          ),
      ]),
    ),
  );
}
