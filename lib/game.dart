import 'dart:math';

import 'package:flutter/foundation.dart';

/// Ordered so a key can keep the "best" state it has seen.
enum LetterState { none, absent, present, correct }

enum Status { playing, won, lost, dnf }

/// Standard Wordle colouring incl. duplicates: greens first, then yellows
/// only while unmatched copies of that letter remain in the answer.
List<LetterState> evaluate(String guess, String answer) {
  final out = List.filled(guess.length, LetterState.absent);
  final left = <String, int>{};
  for (var i = 0; i < answer.length; i++) {
    if (guess[i] == answer[i]) {
      out[i] = LetterState.correct;
    } else {
      left[answer[i]] = (left[answer[i]] ?? 0) + 1;
    }
  }
  for (var i = 0; i < guess.length; i++) {
    if (out[i] == LetterState.correct) continue;
    final n = left[guess[i]] ?? 0;
    if (n > 0) {
      out[i] = LetterState.present;
      left[guess[i]] = n - 1;
    }
  }
  return out;
}

class GameConfig {
  final int length, hints, strikeTaps, strikeLetters;
  const GameConfig({this.length = 5, this.hints = 2, this.strikeTaps = 1, this.strikeLetters = 3});

  Map<String, int> toJson() => {'length': length, 'hints': hints, 'strikeTaps': strikeTaps, 'strikeLetters': strikeLetters};
  factory GameConfig.fromJson(Map<String, dynamic> j) => GameConfig(
    length: j['length'] ?? 5,
    hints: j['hints'] ?? 2,
    strikeTaps: j['strikeTaps'] ?? 1,
    strikeLetters: j['strikeLetters'] ?? 3,
  );
}

/// A booster use: [row] is 1-based row being played, [letters] = letters struck (0 for a hint).
typedef Booster = ({bool hint, int row, int letters});

class Score {
  final double guessPts, hintCost, strikeCost, mult;
  final int total;
  const Score(this.guessPts, this.hintCost, this.strikeCost, this.mult, this.total);
}

/// Each hint keeps this fraction of the guess points. ponytail: single tuning knob.
const hintFactor = 0.5;

/// Fewer guesses and longer words score more. Each hint halves the guess
/// points (whenever used); strikes are a flat cost, cheaper the later you use them.
Score score(int length, int solvedRow, List<Booster> used) {
  final l = length;
  double late(int row) => (l - row + 1) / l;
  final guessPts = 1000 * late(solvedRow);
  var hints = 0, strike = 0.0;
  for (final b in used) {
    if (b.hint) {
      hints++;
    } else {
      strike += 60 * b.letters * late(b.row);
    }
  }
  final hint = guessPts * (1 - pow(hintFactor, hints));
  final mult = 1 + 0.25 * (l - 4);
  final total = (mult * max(guessPts - hint - strike, 50) / 5).round() * 5;
  return Score(guessPts, hint, strike, mult, total);
}

class Game extends ChangeNotifier {
  final String answer;
  final GameConfig config;
  final Set<String> dictionary;
  final Random _rng;

  final guesses = <String>[];
  final results = <List<LetterState>>[];
  final keys = <String, LetterState>{};
  final struck = <String>{};
  final hinted = <int>{}; // positions revealed by hints; shown as placeholders in empty cells, never locked in
  final used = <Booster>[];
  late List<String?> row;
  Status status = Status.playing;

  Game(this.answer, this.config, this.dictionary, [Random? rng]) : _rng = rng ?? Random() {
    _resetRow();
  }

  Map<String, dynamic> toJson() => {
    'answer': answer,
    'config': config.toJson(),
    'guesses': guesses,
    'row': row,
    'struck': struck.toList(),
    'hinted': hinted.toList(),
    'used': [
      for (final b in used) [b.hint ? 1 : 0, b.row, b.letters],
    ],
  };

  /// Rebuilds a saved game by replaying its guesses (recomputes colours, keys, status).
  factory Game.fromJson(Map<String, dynamic> j, Set<String> dictionary) {
    final g = Game(j['answer'], GameConfig.fromJson(j['config']), dictionary);
    g.hinted.addAll(List<int>.from(j['hinted']));
    g.struck.addAll(List<String>.from(j['struck']));
    g.used.addAll([for (final u in j['used']) (hint: u[0] == 1, row: u[1] as int, letters: u[2] as int)]);
    for (final w in List<String>.from(j['guesses'])) {
      g.row = List<String?>.from(w.split(''));
      g.submit();
    }
    g.row = List<String?>.from(j['row']);
    for (final i in g.hinted) {
      g.keys[g.answer[i]] = LetterState.correct;
    }
    return g;
  }

  int get length => config.length;
  int get rowIndex => guesses.length; // 0-based current row
  int get hintsLeft => config.hints - used.where((b) => b.hint).length;
  int get strikesLeft => config.strikeTaps - used.where((b) => !b.hint).length;
  Score? get result => status == Status.won ? score(length, guesses.length, used) : null;

  void _resetRow() => row = List.filled(length, null);

