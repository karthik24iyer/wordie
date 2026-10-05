import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'game.dart';
import 'main.dart' show WordList;
import 'wood.dart';

TextStyle txt(double size, {Color color = Wood.ink, double weight = 600}) =>
    TextStyle(fontFamily: 'Fredoka', fontSize: size, color: color, fontVariations: [FontVariation('wght', weight)]);

const _flipMs = 300;

Color stateColor(LetterState s) => switch (s) {
  LetterState.correct => Wood.green,
  LetterState.present => Wood.yellow,
  LetterState.absent => Wood.grey,
  LetterState.none => Wood.birch,
};

/// Everything persisted lives in SharedPreferences as JSON under these keys.
class Store {
  final SharedPreferences p;
  final Map<int, WordList> words;
  final Map<String, String> meanings;
  Store(this.p, this.words, this.meanings);

  Map<String, dynamic>? _get(String k) => p.getString(k) == null ? null : jsonDecode(p.getString(k)!);

  GameConfig get config => _get('config') == null ? const GameConfig() : GameConfig.fromJson(_get('config')!);
  set config(GameConfig c) => p.setString('config', jsonEncode(c.toJson()));

  Stats get stats => _get('stats') == null ? Stats() : Stats.fromJson(_get('stats')!);
  void record(Game g) => p.setString('stats', jsonEncode((stats..record(g)).toJson()));

  Game? get saved {
    final j = _get('saved');
    if (j == null) return null;
    try {
      return Game.fromJson(j, words[j['config']['length']]!.guesses);
    } catch (_) {
      return null; // ponytail: corrupt/old save is just dropped
    }
  }

  void save(Game g) => g.status == Status.playing ? p.setString('saved', jsonEncode(g.toJson())) : p.remove('saved');

  Game fresh(GameConfig c) {
    final list = words[c.length]!;
    return Game(list.answers[Random().nextInt(list.answers.length)], c, list.guesses);
  }

  /// Leaving an in-progress game with guesses counts as a DNF (and a loss in Played/Win %).
  void abandonSaved() {
    final g = saved;
    if (g != null && g.guesses.isNotEmpty) record(g..forfeit());
    p.remove('saved');
  }
}

Future<GameConfig?> showConfigSheet(BuildContext context, GameConfig c, {required String title, required String action}) =>
    showModalBottomSheet<GameConfig>(
      context: context,
      backgroundColor: const Color(0xFFFDF1E4),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _NewGameSheet(c, title: title, action: action),
    );

class Background extends StatelessWidget {
  final Widget child;
  const Background({super.key, required this.child});
  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFFDF1E4), Color(0xFFFADDD3), Color(0xFFD9F0E6)],
      ),
    ),
    child: SafeArea(child: child),
  );
}

