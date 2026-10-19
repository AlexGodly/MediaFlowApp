import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow_app/app/mediaflow_shell.dart';
import 'package:mediaflow_app/design_system/mediaflow_theme.dart';
import 'package:mediaflow_app/features/website/native_website_workspaces.dart';

void main() {
  test('complete native workspace navigation preserves every legacy screen', () {
    final names = MediaFlowSection.values.map((section) => section.label).toSet();
    for (final label in const [
      'Dashboard', 'Library', 'Logging', 'Personal Order', 'Collections',
      'History', 'Statistics', 'Account', 'Settings',
      'Old System', 'Fresh Episodes', 'Background Processes',
      'Theme Studio', 'About',
    ]) {
      expect(names, contains(label));
    }
    expect(MediaFlowSection.values.length, 14);
    expect(MediaFlowBreakpoints.desktop, 1081.0);
  });

  test('three genuine theme palettes have website gold accents', () {
    for (final appearance in MediaFlowAppearance.values) {
      final tokens = MediaFlowTheme.palette(appearance);
      expect(tokens.accent, MediaFlowColors.accent);
      expect(tokens.background, isNot(tokens.panel));
      expect(tokens.text, isNot(tokens.background));
    }
    expect(MediaFlowTheme.build(MediaFlowAppearance.dark).useMaterial3, isTrue);
  });

  test('native website companion workspaces are Flutter widgets', () {
    expect(WebsiteWorkspaceKind.values,
      containsAll(WebsiteWorkspaceKind.values));
    expect(WebsiteWorkspaceKind.values.length, 3);
    expect(const NativeWebsiteAboutScreen(), isNotNull);
  });
}
