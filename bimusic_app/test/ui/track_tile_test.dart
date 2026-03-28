import 'package:bimusic_app/models/track.dart';
import 'package:bimusic_app/ui/widgets/track_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const testTrack = Track(
    id: 1,
    title: 'Test Track',
    trackNumber: '3',
    duration: 213000, // 3:33
    albumId: 1,
    artistId: 10,
    hasFile: true,
    streamUrl: 'http://example.com/stream/1',
  );

  const trackWithoutFile = Track(
    id: 2,
    title: 'Another Track',
    trackNumber: '4',
    duration: 120000, // 2:00
    albumId: 1,
    artistId: 10,
    hasFile: false,
    streamUrl: 'http://example.com/stream/2',
  );

  testWidgets('displays track number, title, and formatted duration',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: TrackTile(track: testTrack, onTap: _noop),
        ),
      ),
    );

    expect(find.text('Test Track'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('3:33'), findsOneWidget);
  });

  testWidgets('shows offline indicator when hasFile is true', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: TrackTile(track: testTrack, onTap: _noop),
        ),
      ),
    );

    expect(find.byIcon(Icons.download_done), findsOneWidget);
  });

  testWidgets('hides offline indicator when hasFile is false', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: TrackTile(track: trackWithoutFile, onTap: _noop),
        ),
      ),
    );

    expect(find.byIcon(Icons.download_done), findsNothing);
  });

  testWidgets('tap triggers onTap callback', (tester) async {
    var tapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TrackTile(
            track: testTrack,
            onTap: () => tapped = true,
          ),
        ),
      ),
    );

    await tester.tap(find.byType(ListTile));
    expect(tapped, isTrue);
  });
}

void _noop() {}
