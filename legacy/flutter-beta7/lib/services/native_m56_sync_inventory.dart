/// Milestone 56 source-backed inventory projection.
/// Audit facts are immutable and cannot unlock network or production writes.
class NativeM56WriterSurface {
  const NativeM56WriterSurface({required this.id, required this.client,
    required this.kind, required this.entrypoint, required this.sourcePath,
    required this.risk});
  final String id, client, kind, entrypoint, sourcePath, risk;
}

class NativeM56StagingCheck {
  const NativeM56StagingCheck(this.id, this.reason);
  final String id, reason;
}

abstract final class NativeM56SyncInventory {
  static const int writerSurfaces = 18;
  static const int rehearsalScenarios = 12;
  static const int unresolvedDiscoveryTasks = 8;
  static const int unresolvedStagingChecks = 8;
  static const bool sourceAuditExhaustive = false;
  static const bool stagingEnvironmentProvisioned = false;
  static const bool productionCloudWritesEnabled = false;
  static const bool serverProtocolDeployed = false;
  static const bool cutoverAuthorized = false;
  static const bool readyForStaging = false;
  static const bool readyForProduction = false;
  static const String warning =
      'This source-level inventory is NOT exhaustive. A physical staging '
      'Supabase project, deployed database protocol, verified backups and '
      'complete writer migration have not been established.';
  static const List<NativeM56WriterSurface> sources = [
    NativeM56WriterSurface(id: 'web-cloud-rawset', client: 'website', kind: 'direct_cloud_writer', entrypoint: 'rawSet()', sourcePath: 'src/js/services/cloud-sync/004-v115-cloud-data-loss-prevention-recovery-guard.js', risk: 'critical'),
    NativeM56WriterSurface(id: 'web-autosave', client: 'website', kind: 'cloud_write_caller', entrypoint: 'saveState() -> saveQueue -> rawSet()', sourcePath: 'src/js/services/cloud-sync/004-v115-cloud-data-loss-prevention-recovery-guard.js', risk: 'critical'),
    NativeM56WriterSurface(id: 'web-sync-now', client: 'website', kind: 'direct_cloud_write_caller', entrypoint: 'v155SyncNow() -> mergeStates() -> rawSet()', sourcePath: 'src/js/services/cloud-sync/058-v155-complete-cloud-state-full-sync-now.js', risk: 'critical'),
    NativeM56WriterSurface(id: 'web-recovery-restore', client: 'website', kind: 'cloud_write_caller', entrypoint: 'MediaFlowRecovery.restore() / saveState()', sourcePath: 'src/js/services/cloud-sync/004-v115-cloud-data-loss-prevention-recovery-guard.js', risk: 'critical'),
    NativeM56WriterSurface(id: 'web-logging-submit', client: 'website', kind: 'state_mutator_to_autosave', entrypoint: 'App.submitLog() -> persistLibrary()/persistSessions()/persistTask()', sourcePath: 'src/js/features/logging/008-session-flow.js', risk: 'critical'),
    NativeM56WriterSurface(id: 'web-collection-traversal', client: 'website', kind: 'state_mutator_to_autosave', entrypoint: 'v287StageTraversal()/v287RollbackTraversal()/App.submitLog wrapper', sourcePath: 'src/js/components/221-v287-personal-order-collection-queues.js', risk: 'critical'),
    NativeM56WriterSurface(id: 'web-order-clear-restore', client: 'website', kind: 'state_mutator_to_autosave', entrypoint: 'v287 clear/restore Order actions -> saveState()', sourcePath: 'src/js/components/221-v287-personal-order-collection-queues.js', risk: 'high'),
    NativeM56WriterSurface(id: 'web-full-backup-restore', client: 'website', kind: 'cloud_write_caller', entrypoint: 'restore validated backup -> v46ApplyState() -> saveState()', sourcePath: 'src/js/features/backup/053-v148-complete-data-backup-audit-full-restore.js', risk: 'critical'),
    NativeM56WriterSurface(id: 'web-backup-export', client: 'website', kind: 'local_file_export', entrypoint: 'v148BuildFullBackup() / App.exportJSON()', sourcePath: 'src/js/features/backup/053-v148-complete-data-backup-audit-full-restore.js', risk: 'high'),
    NativeM56WriterSurface(id: 'web-automatic-backup', client: 'website', kind: 'local_file_export', entrypoint: 'backupSnapshot() -> v148BuildFullBackup()', sourcePath: 'src/js/features/backup/056-v152-automatic-backup-full-backup.js', risk: 'high'),
    NativeM56WriterSurface(id: 'web-settings-wrappers', client: 'website', kind: 'state_mutator_to_autosave', entrypoint: 'persistSettings() wrapper', sourcePath: 'src/js/services/cloud-sync/115-persistence-merge-sync-now-full-backup.js', risk: 'high'),
    NativeM56WriterSurface(id: 'web-rating-queue-portable', client: 'website', kind: 'state_mutator_to_autosave', entrypoint: 'v155SchedulePortableCloudSave() / snapshot wrapper', sourcePath: 'src/js/services/cloud-sync/058-v155-complete-cloud-state-full-sync-now.js', risk: 'high'),
    NativeM56WriterSurface(id: 'web-library-import', client: 'website', kind: 'state_mutator_to_autosave', entrypoint: 'v169 import apply/rollback', sourcePath: 'src/js/features/import-export/071-v169-advanced-import-export-media-services.js', risk: 'high'),
    NativeM56WriterSurface(id: 'web-legacy-backup-overrides', client: 'website', kind: 'runtime_override_to_review', entrypoint: 'v200 persistSettings()/snapshot()/backup builder', sourcePath: 'src/js/services/cloud-sync/140-persistence-cloud-full-backup.js', risk: 'high'),
    NativeM56WriterSurface(id: 'native-owner-read', client: 'native', kind: 'cloud_read_only', entrypoint: '_readCloud() / _readFreshForPriorityReview()', sourcePath: 'lib/data/mediaflow_library_repository.dart', risk: 'critical'),
    NativeM56WriterSurface(id: 'native-local-drafts', client: 'native', kind: 'device_local_only', entrypoint: 'encrypted offline pending review drafts', sourcePath: 'lib/services/native_m33_draft_store.dart', risk: 'high'),
    NativeM56WriterSurface(id: 'native-proposed-cas', client: 'native', kind: 'test_only_simulation', entrypoint: 'NativeM30SimulatedSharedServer', sourcePath: 'lib/services/native_m30_shared_sync.dart', risk: 'critical'),
    NativeM56WriterSurface(id: 'native-locked-cloud-writes', client: 'native', kind: 'production_capability_gate', entrypoint: 'NativeCloudCapabilities flags', sourcePath: 'lib/services/native_cas_protocol.dart', risk: 'critical'),
  ];
  static const List<NativeM56StagingCheck> stagingChecks = [
    NativeM56StagingCheck('isolated-env', 'No isolated Supabase staging project provisioned; no live migration attempted'),
    NativeM56StagingCheck('writer-exhaustive', 'Dynamic v410 bundled override/write-path discovery remains open'),
    NativeM56StagingCheck('schema-rls', 'No live production/staging schema or RLS audit performed'),
    NativeM56StagingCheck('backup-restore', 'No real owner-scoped, restorable staging backup tested'),
    NativeM56StagingCheck('durable-transactions', 'Only in-memory model tests exist; no PostgreSQL version/receipt transaction deployed'),
    NativeM56StagingCheck('all-client-compat', 'Original website still uses unconditional state_data UPSERT'),
    NativeM56StagingCheck('rollback-drill', 'No database recovery drill or restore receipts captured'),
    NativeM56StagingCheck('cross-device-qa', 'No real-device/account integration tests against staging'),
  ];
  static const List<String> outstandingDiscovery = [
    'Enumerate dynamically overwritten saveState/rawSet/persistX functions in full runtime order',
    'Verify legacy page and beta/live deployments use the same pinned compiled v410 bundle',
    'Audit every Supabase table, storage and Auth/Edge Function write path (no live credentials or schema accessed)',
    'Audit all Library and category CRUD entrypoints, duplicate imports and bulk delete',
    'Audit XP/level/Respect reward hooks, history completion and optimistic reroll paths',
    'Audit profile image URL/account settings, Settings Center versions and portable preferences',
    'Audit browser IndexedDB/localStorage migrations, PWA background sync and service-worker actions',
    'Audit import/restore/automatic backup destinations and rollback across all v410 wrappers',
  ];
}
