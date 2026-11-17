import sys,collections
def ct(s):
    s=s.replace(",",".");p=s.split(":");return float(p[0])*60+float(p[1])
rows=collections.defaultdict(dict)
for l in open(sys.argv[1]):
    f=l.split()
    if len(f)<6: continue
    t=float(f[0].replace(",","."));rows[t][(f[1],f[5])]=(ct(f[3]),int(f[4]))
ts=sorted(rows);prev={}
step=float(sys.argv[2]) if len(sys.argv)>2 else 2
last=-99;acc=collections.Counter();rss={}
for t in ts:
    for k,(c,r) in rows[t].items():
        if k in prev: acc[k[1]]+=c-prev[k]
        prev[k]=c;rss[k[1]]=r
    if t-last>=step:
        tot=sum(acc.values())
        print(f"{t:5.1f}s cpu {tot:5.2f}s/{step:.0f}s  "+" ".join(f"{n}:{v:.2f}" for n,v in acc.most_common(4) if v>0.05))
        acc.clear();last=t
print("rss MB:"," ".join(f"{n}:{r/1024:.0f}" for n,r in sorted(rss.items(),key=lambda x:-x[1])[:8]))
