// XP preview for Log a title (8.0.0, website v574 Batch Log XP preview): the
// log is applied to a copy of the account and the XP total compared, so the
// preview is exactly what saving earns (consumption XP, streak multipliers,
// completions, first starts and the Batch Log bonus).

import '../state/state_codec.dart';
import 'log_engine.dart';
import 'stats.dart' show xpMetrics;

/// The XP [req] would earn on [state] (left unchanged). Null if it can't be logged.
double? previewLogXp(Map<String, dynamic> state, LogRequest req) {
  final copy = deepCopyState(state);
  final before = xpMetrics(copy).total;
  final outcome = applyLog(copy, req);
  if (!outcome.applied) return null;
  return xpMetrics(copy).total - before;
}
