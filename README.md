# Wordie

A cozy Wordle-style word game in Flutter — wooden tiles on a pastel board.

- Word length 4–7; an L-letter word gets L guesses
- Green = right letter, right spot · Yellow = in the word, wrong spot
- 🔍 Hints reveal a letter in place · 🎯 Strikes grey out letters not in the word (counts configurable per game)
- Score rewards fewer guesses and longer words; boosters cost less the later you use them
- Auto-saves in-progress games, local stats, fully offline

## Run

```sh
flutter run
flutter test                       # logic tests
flutter drive --driver=test_driver/integration_test.dart \
  --target=integration_test/app_test.dart   # UI tap-through, screenshots in build/shots/
```

## Words

`tool/build_words.sh` regenerates `assets/words/`: valid guesses come from ENABLE (public domain); answers are ENABLE ∩ SCOWL size ≤35 common words, minus plurals and a small blocklist.

## Icon

`python3 tool/make_icon.py` (needs Pillow) draws the icon and writes all iOS/Android sizes.
