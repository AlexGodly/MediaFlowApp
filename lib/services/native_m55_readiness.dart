/// Frozen release audit projection from docs/parity/m55_release_readiness.json.
/// Inventory counts reflect SOURCE SURFACES, not actual completed functionality.
/// This never connects to cloud or authorizes account writes.
class NativeM55DomainAudit {
  const NativeM55DomainAudit({required this.id,required this.surfaces,
    required this.certified,required this.journeys,required this.verifiedJourneys,
    required this.scaffold});
  final String id, scaffold;
  final int surfaces, certified, journeys, verifiedJourneys;
}

class NativeM55ReleaseBlocker {
  const NativeM55ReleaseBlocker(this.id,this.priority,this.title);
  final String id, priority, title;
}

abstract final class NativeM55Readiness {
  static const String sourceBaseline = 'MediaFlow v410';
  static const int inventorySurfaces = 307;
  static const int inventoriedDomains = 21;
  static const int certifiedSurfaces = 0;
  static const int inventoriedJourneys = 54;
  static const int certifiedJourneys = 0;
  static const int defaultSettingsKeys = 38;
  static const int candidateStateRoots = 30;
  static const int signedProductionPackages = 0;
  static const bool productionReleaseAuthorized = false;
  static const bool fullWebsiteParityCertified = false;
  static const bool productionCloudWritesEnabled = false;
  static const String decision = 'BLOCKED';
  static const String limitation =
    'Source inventory and screen scaffolds are not feature parity. '
    'No source-backed end-to-end journey has been signed off; '
    'no production cloud writes or signed app releases are authorized.';
  static const List<NativeM55DomainAudit> domainAudits = [
    NativeM55DomainAudit(id:'authentication',surfaces:11,certified:0,journeys:3,verifiedJourneys:0,scaffold:'partial'),
    NativeM55DomainAudit(id:'shell-navigation',surfaces:13,certified:0,journeys:2,verifiedJourneys:0,scaffold:'partial'),
    NativeM55DomainAudit(id:'dashboard',surfaces:17,certified:0,journeys:5,verifiedJourneys:0,scaffold:'read_only'),
    NativeM55DomainAudit(id:'library-crud',surfaces:16,certified:0,journeys:3,verifiedJourneys:0,scaffold:'draft_only'),
    NativeM55DomainAudit(id:'library-views',surfaces:20,certified:0,journeys:3,verifiedJourneys:0,scaffold:'read_only'),
    NativeM55DomainAudit(id:'seasons-metadata',surfaces:13,certified:0,journeys:2,verifiedJourneys:0,scaffold:'draft_only'),
    NativeM55DomainAudit(id:'logging',surfaces:17,certified:0,journeys:4,verifiedJourneys:0,scaffold:'draft_only'),
    NativeM55DomainAudit(id:'batch-log',surfaces:12,certified:0,journeys:2,verifiedJourneys:0,scaffold:'draft_only'),
    NativeM55DomainAudit(id:'history',surfaces:17,certified:0,journeys:3,verifiedJourneys:0,scaffold:'read_only'),
    NativeM55DomainAudit(id:'progression',surfaces:16,certified:0,journeys:3,verifiedJourneys:0,scaffold:'read_only'),
    NativeM55DomainAudit(id:'statistics',surfaces:15,certified:0,journeys:2,verifiedJourneys:0,scaffold:'read_only'),
    NativeM55DomainAudit(id:'collections',surfaces:15,certified:0,journeys:3,verifiedJourneys:0,scaffold:'read_only'),
    NativeM55DomainAudit(id:'personal-order',surfaces:16,certified:0,journeys:3,verifiedJourneys:0,scaffold:'read_only'),
    NativeM55DomainAudit(id:'settings',surfaces:17,certified:0,journeys:2,verifiedJourneys:0,scaffold:'partial'),
    NativeM55DomainAudit(id:'themes',surfaces:13,certified:0,journeys:1,verifiedJourneys:0,scaffold:'partial'),
    NativeM55DomainAudit(id:'data-management',surfaces:18,certified:0,journeys:3,verifiedJourneys:0,scaffold:'read_only'),
    NativeM55DomainAudit(id:'cloud-sync',surfaces:15,certified:0,journeys:3,verifiedJourneys:0,scaffold:'read_only'),
    NativeM55DomainAudit(id:'scheduler',surfaces:12,certified:0,journeys:1,verifiedJourneys:0,scaffold:'missing'),
    NativeM55DomainAudit(id:'old-system',surfaces:4,certified:0,journeys:1,verifiedJourneys:0,scaffold:'missing'),
    NativeM55DomainAudit(id:'platform-native',surfaces:15,certified:0,journeys:3,verifiedJourneys:0,scaffold:'partial'),
    NativeM55DomainAudit(id:'performance-security',surfaces:15,certified:0,journeys:2,verifiedJourneys:0,scaffold:'foundation'),
  ];
  static const List<NativeM55ReleaseBlocker> gates = [
    NativeM55ReleaseBlocker('feature-certification','P0','307 source-backed feature certifications'),
    NativeM55ReleaseBlocker('journey-certification','P0','54 full end-to-end workflows'),
    NativeM55ReleaseBlocker('shared-sync','P0','Atomic shared website/native synchronization'),
    NativeM55ReleaseBlocker('logging-history-xp','P0','Logging, History, XP and Respect transaction parity'),
    NativeM55ReleaseBlocker('collections-order','P0','Collections and Personal Order persisted editing'),
    NativeM55ReleaseBlocker('import-export','P0','Import, export and restore safety'),
    NativeM55ReleaseBlocker('settings-themes','P1','Settings persistence and dynamic theme parity'),
    NativeM55ReleaseBlocker('screen-parity','P1','Exact responsive v410 screen/interaction parity'),
    NativeM55ReleaseBlocker('scheduler-old-system','P1','Scheduler and legacy feature coverage'),
    NativeM55ReleaseBlocker('offline-conflicts','P1','Offline write queue and recovery'),
    NativeM55ReleaseBlocker('performance-security','P1','Production performance, accessibility and security'),
    NativeM55ReleaseBlocker('signed-distribution','P0','Signed production packages and device certification'),
  ];
  static const List<String> proposedNextMilestones = [
    'M56 — All-writer sync inventory and staging preparation',
    'M57 — Revisioned server transaction in staging',
    'M58 — Website shared-writer migration',
    'M59 — Native account transactions and sync',
    'M60 — Full Standard and Advanced Logging commit',
    'M61 — History, XP, streak and Respect events',
    'M62 — Scheduler, task engine and legacy coverage',
    'M63 — Collections and Personal Order persistence',
    'M64 — Complete Library CRUD and display parity',
    'M65 — Seasons and provider metadata parity',
    'M66 — Settings, appearance and account parity',
    'M67 — Import/export and reversible recovery',
    'M68 — Offline first writable continuity',
    'M69 — Full cross-platform acceptance sweep',
    'M70 — Signed release candidate gate',
  ];
  static bool get canPublishProduction => false;
  static bool get allCertified =>
      certifiedSurfaces == inventorySurfaces &&
      certifiedJourneys == inventoriedJourneys &&
      productionReleaseAuthorized && fullWebsiteParityCertified;
}
