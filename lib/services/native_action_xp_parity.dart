import 'dart:math' as math;

import '../data/mediaflow_models.dart';
import 'native_logging_parity_preview.dart';

/// v348 source-reference calculations. NEVER writes S.xpLedger or Supabase.
/// Real awards also depend on the ORIGINAL submission hooks, user ledgers,
/// task/collection/order outcomes and newer v410 overrides.
class NativeActionXpPreview {
  const NativeActionXpPreview({
    required this.kind, required this.quantity, required this.baseXp,
    required this.streakMultiplier, required this.provisionalXp,
  });
  final String kind;
  final int quantity, provisionalXp;
  final double baseXp, streakMultiplier;
  bool get mayAward => false;
  bool get canCommit => false;
}

abstract final class NativeActionXpParity {
  static const defaultRates = <String, double>{
    'collectionAddTitleXP': 8,
    'orderAddTitleXP': 6,
    'orderAddCollectionXP': 12,
    'orderReorderTitleXP': 4,
    'orderReorderCollectionXP': 6,
    'collectionReorderTitleXP': 4,
    'batchLogXP': 15,
  };

  static double rate(MediaFlowXpEvidence settings, String kind) {
    final defaultValue = defaultRates[kind];
    if (defaultValue == null) {
      throw const FormatException('Unknown v348 action type');
    }
    final configured = settings.actionRates[kind];
    if (configured == null || !configured.isFinite) return defaultValue;
    return configured.clamp(0, 100000).toDouble();
  }

  static double multiplier(MediaFlowXpEvidence settings, int streak) {
    if (!settings.levelingEnabled || !settings.globalStreakEnabled) return 1;
    if (streak < 0 || streak > 100000000) {
      throw const FormatException('Invalid streak');
    }
    return math.max(1,
        NativeLoggingParityPreview.streakMultiplier(streak)).toDouble();
  }

  static int jsRound(double value) {
    if (!value.isFinite || value < 0 || value > 1000000000) {
      throw const FormatException('Invalid XP amount');
    }
    // JS Math.round rounds positive .5 toward +Infinity, matching floor(x+.5).
    return (value + 0.5).floor();
  }

  static NativeActionXpPreview action({
    required MediaFlowXpEvidence settings,
    required String kind,
    required double amount,
    required int streak,
  }) {
    if (!amount.isFinite || amount < 0 || amount > 10000) {
      throw const FormatException('Invalid action count');
    }
    final quantity = jsRound(amount);
    final base = quantity * rate(settings, kind);
    final factor = multiplier(settings, streak);
    final reward = settings.levelingEnabled && quantity > 0
        ? jsRound(base * factor) : 0;
    return NativeActionXpPreview(
      kind: kind, quantity: quantity, baseXp: base,
      streakMultiplier: factor, provisionalXp: reward,
    );
  }

  /// v348RaiseNewRewards: only the newly added delta is amplified. Existing
  /// ledger records are not multiplied again after a later streak increase.
  static double extraForNewFixedReward({
    required MediaFlowXpEvidence settings,
    required double before,
    required double after,
    required int streak,
  }) {
    if (!before.isFinite || !after.isFinite || before < 0 || after < 0 ||
        before > 100000000 || after > 100000000) {
      throw const FormatException('Invalid stored ledger amounts');
    }
    if (!settings.levelingEnabled) return 0;
    final delta = math.max(0.0, after - before);
    if (delta <= 0) return 0;
    return math.max(0.0,
        jsRound(delta * multiplier(settings, streak)) - delta);
  }

  /// The v348ExtraXP metric adds only these THREE bonus ledger maps.
  /// It does not add v348EventMeta or v120 completion logCompletions again.
  static double knownExtraXp(MediaFlowXpEvidence evidence) =>
      evidence.knownExtraXp;
}
