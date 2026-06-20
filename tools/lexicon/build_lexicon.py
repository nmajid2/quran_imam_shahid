import re, json, html, sqlite3, os

raw=open('mufradat_raw.txt',encoding='utf-8').read()
raw=re.sub(r'<<<PAGE \d+>>>','',raw)
muf2corpus=json.load(open('muf2corpus.json',encoding='utf-8'))
word_root=json.load(open('word_root.json',encoding='utf-8'))

rootpat=re.compile(r'^[ء-ي]{2,6}$')
# locate root-entry markers (c4 spans whose bracket content is a bare root)
marker=re.compile(r'<span class="c4">\[([^\]]*)\]</span>')
positions=[]
for m in marker.finditer(raw):
    content=m.group(1).strip()
    if rootpat.match(content):
        positions.append((m.start(), m.end(), content))

def clean(htmlfrag):
    t=re.sub(r'<a\b[^>]*>.*?</a>',' ',htmlfrag,flags=re.S)   # drop copy buttons
    t=re.sub(r'<[^>]+>',' ',t)
    t=html.unescape(t)
    t=t.replace('«',' ').replace('»',' ')
    t=re.sub(r'[ \t]+',' ',t)
    t=re.sub(r'\n\s*\n+','\n\n',t)
    return t.strip()

entries={}   # corpus_root -> text
skipped=0
for i,(s,e,root) in enumerate(positions):
    end = positions[i+1][0] if i+1<len(positions) else len(raw)
    body=clean(raw[e:end])
    cr=muf2corpus.get(root)
    if not cr: skipped+=1; continue
    if len(body)<2: continue
    if cr in entries: entries[cr]+= "\n\n"+body
    else: entries[cr]=body
print('root entries placed (by corpus root):',len(entries),' skipped(no corpus match):',skipped)

# build sqlite
out='lexicon.db'
if os.path.exists(out): os.remove(out)
con=sqlite3.connect(out); cur=con.cursor()
cur.execute('CREATE TABLE word_root(form TEXT PRIMARY KEY, root TEXT)')
cur.execute('CREATE TABLE entry(book TEXT, root TEXT, content TEXT, PRIMARY KEY(book,root))')
cur.executemany('INSERT OR REPLACE INTO word_root VALUES(?,?)', list(word_root.items()))
cur.executemany('INSERT OR REPLACE INTO entry VALUES(?,?,?)',
                [('mufradat',r,t) for r,t in entries.items()])
con.commit()
# stats
print('word_root rows:', cur.execute('select count(*) from word_root').fetchone()[0])
print('entry rows:', cur.execute('select count(*) from entry').fetchone()[0])
# sample lookup: word الكتاب
f='الكتاب'
from build_wordroot import norm  # reuse
nf=norm(f)
r=cur.execute('select root from word_root where form=?',(nf,)).fetchone()
print('الكتاب norm=',nf,'root=',r)
if r:
    ent=cur.execute('select content from entry where book=? and root=?',('mufradat',r[0])).fetchone()
    print('entry preview:', (ent[0][:200] if ent else None))
con.close()
print('db size:', os.path.getsize(out), 'bytes')
