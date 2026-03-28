import 'package:flutter/material.dart';

class AlbumDetailScreen extends StatelessWidget {
  const AlbumDetailScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Album Detail')),
      body: const Center(child: Text('Album Detail')),
    );
  }
}
