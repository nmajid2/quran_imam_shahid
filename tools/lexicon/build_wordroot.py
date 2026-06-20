import re, collections, difflib, json

# Portable normalization — MUST be mirrored exactly in the Dart app.
HARAKAT = re.compile('[ؐ-ؚـً-ٟۖ-ۭ࣓-ࣿ]')
def norm(t):
    t = t.replace('ٰ', 'ا')   # dagger alef -> alef
    t = HARAKAT.sub('', t)
    t = (t.replace('ٱ', 'ا')  # alef wasla -> alef
           .replace('أ', 'ا').replace('إ', 'ا').replace('آ', 'ا')
           .replace('ى', 'ي')  # alef maksura -> ya
           .replace('ة', 'ه')) # ta marbuta -> ha
    return t.strip()

ARLET = re.compile('[ء-ي]')
def is_word(t): return bool(ARLET.search(t))

cw = collections.defaultdict(dict)
cr = collections.defaultdict(dict)
for line in open('m.txt', encoding='utf-8'):
    line = line.rstrip('\n')
    if not line: continue
    p = line.split('\t')
    if len(p) < 4: continue
    s, a, w, g = (int(x) for x in p[0].split(':'))
    cw[(s, a)].setdefault(w, '')
    cw[(s, a)][w] += p[1]
    m = re.search(r'ROOT:([^|]+)', p[3])
    if m and w not in cr[(s, a)]: cr[(s, a)][w] = m.group(1)

tan = {}
for line in open('/home/zenrock/github/quran_imam_shahid/gateway/qis/content/quran_data/ar.simple.txt', encoding='utf-8'):
    line = line.strip()
    if not line or line.startswith('#'): continue
    pp = line.split('|', 2)
    if len(pp) == 3: tan[(int(pp[0]), int(pp[1]))] = pp[2]

BASM = ['بسم', 'الله', 'الرحمن', 'الرحيم']
form2root = collections.defaultdict(collections.Counter)
pairs = 0
for (s, a), txt in tan.items():
    tw = [t for t in txt.split() if is_word(t)]
    if a == 1 and s not in (1, 9) and [norm(re.sub('[^ء-ي]', '', x)) for x in tw[:4]] == BASM:
        tw = tw[4:]
    cwords = [cw[(s, a)][k] for k in sorted(cw[(s, a)])]
    croots = [cr[(s, a)].get(k) for k in sorted(cw[(s, a)])]
    tn = [norm(x) for x in tw]; cn = [norm(x) for x in cwords]
    if len(tn) == len(cn):
        pairsiter = list(zip(tn, croots))
    else:
        sm = difflib.SequenceMatcher(None, tn, cn, autojunk=False)
        pairsiter = []
        for tag, i1, i2, j1, j2 in sm.get_opcodes():
            if tag in ('equal', 'replace'):
                for off in range(min(i2 - i1, j2 - j1)):
                    pairsiter.append((tn[i1 + off], croots[j1 + off]))
    for nf, rt in pairsiter:
        if rt and nf: form2root[nf][rt] += 1; pairs += 1

final = {f: c.most_common(1)[0][0] for f, c in form2root.items()}
json.dump(final, open('word_root.json', 'w', encoding='utf-8'), ensure_ascii=False)
print('distinct normalized forms with root:', len(final))

tot = hit = 0
for (s, a), txt in tan.items():
    for t in txt.split():
        if not is_word(t): continue
        tot += 1
        if norm(t) in final: hit += 1
print(f'Tanzil token coverage: {hit}/{tot} = {100*hit/tot:.2f}%')
for w in ['الرحيم', 'الكتاب', 'الصلاة', 'الرَّحْمَٰنِ', 'يَعْلَمُونَ']:
    print(' ', w, '->', final.get(norm(w)))
