import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ui.dart';
import 'wood.dart';

typedef WordList = ({List<String> answers, Set<String> guesses});

Future<Map<int, WordList>> loadWords() async {
  Future<List<String>> read(String f) async =>
      (await rootBundle.loadString('assets/words/$f.txt')).split('\n').where((w) => w.isNotEmpty).toList();
  return {for (var n = 4; n <= 7; n++) n: (answers: await read('answer_$n'), guesses: (await read('guess_$n')).toSet())};
}

/// word -> short gloss, from tool/build_meanings.py
Future<Map<String, String>> loadMeanings() async => {
  for (final l in (await rootBundle.loadString('assets/words/meanings.txt')).split('\n'))
    if (l.contains('\t')) l.split('\t')[0]: l.split('\t')[1],
};

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final (words, meanings, prefs) = (await loadWords(), await loadMeanings(), await SharedPreferences.getInstance());
  runApp(
    MaterialApp(
      title: 'Wordie',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'Fredoka',
        colorScheme: ColorScheme.fromSeed(seedColor: Wood.oak),
      ),
      home: HomeScreen(Store(prefs, words, meanings)),
    ),
  );
}
