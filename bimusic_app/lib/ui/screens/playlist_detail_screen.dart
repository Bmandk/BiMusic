import 'package:flutter/material.dart';

class PlaylistDetailScreen extends StatelessWidget {
  const PlaylistDetailScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Playlist Detail')),
      body: const Center(child: Text('Playlist Detail')),
    );
  }
}
