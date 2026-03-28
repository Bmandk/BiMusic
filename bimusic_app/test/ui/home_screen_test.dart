import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bimusic_app/ui/screens/home_screen.dart';

void main() {
  testWidgets('renders Home title', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    expect(find.text('Home'), findsWidgets);
  });
}
