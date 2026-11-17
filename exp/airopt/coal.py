# Experiment: coalesce word loads ts_ld_<buf>((tN + C)) sharing tN and C//16 into one 16-byte texelFetch of the <buf>_4
# view (assumes tN 16-aligned, as the translator already assumes for the _4 fetches of the same base). Only groups whose
# uses are all at the outermost level of main(); the fetch goes right before the first use.
import plistlib,re,sys,os,collections
src,dst=sys.argv[1],sys.argv[2]
d=plistlib.load(open(src,"rb")); g=d["glsl"]; lines=g.split("\n")
start=next(i for i,l in enumerate(lines) if l.startswith("void main()"))
pat=re.compile(r"ts_ld_(\w+)\(\((t\d+) \+ (\d+)\)\)")
groups=collections.defaultdict(list)
for i in range(start,len(lines)):
    for m in pat.finditer(lines[i]):
        buf,base,c=m.group(1),m.group(2),int(m.group(3))
        groups[(buf,base,c//16)].append((i,m.group(0),c%16//4))
has4=set(re.findall(r"uniform usamplerBuffer (\w+)_4;",g))
ins=collections.defaultdict(list); n=0; before=sum(len(v) for v in groups.values())
for k,(key,uses) in enumerate(groups.items()):
    buf,base,blk=key
    if buf not in has4 or len(uses)<2 or any(not lines[i].startswith("  ") or lines[i].startswith("   ") for i,_,_ in uses): continue
    q="tsq%d"%k; first=min(i for i,_,_ in uses)
    ins[first].append("  uvec4 %s = texelFetch(%s_4, (%s_off + (%s + %d)) >> 4);"%(q,buf,buf,base,blk*16))
    for i,txt,comp in uses: lines[i]=lines[i].replace(txt,"%s.%s"%(q,"xyzw"[comp]),1)
    n+=len(uses)-1
out=[]
for i,l in enumerate(lines): out+=ins.get(i,[])+[l]
d["glsl"]="\n".join(out); plistlib.dump(d,open(dst,"wb"))
print(os.path.basename(src)[:12],"word fetches",before,"->",before-n)