class HomeScreen extends StatefulWidget {
  final Store store;
  const HomeScreen(this.store, {super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Store get store => widget.store;

  Future<void> _play(Game g) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => GameScreen(store, g)));
    setState(() {}); // refresh Continue
  }

  Future<void> _newGame() async {
    if (store.saved?.guesses.isNotEmpty ?? false) {
      if (!await confirmAbandon(context) || !mounted) return;
      store.abandonSaved();
      setState(() {}); // Continue is gone either way
    }
    final c = await showConfigSheet(context, store.config, title: 'New Game', action: 'Start');
    if (c == null || !mounted) return;
    store.abandonSaved(); // drops a 0-guess save
    store.config = c;
    _play(store.fresh(c));
  }

  Future<void> _settings() async {
    final c = await showConfigSheet(context, store.config, title: 'Settings', action: 'Save');
    if (c != null) store.config = c;
  }

  @override
  Widget build(BuildContext context) {
    final saved = store.saved;
    Widget button(String label, Color color, VoidCallback onTap, {String? sub, IconData? icon}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: _Pressable(
        onTap: onTap,
        child: SizedBox(
          width: 270,
          height: sub == null ? 58 : 68,
          child: WoodBox(
            color: color,
            radius: 16,
            seed: label.hashCode,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[Icon(icon, color: Wood.ink), const SizedBox(width: 8)],
                    Text(label, style: txt(22, weight: 700)),
                  ],
                ),
                if (sub != null) Text(sub, style: txt(13, weight: 500)),
              ],
            ),
          ),
        ),
      ),
    );

    return Scaffold(
      body: Background(
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final (i, ch) in 'WORDIE'.split('').indexed)
                      Padding(
                        padding: const EdgeInsets.all(3),
                        child: _Tile(letter: ch, color: const [Wood.green, Wood.yellow, Wood.oak][i % 3], size: 48, seed: i + 40),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Text('guess the word', style: txt(18, color: Wood.walnut, weight: 500)),
                const SizedBox(height: 40),
                if (saved != null)
                  button(
                    'Continue',
                    Wood.green,
                    () => _play(saved),
                    icon: Icons.play_arrow_rounded,
                    sub: '${saved.length} letters · row ${saved.rowIndex + 1}/${saved.length}',
                  ),
                button('New Game', saved == null ? Wood.green : Wood.oak, _newGame, icon: Icons.add_rounded),
                button(
                  'Statistics',
                  Wood.oak,
                  () => showDialog(context: context, builder: (_) => _StatsDialog(store.stats)),
                  icon: Icons.bar_chart_rounded,
                ),
                button('Settings', Wood.oak, _settings, icon: Icons.tune_rounded),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class GameScreen extends StatefulWidget {
  final Store store;
  final Game initial;
  const GameScreen(this.store, this.initial, {super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  Store get store => widget.store;
  late Game game;
  int gameId = 0, shake = 0;
  String? toast;
  bool toastOn = false;

  @override
  void initState() {
    super.initState();
    _start(widget.initial);
  }

  // autosave on every change: typing, boosters, guesses
  void _start(Game g) {
    game = g..addListener(() => setState(() {
      store.save(game);
    }));
    gameId++;
    store.save(g);
  }

  void _submit() {
    final err = game.submit();
    if (err != null) {
      setState(() => shake++);
      final id = shake;
      setState(() {
        toast = err;
        toastOn = true;
      });
      Future.delayed(const Duration(milliseconds: 1300), () {
        if (mounted && id == shake) setState(() => toastOn = false);
      });
      return;
    }
    if (game.status != Status.playing) {
      store.record(game);
      final id = gameId;
      Future.delayed(Duration(milliseconds: _flipMs * game.length + 300), () {
        if (mounted && id == gameId) _showResult();
      });
    }
  }

  Future<void> _newGame() async {
    if (game.status == Status.playing && game.guesses.isNotEmpty) {
      if (!await confirmAbandon(context)) return;
      game.forfeit(); // listener autosave drops the save
      store.record(game);
    }
    if (!mounted) return;
    final c = await showConfigSheet(context, store.config, title: 'New Game', action: 'Start');
    if (c == null) return;
    store.abandonSaved();
    store.config = c;
    setState(() => _start(store.fresh(c)));
  }

  void _showResult() => showDialog(
    context: context,
    builder: (ctx) => _ResultDialog(
      game,
      store.stats,
      store.meanings[game.answer],
      onNew: () {
        Navigator.pop(ctx);
        _newGame();
      },
      onHome: () {
        Navigator.pop(ctx);
        Navigator.pop(context);
      },
    ),
  );

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.enter) {
      _submit();
    } else if (k == LogicalKeyboardKey.backspace) {
      game.backspace();
    } else if (k == LogicalKeyboardKey.digit1) {
      game.useHint();
    } else if (k == LogicalKeyboardKey.digit2) {
      game.useStrike();
    } else if (RegExp(r'^[a-zA-Z]$').hasMatch(k.keyLabel)) {
      game.type(k.keyLabel.toLowerCase());
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Focus(
        autofocus: true,
        onKeyEvent: _onKey,
        child: Background(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(
              children: [
                const SizedBox(height: 6),
                _topBar(),
                const SizedBox(height: 10),
                _status(),
                Expanded(
                  child: Stack(
                    children: [
                      _grid(),
                      Positioned(
                        top: 4,
                        left: 0,
                        right: 0,
                        child: IgnorePointer(
                          child: AnimatedOpacity(
                            opacity: toastOn ? 1 : 0,
                            duration: const Duration(milliseconds: 150),
                            child: Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                decoration: BoxDecoration(color: Wood.walnut, borderRadius: BorderRadius.circular(12)),
                                child: Text(toast ?? '', style: txt(16, color: Colors.white)),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                _Keyboard(game),
                const SizedBox(height: 10),
                _actions(),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _topBar() => Row(
    children: [
      _WoodButton(icon: Icons.home_rounded, onTap: () => Navigator.pop(context)),
      Expanded(
        child: Center(
          child: SizedBox(
            width: 170,
            height: 48,
            child: WoodBox(
              color: Wood.walnut,
              radius: 12,
              seed: 99,
              child: Text('Wordie', style: txt(28, color: const Color(0xFFFDF1E4), weight: 700)),
            ),
          ),
        ),
      ),
      _WoodButton(icon: Icons.refresh_rounded, onTap: _newGame),
    ],
  );

  Widget _status() => Text(
    switch (game.status) {
      Status.won => 'Solved in ${game.guesses.length}/${game.length}',
      Status.lost || Status.dnf => 'The word was ${game.answer.toUpperCase()}',
      Status.playing => '${game.length} letters · row ${game.rowIndex + 1}/${game.length}',
    },
    style: txt(15, color: Wood.walnut, weight: 500),
  );

  Widget _actions() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 6),
    child: Row(
      children: [
        _BoosterButton(icon: Icons.search_rounded, count: game.hintsLeft, enabled: game.canHint, onTap: game.useHint),
        const SizedBox(width: 14),
        Expanded(
          // ponytail: still tappable when grey so a full-but-unknown word shakes + says why
          child: game.status != Status.playing
              ? _Pressable(
                  onTap: _newGame,
                  child: SizedBox(
                    height: 54,
                    child: WoodBox(color: Wood.green, radius: 27, seed: 12, child: Text('NEW GAME', style: txt(22, weight: 700))),
                  ),
                )
              : _Pressable(
                  onTap: _submit,
                  child: SizedBox(
                    height: 54,
                    child: WoodBox(
                      color: game.canSubmit ? Wood.green : Wood.grey,
                      radius: 27,
                      seed: 11,
                      child: Text('SUBMIT', style: txt(22, color: game.canSubmit ? Wood.ink : Colors.white, weight: 700)),
                    ),
                  ),
                ),
        ),
        const SizedBox(width: 14),
        _BoosterButton(icon: Icons.track_changes_rounded, count: game.strikesLeft, enabled: game.canStrike, onTap: game.useStrike),
      ],
    ),
  );

  Widget _grid() => LayoutBuilder(
    builder: (context, box) {
      final n = game.length;
      const gap = 6.0;
      final tile = [(box.maxWidth - 24 - gap * (n - 1)) / n, (box.maxHeight - 24 - gap * (n - 1)) / n, 64.0].reduce(min);
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var r = 0; r < n; r++)
              Padding(
                padding: EdgeInsets.only(bottom: r == n - 1 ? 0 : gap),
                child: _row(r, tile, gap),
              ),
          ],
        ),
      );
    },
  );

  Widget _row(int r, double size, double gap) {
    final n = game.length;
    final current = r == game.rowIndex && game.status == Status.playing;
    Widget tileAt(int c) {
      final key = '$gameId-$r-$c';
      if (r < game.guesses.length) {
        return _FlipTile(
          key: ValueKey('$key-done'),
          letter: game.guesses[r][c],
          state: game.results[r][c],
          index: c,
          size: size,
          seed: r * 10 + c,
        );
      }
      final letter = current ? game.row[c] : null;
      final ghost = current && letter == null && game.hinted.contains(c); // placeholder until something is typed here
      return _Tile(
        key: ValueKey('$key-$letter'),
        letter: ghost ? game.answer[c] : letter,
        color: ghost ? Wood.green : (letter == null ? Wood.birch : Wood.oak),
        raised: letter != null,
        size: size,
        seed: r * 10 + c,
        pop: letter != null,
      );
    }

    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var c = 0; c < n; c++)
          Padding(
            padding: EdgeInsets.only(right: c == n - 1 ? 0 : gap),
            child: tileAt(c),
          ),
      ],
    );
    if (!current) return row;
    return TweenAnimationBuilder<double>(
      key: ValueKey('shake-$shake'),
      tween: Tween(begin: shake == 0 ? 1 : 0, end: 1),
      duration: const Duration(milliseconds: 450),
      builder: (_, t, child) => Transform.translate(offset: Offset(sin(t * pi * 6) * 10 * (1 - t), 0), child: child),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          boxShadow: const [BoxShadow(color: Color(0x66FFD27F), blurRadius: 14, spreadRadius: 2)],
        ),
        child: row,
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final String? letter;
  final Color color;
  final bool raised, pop;
  final double size;
  final int seed;
  const _Tile({super.key, this.letter, required this.color, required this.size, required this.seed, this.raised = true, this.pop = false});

  @override
  Widget build(BuildContext context) {
    final box = SizedBox.square(
      dimension: size,
      child: WoodBox(
        color: raised ? color : color.withValues(alpha: 0.55),
        raised: raised,
        seed: seed,
        child: letter == null
            ? null
            : Text(letter!.toUpperCase(), style: txt(size * 0.5, color: color == Wood.grey ? Colors.white : Wood.ink, weight: 700)),
      ),
    );
    if (!pop) return box;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 1.15, end: 1),
      duration: const Duration(milliseconds: 120),
      builder: (_, s, child) => Transform.scale(scale: s, child: child),
      child: box,
    );
  }
}

/// Flips once when first built; tiles are staggered by [index].
class _FlipTile extends StatelessWidget {
  final String letter;
  final LetterState state;
  final int index, seed;
  final double size;
  const _FlipTile({super.key, required this.letter, required this.state, required this.index, required this.size, required this.seed});

  @override
  Widget build(BuildContext context) {
    final total = _flipMs * (index + 1);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: total),
      builder: (_, t, _) {
        final p = ((t * total - _flipMs * index) / _flipMs).clamp(0.0, 1.0);
        final front = p < 0.5;
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.002)
            ..rotateX(front ? p * pi : (p - 1) * pi),
          child: _Tile(letter: letter, color: front ? Wood.oak : stateColor(state), size: size, seed: seed),
        );
      },
    );
  }
}

