import 'package:flutter/material.dart';
import 'app/mediaflow_shell.dart';

void main() => runApp(const MediaFlowApp());

class MediaFlowApp extends StatelessWidget {
  const MediaFlowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'MediaFlow',
      debugShowCheckedModeBanner: false,
      home: MediaFlowShell(),
    );
  }
}
