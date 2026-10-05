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
    expect(score(5, 3, [(hint: true, row: 2, letters: 0)]).total, 375); // one hint halves
    expect(score(5, 3, List.filled(2, (hint: true, row: 3, letters: 0))).total, 190); // two quarter
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
      final x = g.struck.first;
      g.type(x);
      expect(g.row.first, x); // struck letters are still typeable
      g.backspace();
      for (var i = 0; i < 5; i++) {
        g.useHint();
      }
      expect(g.hinted.length, 5);
      expect(g.row.contains(null), isTrue); // hints are placeholders, not typed letters
      expect(g.canHint, isFalse);
      for (final ch in 'apple'.split('')) {
        g.type(ch);
      }
      expect(g.submit(), isNull);
      expect(g.status, Status.won);
    }
  });

  test('hinted cell can be overwritten and backspaced', () {
    final g = Game('apple', const GameConfig(hints: 5), {'apple', 'zebra'}, Random(0));
    for (var i = 0; i < 5; i++) {
      g.useHint();
    }
    for (final ch in 'zebra'.split('')) {
      g.type(ch);
    }
    expect(g.row.join(), 'zebra');
    for (var i = 0; i < 5; i++) {
      g.backspace();
    }
    expect(g.row.every((c) => c == null), isTrue);
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

  test('forfeit is a DNF; daily streak counts days with a finished game', () {
    Game won(String w) => Game(w, GameConfig(length: w.length), {w})
      ..row = w.split('')
      ..submit();
    Game dnf() => Game('cat', const GameConfig(length: 3), {'cat'})..forfeit();
    final st = Stats();
    final d1 = DateTime(2026, 3, 1, 9);

    final f = dnf();
    expect(f.status, Status.dnf);
    expect(f.results.last, everyElement(LetterState.correct));
    st.record(f, d1);
    expect([st.played, st.dnf, st.wins, st.streakOn(d1)], [1, 1, 0, 0]); // DNF alone doesn't make a day

    st.record(won('apple'), d1);
    st.record(won('cats'), d1); // same day: streak stays 1
    expect(st.streakOn(d1), 1);
    expect(st.avgLength, 4.5);

    st.record(won('plane'), DateTime(2026, 3, 2, 23));
    expect([st.streak, st.maxStreak], [2, 2]);
    expect(st.streakOn(DateTime(2026, 3, 3)), 2); // still alive the next day
    expect(st.streakOn(DateTime(2026, 3, 4)), 0); // missed a day

    st.record(dnf(), DateTime(2026, 3, 5));
    st.record(won('plane'), DateTime(2026, 3, 5));
    expect([st.streak, st.maxStreak, st.played, st.dnf], [1, 2, 6, 2]);

    final r = Stats.fromJson(jsonDecode(jsonEncode(st.toJson())));
    expect([r.streak, r.maxStreak, r.lastDay, r.dnf, r.avgLength], [1, 2, '2026-03-05', 2, st.avgLength]);

    st.record(Game('apple', const GameConfig(), {'apple'})..useHint()..row = 'apple'.split('')..submit(), DateTime(2026, 3, 5));
    expect([st.noHints, st.wins], [4, 5]); // DNF and hinted games don't count
    expect(Stats.fromJson(jsonDecode(jsonEncode(st.toJson()))).noHints, 4);
  });
}