class _Keyboard extends StatelessWidget {
  final Game game;
  const _Keyboard(this.game);

  @override
  Widget build(BuildContext context) {
    Widget key(String label, {int flex = 2, VoidCallback? onTap, Color? color, IconData? icon, bool struck = false}) => Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2.5, vertical: 4),
        child: _Pressable(
          onTap: onTap,
          child: SizedBox(
            height: 54,
            child: WoodBox(
              color: color ?? Wood.oak,
              radius: 7,
              seed: label.hashCode,
              child: icon != null
                  ? Icon(icon, color: Wood.ink, size: 22)
                  : Text(
                      label.toUpperCase(),
                      style: txt(label.length > 1 ? 13 : 20, color: color == Wood.grey ? Colors.white : Wood.ink).copyWith(
                        decoration: struck ? TextDecoration.lineThrough : null,
                        decorationThickness: 3,
                        decorationColor: color == Wood.grey ? Colors.white : Wood.ink,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );

    Widget letter(String l) {
      final struck = game.struck.contains(l);
      final s = game.keys[l] ?? LetterState.none;
      return key(l, onTap: () => game.type(l), struck: struck, color: struck ? Wood.grey : (s == LetterState.none ? null : stateColor(s)));
    }

    return Column(
      children: [
        Row(children: [for (final l in 'qwertyuiop'.split('')) letter(l)]),
        Row(children: [const Spacer(), for (final l in 'asdfghjkl'.split('')) letter(l), const Spacer()]),
        Row(
          children: [
            const Spacer(),
            for (final l in 'zxcvbnm'.split('')) letter(l),
            key('back', flex: 5, onTap: game.backspace, icon: Icons.backspace_outlined),
          ],
        ),
      ],
    );
  }
}

/// Sinks slightly while pressed.
class _Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  const _Pressable({required this.child, this.onTap});
  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool down = false;
  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTapDown: widget.onTap == null ? null : (_) => setState(() => down = true),
    onTapUp: (_) => setState(() => down = false),
    onTapCancel: () => setState(() => down = false),
    onTap: widget.onTap == null
        ? null
        : () {
            HapticFeedback.selectionClick();
            widget.onTap!();
          },
    child: AnimatedSlide(offset: Offset(0, down ? 0.04 : 0), duration: const Duration(milliseconds: 60), child: widget.child),
  );
}

class _WoodButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _WoodButton({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) => _Pressable(
    onTap: onTap,
    child: SizedBox.square(
      dimension: 44,
      child: WoodBox(
        color: Wood.oak,
        radius: 12,
        seed: icon.codePoint,
        child: Icon(icon, color: Wood.ink, size: 26),
      ),
    ),
  );
}

class _BoosterButton extends StatelessWidget {
  final IconData icon;
  final int count;
  final bool enabled;
  final VoidCallback onTap;
  const _BoosterButton({required this.icon, required this.count, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: enabled ? 1 : 0.45,
    child: _Pressable(
      onTap: enabled ? onTap : null,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          SizedBox.square(
            dimension: 48,
            child: WoodBox(
              color: Wood.oak,
              radius: 24,
              seed: icon.codePoint,
              child: Icon(icon, color: Wood.ink, size: 26),
            ),
          ),
          Positioned(
            right: -4,
            top: -4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: Wood.walnut,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: Text('$count', style: txt(12, color: Colors.white)),
            ),
          ),
        ],
      ),
    ),
  );
}

