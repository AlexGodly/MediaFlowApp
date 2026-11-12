/// Public client configuration. These are the same values the MediaFlow website
/// ships in its own JavaScript; the publishable key is safe to embed.
const String kSupabaseUrl = 'https://wgeijxfdpgehesxialxm.supabase.co';
const String kSupabasePublishableKey = 'sb_publishable_d2P0qZlvGZOSqcUzEg3BNg_3wQsHY_M';
const String kStateTable = 'mediaflow_states';

const String kWebsiteUrl = 'https://alexgodly.github.io/MediaFlow/';
/// MAJOR.FEATURE.FIX.WEBSITE — see CLAUDE.md "Versions".
const String kAppVersionLabel = '6.1.0.565';

/// Whether a release tag (`mediaflowapp-v2.1.0.561`) is newer than [current],
/// comparing the numbers in order (a missing number counts as 0).
bool isNewerVersion(String tag, String current) {
  List<int> parts(String v) => RegExp(r'\d+').allMatches(v.replaceFirst(RegExp(r'^[^\d]*'), '').split('-').first).map((m) => int.parse(m[0]!)).toList();
  final a = parts(tag), b = parts(current);
  if (a.isEmpty) return false;
  for (var i = 0; i < (a.length > b.length ? a.length : b.length); i++) {
    final x = i < a.length ? a[i] : 0, y = i < b.length ? b[i] : 0;
    if (x != y) return x > y;
  }
  return false;
}