  Iterable<int> get _hintable sync* {
    for (var i = 0; i < length; i++) {
      if (!hinted.contains(i) && !results.any((r) => r[i] == LetterState.correct)) yield i;
    }
  }

  Iterable<String> get _strikeable sync* {
    for (var c = 97; c <= 122; c++) {
      final s = String.fromCharCode(c);
      if (!answer.contains(s) && !struck.contains(s) && keys[s] != LetterState.absent) yield s;
    }
  }

  bool get canHint => status == Status.playing && hintsLeft > 0 && _hintable.isNotEmpty;
  bool get canStrike => status == Status.playing && strikesLeft > 0 && _strikeable.isNotEmpty;
  bool get canSubmit => status == Status.playing && !row.contains(null) && dictionary.contains(row.join());

  void type(String letter) {
    if (status != Status.playing) return;
    final i = row.indexOf(null);
    if (i == -1) return;
    row[i] = letter;
    notifyListeners();
  }

  void backspace() {
    for (var i = length - 1; i >= 0; i--) {
      if (row[i] != null) {
        row[i] = null;
        notifyListeners();
        return;
      }
    }
  }

  /// Returns an error message, or null if the guess was accepted.
  String? submit() {
    if (status != Status.playing) return null;
    if (row.contains(null)) return 'Not enough letters';
    final guess = row.join();
    if (!dictionary.contains(guess)) return 'Not in word list';
    final res = evaluate(guess, answer);
    guesses.add(guess);
    results.add(res);
    for (var i = 0; i < length; i++) {
      final k = guess[i];
      if (res[i].index > (keys[k] ?? LetterState.none).index) keys[k] = res[i];
    }
    if (guess == answer) {
      status = Status.won;
    } else if (guesses.length == length) {
      status = Status.lost;
    }
    _resetRow();
    notifyListeners();
    return null;
  }

  /// Gives up: fills the current row with the answer in green and ends the game as a DNF.
  void forfeit() {
    if (status != Status.playing) return;
    guesses.add(answer);
    results.add(List.filled(length, LetterState.correct));
    status = Status.dnf;
    _resetRow();
    notifyListeners();
  }

  void useHint() {
    if (!canHint) return;
    final options = _hintable.toList();
    final i = options[_rng.nextInt(options.length)];
    hinted.add(i);
    keys[answer[i]] = LetterState.correct;
    used.add((hint: true, row: rowIndex + 1, letters: 0));
    notifyListeners();
  }

  void useStrike() {
    if (!canStrike) return;
    final options = _strikeable.toList()..shuffle(_rng);
    final hit = options.take(config.strikeLetters).toList();
    struck.addAll(hit); // still typeable, like any grey letter
    used.add((hint: false, row: rowIndex + 1, letters: hit.length));
    notifyListeners();
  }
}

String _day(DateTime d) => DateTime(d.year, d.month, d.day).toIso8601String().substring(0, 10);

class Stats {
  // streak = consecutive days with at least one finished (won/lost) game; a DNF alone doesn't count
  int played = 0, wins = 0, dnf = 0, noHints = 0, streak = 0, maxStreak = 0, best = 0, total = 0, lenSum = 0, lenWins = 0;
  String? lastDay; // day of the last finished game

  /// Current daily streak: 0 once a whole day passes without finishing a game.
  int streakOn(DateTime now) =>
      lastDay == _day(now) || lastDay == _day(DateTime(now.year, now.month, now.day - 1)) ? streak : 0;

  double get avgLength => lenWins == 0 ? 0 : lenSum / lenWins;

  void record(Game g, [DateTime? now]) {
    now ??= DateTime.now();
    played++;
    if (g.status == Status.dnf) {
      dnf++;
      return;
    }
    if (!g.used.any((b) => b.hint)) noHints++;
    final s = g.result;
    if (s != null) {
      wins++;
      best = max(best, s.total);
      total += s.total;
      lenSum += g.length;
      lenWins++;
    }
    if (lastDay != _day(now)) {
      streak = streakOn(now) + 1;
      lastDay = _day(now);
      maxStreak = max(maxStreak, streak);
    }
  }

  // ponytail: old win-streak keys ('streak'/'maxStreak'/'hist') are just ignored; lenWins starts at 0 as old wins have no length
  Map<String, dynamic> toJson() => {
    'played': played,
    'wins': wins,
    'dnf': dnf,
    'noHints': noHints,
    'dayStreak': streak,
    'maxDayStreak': maxStreak,
    'lastDay': lastDay,
    'best': best,
    'total': total,
    'lenSum': lenSum,
    'lenWins': lenWins,
  };
  Stats();
  Stats.fromJson(Map<String, dynamic> j)
    : played = j['played'] ?? 0,
      wins = j['wins'] ?? 0,
      dnf = j['dnf'] ?? 0,
      noHints = j['noHints'] ?? 0,
      streak = j['dayStreak'] ?? 0,
      maxStreak = j['maxDayStreak'] ?? 0,
      lastDay = j['lastDay'],
      best = j['best'] ?? 0,
      total = j['total'] ?? 0,
      lenSum = j['lenSum'] ?? 0,
      lenWins = j['lenWins'] ?? 0;
}
