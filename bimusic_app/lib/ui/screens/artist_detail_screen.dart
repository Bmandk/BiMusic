import 'package:flutter/material.dart';

class ArtistDetailScreen extends StatelessWidget {
  const ArtistDetailScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Artist Detail')),
      body: const Center(child: Text('Artist Detail')),
    );
  }
}
