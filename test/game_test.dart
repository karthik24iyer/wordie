import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:wordie/game.dart';

const c = LetterState.correct, p = LetterState.present, a = LetterState.absent;

void main() {
  test('evaluate handles duplicate letters', () {
    expect(evaluate('speed', 'abide'), [a, a, p, a, p]);
    expect(evaluate('eerie', 'crepe'), [p, a, p, a, c]);
    expect(evaluate('llama', 'hello'), [p, p, a, a, a]);
    expect(evaluate('crane', 'crane'), [c, c, c, c, c]);
  });

  test('score matches plan examples', () {
    expect(score(5, 3, []).total, 750);
    expect(score(5, 3, [(hint: true, row: 2, letters: 0)]).total, 550);
    expect(score(5, 3, [(hint: true, row: 3, letters: 0)]).total, 600);
    expect(score(5, 1, [(hint: false, row: 1, letters: 3)]).total, 1025); // (1000-180)*1.25
    expect(score(4, 4, List.filled(3, (hint: true, row: 1, letters: 0))).total, 50); // floor
  });

  test('hint reveals answer letters, strike only hits absent letters', () {
    for (var seed = 0; seed < 50; seed++) {
      final g = Game('apple', const GameConfig(hints: 5, strikeTaps: 3, strikeLetters: 5), {'apple'}, Random(seed));
      for (var i = 0; i < 3; i++) {
        g.useStrike();
      }
      expect(g.struck.length, 15);
      expect(g.struck.any('apple'.contains), isFalse);
      expect(g.canStrike, isFalse);
      for (var i = 0; i < 5; i++) {
        g.useHint();
      }
      expect(g.row.join(), 'apple');
      expect(g.canHint, isFalse);
      expect(g.submit(), isNull);
      expect(g.status, Status.won);
    }
  });

  test('rejects unknown words and loses after length rows', () {
    final g = Game('cat', const GameConfig(length: 3), {'cat', 'dog'});
    for (final ch in 'xyz'.split('')) {
      g.type(ch);
    }
    expect(g.canSubmit, isFalse);
    expect(g.submit(), 'Not in word list');
    for (var i = 0; i < 3; i++) {
      g.backspace();
    }
    for (var r = 0; r < 3; r++) {
      for (final ch in 'dog'.split('')) {
        g.type(ch);
      }
      expect(g.canSubmit, isTrue);
      g.submit();
    }
    expect(g.status, Status.lost);
    expect(g.result, isNull);
  });

  test('saved game restores identically', () {
    const dict = {'apple', 'plane', 'crane'};
    final g = Game('apple', const GameConfig(), dict, Random(1));
    for (final ch in 'plane'.split('')) {
      g.type(ch);
    }
    g.submit();
    g.useHint();
    g.useStrike();
    g.type('a');
    final r = Game.fromJson(jsonDecode(jsonEncode(g.toJson())), dict);
    expect(r.guesses, g.guesses);
    expect(r.results, g.results);
    expect(r.keys, g.keys);
    expect(r.row, g.row);
    expect(r.struck, g.struck);
    expect(r.hinted, g.hinted);
    expect(r.used, g.used);
    expect(r.hintsLeft, 1);
    expect(r.status, Status.playing);
  });
}