class _Stepper extends StatelessWidget {
  final String label;
  final int value, lo, hi;
  final ValueChanged<int> onChanged;
  const _Stepper(this.label, this.value, this.lo, this.hi, this.onChanged);

  @override
  Widget build(BuildContext context) {
    Widget btn(IconData i, int to) => Opacity(
      opacity: to < lo || to > hi ? 0.35 : 1,
      child: _Pressable(
        onTap: to < lo || to > hi ? null : () => onChanged(to),
        child: SizedBox.square(
          dimension: 40,
          child: WoodBox(
            color: Wood.oak,
            radius: 20,
            seed: label.hashCode + i.codePoint,
            child: Icon(i, color: Wood.ink),
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(child: Text(label, style: txt(18, weight: 500))),
          btn(Icons.remove_rounded, value - 1),
          SizedBox(
            width: 44,
            child: Text('$value', textAlign: TextAlign.center, style: txt(22, weight: 700)),
          ),
          btn(Icons.add_rounded, value + 1),
        ],
      ),
    );
  }
}

class _NewGameSheet extends StatefulWidget {
  final GameConfig initial;
  final String title, action;
  const _NewGameSheet(this.initial, {required this.title, required this.action});
  @override
  State<_NewGameSheet> createState() => _NewGameSheetState();
}

class _NewGameSheetState extends State<_NewGameSheet> {
  late var c = widget.initial;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.title, style: txt(26, weight: 700)),
          const SizedBox(height: 8),
          _Stepper(
            'Word length',
            c.length,
            4,
            7,
            (v) => setState(() => c = GameConfig(length: v, hints: c.hints, strikeTaps: c.strikeTaps, strikeLetters: c.strikeLetters)),
          ),
          _Stepper(
            'Hints 🔍',
            c.hints,
            0,
            3,
            (v) => setState(() => c = GameConfig(length: c.length, hints: v, strikeTaps: c.strikeTaps, strikeLetters: c.strikeLetters)),
          ),
          _Stepper(
            'Strikes 🎯',
            c.strikeTaps,
            0,
            3,
            (v) => setState(() => c = GameConfig(length: c.length, hints: c.hints, strikeTaps: v, strikeLetters: c.strikeLetters)),
          ),
          _Stepper(
            'Letters per strike',
            c.strikeLetters,
            1,
            5,
            (v) => setState(() => c = GameConfig(length: c.length, hints: c.hints, strikeTaps: c.strikeTaps, strikeLetters: v)),
          ),
          Text('${c.length} guesses to find a ${c.length}-letter word', style: txt(14, color: Wood.walnut, weight: 400)),
          const SizedBox(height: 16),
          _Pressable(
            onTap: () => Navigator.pop(context, c),
            child: SizedBox(
              height: 52,
              width: double.infinity,
              child: WoodBox(
                color: Wood.green,
                radius: 14,
                seed: 7,
                child: Text(widget.action, style: txt(22, weight: 700)),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _Panel extends StatelessWidget {
  final List<Widget> children;
  const _Panel(this.children);
  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: const Color(0xFFFDF1E4),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(24),
      side: const BorderSide(color: Wood.oak, width: 3),
    ),
    child: Padding(
      padding: const EdgeInsets.all(22),
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    ),
  );
}

Widget _line(String k, String v, {bool bold = false}) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 3),
  child: Row(
    children: [
      Expanded(
        child: Text(k, style: txt(16, weight: bold ? 700 : 400)),
      ),
      Text(v, style: txt(16, weight: bold ? 700 : 500)),
    ],
  ),
);

