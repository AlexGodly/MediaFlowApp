// Who is signed in, as the website shows it (getDisplayName / getAvatarUrl):
// the Supabase display name, else the account's profile name, else the email;
// the account's profile picture, else the Supabase avatar.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/account_controller.dart';
import '../util/js.dart';
import 'theme.dart';

Map<String, dynamic> _meta() {
  try {
    return Supabase.instance.client.auth.currentUser?.userMetadata ?? const {};
  } catch (_) {
    return const {};
  }
}

String accountDisplayName(AccountController account) {
  final meta = jsStr(_meta()['display_name']).trim();
  if (meta.isNotEmpty) return meta;
  final profile = account.view?.profileName.trim() ?? '';
  if (profile.isNotEmpty) return profile;
  return account.email.trim().isEmpty ? 'Account' : account.email.trim();
}

String accountAvatarUrl(AccountController account) {
  final own = jsStr(account.view?.state['profilePicture']).trim();
  return own.isNotEmpty ? own : jsStr(_meta()['avatar_url']).trim();
}

/// The round picture, or the name's first letter.
class AccountAvatar extends StatelessWidget {
  const AccountAvatar({super.key, required this.account, this.radius = 26});
  final AccountController account;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final url = accountAvatarUrl(account), name = accountDisplayName(account);
    final letter = CircleAvatar(
      radius: radius,
      backgroundColor: MF.accentSoft,
      child: Text(name.isEmpty ? '?' : name[0].toUpperCase(),
          style: TextStyle(fontSize: radius * 0.85, fontWeight: FontWeight.w900, color: MF.accent)),
    );
    if (url.isEmpty) return letter;
    final ImageProvider image = url.startsWith('data:image/')
        ? MemoryImage(UriData.parse(url).contentAsBytes())
        : NetworkImage(url);
    return CircleAvatar(radius: radius, backgroundColor: MF.accentSoft, backgroundImage: image, onBackgroundImageError: (e, s) {});
  }
}
