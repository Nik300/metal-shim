import csv,statistics as st,math,sys
r=list(csv.DictReader(open(sys.argv[1]),delimiter="\t"))
for x in r:
    for k in x:
        if k!="file": x[k]=float(x[k])
print("rows",len(r))
def q(lo,hi):
    s=[x for x in r if lo<=x["bytes"]<hi]
    if not s: return
    f=lambda k: st.median([x[k] for x in s])
    print(f"| {lo/1000:g}–{hi/1000:g} KB | {len(s)} | {f('bytes')/1000:.1f} | {f('compile'):.1f} | {f('link'):.1f} | {f('warm'):.1f} | {f('compile')+f('link')+f('warm'):.1f} | {f('m_compile')+f('m_link')+f('m_warm'):.1f} |")
print("| dimensione | n | mediana KB | compile ms | link ms | compilazione differita ms | totale | totale minimizzato |")
for lo,hi in [(0,1000),(1000,3000),(3000,10000),(10000,20000),(20000,40000),(40000,300000)]: q(lo,hi)
tot=lambda k:sum(x[k] for x in r)
o=tot("compile")+tot("link")+tot("warm"); m=tot("m_compile")+tot("m_link")+tot("m_warm")
print("totals: orig %.0f ms (compile %.0f link %.0f warm %.0f), minified %.0f ms (%+.1f%%); text %.0f KB -> %.0f KB (%.0f%%)"%(o,tot("compile"),tot("link"),tot("warm"),m,100*(m-o)/o,tot("bytes")/1024,tot("min_bytes")/1024,100*tot("min_bytes")/tot("bytes")))
ratios=[(x["m_compile"]+x["m_link"]+x["m_warm"])/(x["compile"]+x["link"]+x["warm"]) for x in r if x["bytes"]>3000]
print("per-shader minified/orig (>3KB): median %.2f, min %.2f, max %.2f"%(st.median(ratios),min(ratios),max(ratios)))
xs=[math.log(x["bytes"]) for x in r if x["bytes"]>1000]; ys=[math.log(x["compile"]+x["link"]+x["warm"]) for x in r if x["bytes"]>1000]
mx,my=st.mean(xs),st.mean(ys); cov=sum((a-mx)*(b-my) for a,b in zip(xs,ys))
b=cov/sum((a-mx)**2 for a in xs); c=cov/math.sqrt(sum((a-mx)**2 for a in xs)*sum((b-my)**2 for b in ys))
print("log-log slope (>1KB): %.2f, r=%.2f"%(b,c))
print("warm share of total: %.0f%%"%(100*tot("warm")/o))
for x in sorted(r,key=lambda x:x["bytes"])[-5:]: print(int(x["bytes"]),int(x["lines"]),x["compile"],x["link"],x["warm"],"| min",x["m_compile"],x["m_link"],x["m_warm"])
