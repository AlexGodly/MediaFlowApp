// A Discord-style activity card: what a status looks like on Discord
// (Settings → Discord preview, "Discord has" and the Custom Status editor).

import 'dart:async';

import 'package:flutter/material.dart';

import '../platform/discord_ffi.dart' show ActivityType;
import '../platform/discord_presence.dart';
import 'theme.dart';

String activityVerb(int type) => switch (type) {
      ActivityType.watching => 'Watching',
      ActivityType.listening => 'Listening to',
      ActivityType.competing => 'Competing in',
      _ => 'Playing',
    };

class DiscordActivityCard extends StatefulWidget {
  const DiscordActivityCard({super.key, required this.activity, this.empty = 'No active status'});
  final DiscordActivity? activity;
  final String empty;

  @override
  State<DiscordActivityCard> createState() => _DiscordActivityCardState();
}

class _DiscordActivityCardState extends State<DiscordActivityCard> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      final a = widget.activity;
      if (mounted && a != null && (a.start > 0 || a.end > 0)) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  static String _clock(int ms) {
    final s = (ms / 1000).floor().clamp(0, 1 << 31);
    final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
    String two(int v) => v.toString().padLeft(2, '0');
    return h > 0 ? '$h:${two(m)}:${two(sec)}' : '${two(m)}:${two(sec)}';
  }

  Widget _image(String src, double size) {
    if (src.isEmpty) {
      return Container(width: size, height: size, decoration: BoxDecoration(color: MF.surface, borderRadius: BorderRadius.circular(8)));
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(size > 30 ? 8 : size / 2),
      child: Image.network(src, width: size, height: size, cacheWidth: (size * 3).ceil(), fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(width: size, height: size, color: MF.surface, child: const Icon(Icons.image_not_supported_outlined, size: 16))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.activity;
    if (e == null) {
      return Container(
        constraints: const BoxConstraints(minHeight: 110),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: const Color(0xFF111214), borderRadius: BorderRadius.circular(10)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFF949BA4)),
          const SizedBox(width: 6),
          Text(widget.empty, style: const TextStyle(color: Color(0xFF949BA4))),
        ]),
      );
    }
    const text = Color(0xFFF2F3F5), dim = Color(0xFFB5BAC1);
    final now = DateTime.now().millisecondsSinceEpoch;
    final hasBar = e.start > 0 && e.end > e.start;
    final elapsed = e.start > 0 ? now - e.start : 0;
    final left = e.end > 0 ? e.end - now : 0;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFF111214), borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('${activityVerb(e.type)} ${e.name}',
            maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: text, fontWeight: FontWeight.w800, fontSize: 12)),
        const SizedBox(height: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Stack(clipBehavior: Clip.none, children: [
            Tooltip(message: e.largeText ?? '', child: _image(e.large, 64)),
            if (e.small != null)
              Positioned(
                right: -4,
                bottom: -4,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(color: Color(0xFF111214), shape: BoxShape.circle),
                  child: Tooltip(message: e.smallText ?? '', child: _image(e.small!, 22)),
                ),
              ),
          ]),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: text, fontWeight: FontWeight.w800)),
              if (e.details != null)
                Text(e.details!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: e.detailsUrl.isNotEmpty ? const Color(0xFF00A8FC) : text)),
              if (e.state != null)
                Text(
                  '${e.state!}${e.partyMax > 0 ? ' (${e.partyCurrent} of ${e.partyMax})' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: e.stateUrl.isNotEmpty ? const Color(0xFF00A8FC) : dim),
                ),
              if (!hasBar && e.start > 0) Text('${_clock(elapsed)} elapsed', style: const TextStyle(color: dim, fontSize: 12)),
              if (!hasBar && e.start == 0 && e.end > 0) Text('${_clock(left)} left', style: const TextStyle(color: dim, fontSize: 12)),
              if (hasBar) ...[
                const SizedBox(height: 4),
                Row(children: [
                  Text(_clock(elapsed.clamp(0, e.end - e.start).toInt()), style: const TextStyle(color: dim, fontSize: 11)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: ((now - e.start) / (e.end - e.start)).clamp(0, 1).toDouble(),
                        minHeight: 4,
                        backgroundColor: const Color(0xFF4E5058),
                        color: text,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(_clock(e.end - e.start), style: const TextStyle(color: dim, fontSize: 11)),
                ]),
              ],
            ]),
          ),
        ]),
        for (final (label, _) in e.buttons) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            alignment: Alignment.center,
            decoration: BoxDecoration(color: const Color(0xFF2B2D31), borderRadius: BorderRadius.circular(4)),
            child: Text(label, style: const TextStyle(color: text, fontWeight: FontWeight.w700, fontSize: 13)),
          ),
        ],
      ]),
    );
  }
}
