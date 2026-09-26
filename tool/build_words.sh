#!/bin/sh
# Regenerates assets/words/. Guesses = ENABLE (public domain). Answers = ENABLE ∩ SCOWL ≤35 minus blocklist.
set -e
cd "$(dirname "$0")/.."
T=$(mktemp -d)
curl -sSL -o "$T/enable.txt" https://raw.githubusercontent.com/dolph/dictionary/master/enable1.txt
curl -sSL https://downloads.sourceforge.net/wordlist/scowl-2020.12.07.tar.gz | tar xz -C "$T"
F="$T/scowl-2020.12.07/final"
cat "$F"/english-words.10 "$F"/english-words.20 "$F"/english-words.35 \
    "$F"/american-words.10 "$F"/american-words.20 "$F"/american-words.35 \
  | iconv -f latin1 -t utf-8 | grep -E '^[a-z]+$' | sort -u > "$T/common.txt"
# ponytail: tiny hand blocklist, extend if something rude shows up as an answer
BLOCK='^(anal|anus|arse|bitch|boob|boobs|butt|clit|cock|coon|crap|cunt|damn|dick|dildo|dyke|fag|fags|faggot|fuck|gook|hell|homo|jerk|jizz|kike|nazi|nigga|nigger|penis|piss|poop|porn|prick|pube|pussy|rape|raped|rapes|rapist|semen|sex|sexy|shit|slut|sluts|spic|tits|titty|turd|twat|vagina|wank|whore|whores|retard|bastard|pimp|horny|nude|nudes|orgy|orgasm|erotic|condom|sperm|scrotum)$'
tr -d '\r' < "$T/enable.txt" | grep -E '^[a-z]+$' | sort -u > "$T/enable.sorted"
mkdir -p assets/words
for n in 4 5 6 7; do
  grep -E "^[a-z]{$n}\$" "$T/enable.sorted" > "assets/words/guess_$n.txt"
  comm -12 "assets/words/guess_$n.txt" "$T/common.txt" | grep -Ev "$BLOCK" \
    | awk -v all="$T/enable.sorted" 'BEGIN{while((getline w < all)>0) d[w]=1} !(/s$/ && d[substr($0,1,length($0)-1)])' \
    > "assets/words/answer_$n.txt"  # drop plain plurals/3rd-person (cats, sews)
  echo "$n: $(wc -l < assets/words/guess_$n.txt) guesses, $(wc -l < assets/words/answer_$n.txt) answers"
done
rm -rf "$T"
