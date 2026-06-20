import re, time, urllib.request

def fetch(n):
    url=f"https://shamela.ws/book/23636/{n}"
    req=urllib.request.Request(url, headers={'User-Agent':'Mozilla/5.0'})
    for attempt in range(3):
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                return r.read().decode('utf-8','ignore')
        except Exception as e:
            time.sleep(1.0)
    return ''

NASS=re.compile(r'<div[^>]*class="[^"]*nass[^"]*"[^>]*>(.*?)</div>\s*(?:<div|<section|<footer|<script)', re.S)
out=open('mufradat_raw.txt','w',encoding='utf-8')
LAST=881
for n in range(1, LAST+1):
    h=fetch(n)
    m=NASS.search(h)
    nass=m.group(1) if m else ''
    out.write(f"\n<<<PAGE {n}>>>\n")
    out.write(nass)
    if n % 50 == 0:
        out.flush()
        print(f"scraped {n}/{LAST}", flush=True)
    time.sleep(0.12)
out.close()
print("DONE", flush=True)
