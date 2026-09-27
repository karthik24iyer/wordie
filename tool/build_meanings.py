"""Writes assets/words/meanings.txt ("word<TAB>short gloss") for every answer word from WordNet. Needs: pip install nltk."""
import os
import nltk
nltk.download('wordnet', quiet=True)
from nltk.corpus import wordnet as wn

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
out, missing = [], 0
for n in range(4, 8):
    for w in open(f'{root}/assets/words/answer_{n}.txt').read().split():
        s = wn.synsets(w)
        if not s:
            missing += 1
            continue
        # first sense, first clause only: "in few words"
        g = s[0].definition().split(';')[0].strip()
        out.append(f'{w}\t{g[0].upper() + g[1:]}')
open(f'{root}/assets/words/meanings.txt', 'w').write('\n'.join(out) + '\n')
print(f'{len(out)} glosses, {missing} words without one')
