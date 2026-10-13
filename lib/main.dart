import 'package:flutter/material.dart';

void main() => runApp(const MediaFlowApp());

class MediaFlowApp extends StatelessWidget {
  const MediaFlowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MediaFlow',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
      home: const Scaffold(
        body: Center(child: Text('MediaFlow native migration — development scaffold')),
      ),
    );
  }
}
