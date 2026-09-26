import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wordie/game.dart';
import 'package:wordie/main.dart' as app;

/// Full tap-through on a device/simulator. Seeds a saved game with a known answer so it's deterministic.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('play a seeded game end to end', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    final seeded = Game('apple', const GameConfig(), {'apple'});
    await prefs.setString('saved', jsonEncode(seeded.toJson()));

    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 1));
    Future<void> shot(String n) async {
      await tester.pumpAndSettle();
      await binding.takeScreenshot(n);
    }

    Future<void> type(String w) async {
      for (final ch in w.toUpperCase().split('')) {
        await tester.tap(find.text(ch).last); // keyboard is below the grid
        await tester.pump();
      }
    }

    await shot('01_home_continue');
    expect(find.text('Continue'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    await type('plan');
    await shot('02_partial_grey_submit');
    await type('e');
    await shot('03_valid_green_submit');
    await tester.tap(find.text('SUBMIT'));
    await tester.pumpAndSettle();
    await shot('04_row1_revealed');

    await type('qzxjk');
    await tester.tap(find.text('SUBMIT'));
    await tester.pump(const Duration(milliseconds: 200));
    await binding.takeScreenshot('05_not_in_list');
    expect(find.text('Not in word list'), findsOneWidget);
    for (var i = 0; i < 5; i++) {
      await tester.tap(find.byIcon(Icons.backspace_outlined));
      await tester.pump();
    }

    await tester.tap(find.byIcon(Icons.track_changes_rounded));
    await shot('06_strike');
    await type('apple');
    await tester.tap(find.byIcon(Icons.search_rounded));
    await shot('07_hint');
    await tester.tap(find.text('SUBMIT'));
    await tester.pump(const Duration(seconds: 3));
    await shot('08_result');
    // row 2, hint in row 2, strike of 3 letters in row 2: (800 - 160 - 144) * 1.25
    expect(find.text('620'), findsOneWidget);

    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(find.text('Continue'), findsNothing);
    await tester.tap(find.text('Statistics'));
    await shot('09_stats');
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    await tester.tap(find.text('New Game'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(BottomSheet), matching: find.byIcon(Icons.add_rounded)).first); // length 5 -> 6
    await shot('10_new_game_sheet');
    await tester.tap(find.text('Start'));
    await shot('11_six_letter_grid');
    expect(find.text('6 letters · row 1/6'), findsOneWidget);
  });
}
