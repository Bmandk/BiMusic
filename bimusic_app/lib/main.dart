import 'package:flutter/material.dart';

void main() {
  runApp(const BiMusicApp());
}

class BiMusicApp extends StatelessWidget {
  const BiMusicApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'BiMusic',
      home: Scaffold(
        body: Center(
          child: Text('BiMusic'),
        ),
      ),
    );
  }
}
