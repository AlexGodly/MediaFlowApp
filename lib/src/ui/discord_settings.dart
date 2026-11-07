// Settings → This app → Discord: Rich Presence on/off, linking (phones),
// what is shown, idle behaviour and hidden categories.

import 'package:flutter/material.dart';

import '../data/account_controller.dart';
import '../platform/discord_ffi.dart';
import '../platform/discord_presence.dart';
import 'theme.dart';
import 'widgets.dart';

class DiscordSettings extends StatelessWidget {
  const DiscordSettings({super.key, required this.account});
  final AccountController? account;

  @override
  Widget build(BuildContext context) {
    final d = DiscordPresence.instance;
    return ListenableBuilder(
      listenable: d,
      builder: (context, _) {
        if (!DiscordPresence.supported) {
          return Text('Discord Rich Presence is available on Windows, Android and iOS.', style: TextStyle(color: MF.textDim));
        }
        if (!d.available) {
          return Text(
            'This build of MediaFlow does not include Discord Rich Presence.${DiscordFfi.loadError.isEmpty ? '' : '\n${DiscordFfi.loadError}'}',
            style: TextStyle(color: MF.textDim, fontSize: 12),
          );
        }
        final e = d.effective();
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Show what I\'m doing in MediaFlow on Discord'),
            subtitle: Text(DiscordPresence.mobile
                ? 'Link your Discord account once (Discord\'s own sign-in).'
                : 'Works while the Discord app is open on this PC. Nothing to link.'),
            value: d.enabled,
            onChanged: (v) => d.setEnabled(v),
          ),
          if (d.enabled) ...[
            Row(children: [
              Icon(Icons.circle, size: 10, color: d.connected ? MF.good : MF.textMute),
              const SizedBox(width: 8),
              Expanded(child: Text(d.statusText, style: const TextStyle(fontWeight: FontWeight.w700))),
              if (DiscordPresence.mobile && !d.linked)
                FilledButton.icon(
                  onPressed: d.linking ? null : d.link,
                  icon: const Icon(Icons.link_rounded),
                  label: Text(d.linking ? 'Waiting…' : 'Link Discord'),
                )
              else if (d.linked)
                TextButton(onPressed: d.unlink, child: const Text('Unlink')),
            ]),
            if (d.lastError.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(d.lastError, style: TextStyle(color: MF.bad, fontSize: 12)),
              ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: d.privacy,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'What to show'),
              items: const [
                DropdownMenuItem(value: 'full', child: Text('Everything (titles, covers, progress)')),
                DropdownMenuItem(value: 'activity', child: Text('What I\'m doing, without titles')),
                DropdownMenuItem(value: 'minimal', child: Text('Just "Using MediaFlow"')),
              ],
              onChanged: (v) => d.setPrivacy(v ?? 'full'),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: d.idleMode,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'After 5 minutes without using MediaFlow'),
              items: const [
                DropdownMenuItem(value: 'show', child: Text('Show "Idle in MediaFlow"')),
                DropdownMenuItem(value: 'clear', child: Text('Clear my status')),
              ],
              onChanged: (v) => d.setIdleMode(v ?? 'show'),
            ),
            if (account?.view != null) ...[
              const SizedBox(height: 10),
              Text('Never show titles from these categories', style: TextStyle(color: MF.textDim, fontSize: 12)),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final c in account!.view!.categories)
                  FilterChip(
                    label: Text(c.name),
                    selected: d.hiddenCategories.contains(c.id),
                    onSelected: (on) {
                      final next = {...d.hiddenCategories};
                      on ? next.add(c.id) : next.remove(c.id);
                      d.setHiddenCategories(next.toList());
                    },
                  ),
              ]),
            ],
            const SizedBox(height: 14),
            Text('PREVIEW', style: TextStyle(color: MF.textDim, fontSize: 11, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: MF.raised, borderRadius: BorderRadius.circular(12)),
              child: e == null
                  ? Text('Nothing shown (idle)', style: TextStyle(color: MF.textDim))
                  : Row(children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(e.large, width: 56, height: 56, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(width: 56, height: 56, color: MF.surface)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text('MediaFlow', style: TextStyle(fontWeight: FontWeight.w900)),
                          Text(e.details, maxLines: 1, overflow: TextOverflow.ellipsis),
                          if (e.state != null) Text(e.state!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: MF.textDim)),
                        ]),
                      ),
                    ]),
            ),
            const SizedBox(height: 8),
            Text(
              'Uses Discord\'s official Social SDK. MediaFlow never sees your Discord password or account token; you can remove '
              'it any time under Discord → Settings → Authorized Apps.',
              style: TextStyle(color: MF.textMute, fontSize: 11),
            ),
          ],
        ]);
      },
    );
  }
}

/// The SectionCard for Settings.
Widget discordSection(AccountController? account) => SectionCard(
      prefKey: 'app.discord',
      icon: Icons.videogame_asset_rounded,
      title: 'Discord',
      subtitle: 'Rich Presence: show what you\'re doing in MediaFlow',
      child: DiscordSettings(account: account),
    );
