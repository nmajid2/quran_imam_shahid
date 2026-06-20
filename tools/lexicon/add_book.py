#!/usr/bin/env python3
"""Fold a second dictionary (e.g. al-Tahqiq) into the bundled lexicon.db.gz.

Usage:
    python3 add_book.py <book_id> <name> <name_fa> <author> <input_file>

<input_file> is one of:
  - .json : { "<root>": "<entry text>", ... }
  - .tsv  : lines of  <root>\\t<entry text>

Roots are canonicalized and matched to the Quran corpus roots already present in
word_root, so they don't need to match exactly. Re-gzips the app asset in place.
"""
import sys, os, json, gzip, sqlite3, shutil, tempfile

ASSET = os.path.join(os.path.dirname(__file__),
                     '../../app/assets/lexicon/lexicon.db.gz')

def canon(r):
    return (r.replace('أ','ا').replace('إ','ا').replace('آ','ا').replace('ٱ','ا')
             .replace('ى','ي').replace('ؤ','و').replace('ئ','ي').strip())

def variants(r):
    c = canon(r); out = {c}; n = len(c)
    if n == 2:
        out |= {c+c[-1], c+'و', c+'ي', c+'ا', c[0]+'و'+c[1], c[0]+'ي'+c[1]}
    if n == 3:
        if c[2] in 'ويا': out |= {c[:2]+'و', c[:2]+'ي'}
        if c[1] == 'ا':   out |= {c[0]+'و'+c[2], c[0]+'ي'+c[2]}
        out |= {c.replace('ا','أ',1)}
    return {v for v in out if v}

def load_input(path):
    if path.endswith('.json'):
        return json.load(open(path, encoding='utf-8'))
    out = {}
    for line in open(path, encoding='utf-8'):
        if '\t' in line:
            r, t = line.split('\t', 1)
            out[r.strip()] = t.strip()
    return out

def main():
    if len(sys.argv) != 6:
        print(__doc__); sys.exit(1)
    book_id, name, name_fa, author, infile = sys.argv[1:]
    data = load_input(infile)
    print(f'input entries: {len(data)}')

    work = tempfile.mkdtemp()
    dbpath = os.path.join(work, 'lexicon.db')
    with gzip.open(ASSET, 'rb') as f, open(dbpath, 'wb') as o:
        shutil.copyfileobj(f, o)
    con = sqlite3.connect(dbpath); cur = con.cursor()

    corpus_roots = {r[0] for r in cur.execute('SELECT DISTINCT root FROM word_root')}
    ccorpus = {}
    for r in corpus_roots: ccorpus.setdefault(canon(r), r)

    matched = 0; unmatched = []
    rows = []
    for root, content in data.items():
        hit = next((ccorpus[v] for v in variants(root) if v in ccorpus), None)
        if hit:
            rows.append((book_id, hit, content)); matched += 1
        else:
            unmatched.append(root)
    cur.executemany('INSERT OR REPLACE INTO entry(book,root,content) VALUES(?,?,?)', rows)
    con.commit()
    print(f'matched to corpus roots: {matched}/{len(data)}')
    if unmatched: print(f'unmatched ({len(unmatched)}): {unmatched[:20]}')
    print(f"entry rows now: {cur.execute('SELECT count(*) FROM entry').fetchone()[0]}")
    con.close()

    with open(dbpath, 'rb') as f, gzip.open(ASSET, 'wb', compresslevel=9) as o:
        shutil.copyfileobj(f, o)
    print(f'rewrote {ASSET} ({os.path.getsize(ASSET)//1024} KB)')
    print(f"\nNow add to lexicon_db.dart:\n  LexiconBook('{book_id}', '{name}', '{name_fa}', '{author}'),")

if __name__ == '__main__':
    main()