Widget _panelButton(String label, Color color, VoidCallback onTap, {double height = 50, double size = 20}) => _Pressable(
  onTap: onTap,
  child: SizedBox(
    height: height,
    width: double.infinity,
    child: WoodBox(color: color, radius: 14, seed: label.hashCode, child: Text(label, style: txt(size, weight: 700))),
  ),
);

/// true = abandon the current game.
Future<bool> confirmAbandon(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (ctx) => _Panel([
        Text('Start over?', style: txt(26, weight: 700)),
        const SizedBox(height: 10),
        Text(
          'Do you want to abandon this game and start new? Note that this will impact your stats.',
          textAlign: TextAlign.center,
          style: txt(16, weight: 400),
        ),
        const SizedBox(height: 18),
        _panelButton('Here We Go Again', Wood.green, () => Navigator.pop(ctx, true)),
        const SizedBox(height: 10),
        _panelButton('Then I Will Finish', Wood.oak, () => Navigator.pop(ctx, false), height: 44, size: 18),
      ]),
    ) ??
    false;

class _ResultDialog extends StatelessWidget {
  final Game game;
  final Stats stats;
  final String? meaning;
  final VoidCallback onNew, onHome;
  const _ResultDialog(this.game, this.stats, this.meaning, {required this.onNew, required this.onHome});

  @override
  Widget build(BuildContext context) {
    final s = game.result;
    final hints = game.used.where((b) => b.hint).length;
    final struck = game.used.fold(0, (a, b) => a + b.letters);
    return _Panel([
      Text(s != null ? 'Solved!' : 'Out of rows', style: txt(28, weight: 700)),
      const SizedBox(height: 12),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < game.length; i++)
            Padding(
              padding: const EdgeInsets.all(2),
              child: _Tile(letter: game.answer[i], color: s != null ? Wood.green : Wood.yellow, size: 36, seed: i),
            ),
        ],
      ),
      if (s != null && meaning != null) ...[
        const SizedBox(height: 8),
        Text(meaning!, textAlign: TextAlign.center, style: txt(15, color: Wood.walnut, weight: 400).copyWith(fontStyle: FontStyle.italic)),
      ],
      const SizedBox(height: 14),
      if (s != null) ...[
        _line('Solved in row ${game.guesses.length}/${game.length}', '+${s.guessPts.round()}'),
        _line('Hints used: $hints', '−${s.hintCost.round()}'),
        _line('Letters struck: $struck', '−${s.strikeCost.round()}'),
        _line('${game.length}-letter bonus', '×${s.mult}'),
        const Divider(color: Wood.oak),
        _line('Score', '${s.total}', bold: true),
      ] else
        _line('Score', '0', bold: true),
      const SizedBox(height: 6),
      _line('Daily streak', '${stats.streakOn(DateTime.now())}'),
      const SizedBox(height: 16),
      _panelButton('New Game', Wood.green, onNew),
      const SizedBox(height: 10),
      _panelButton('Home', Wood.oak, onHome, height: 44, size: 18),
    ]);
  }
}

class _StatsDialog extends StatelessWidget {
  final Stats stats;
  const _StatsDialog(this.stats);

  @override
  Widget build(BuildContext context) {
    final s = stats;
    Widget cell(String v, String k) => Expanded(
      child: Column(
        children: [
          Text(v, style: txt(24, weight: 700)),
          Text(k, textAlign: TextAlign.center, style: txt(12, color: Wood.walnut, weight: 400)),
        ],
      ),
    );
    return _Panel([
      Text('Statistics', style: txt(26, weight: 700)),
      const SizedBox(height: 12),
      Row(
        children: [
          cell('${s.played}', 'Played'),
          cell(s.played == 0 ? '0' : '${(100 * s.wins / s.played).round()}', 'Win %'),
          cell('${s.dnf}', 'DNF'),
        ],
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          cell('${s.streakOn(DateTime.now())}', 'Daily streak'),
          cell('${s.maxStreak}', 'Max streak'),
          cell(s.avgLength.toStringAsFixed(1), 'Avg word length'),
        ],
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          cell('${s.best}', 'Best'),
          cell(s.wins == 0 ? '0' : '${(s.total / s.wins).round()}', 'Avg score'),
          cell('${s.noHints}', 'No hints used'),
        ],
      ),
    ]);
  }
}
