# Variant of a translated fragment shader: temporaries assigned once at the outermost level of main() are declared
# where they are defined ("float t5 = ...;") instead of at the top of main().
import plistlib,re,sys,os
src,dst=sys.argv[1],sys.argv[2]
d=plistlib.load(open(src,"rb")); g=d["glsl"]; lines=g.split("\n")
start=next(i for i,l in enumerate(lines) if l.startswith("void main()"))
decl={}
for i in range(start+1,len(lines)):
    m=re.match(r"^  (float|int|uint|bool|vec[234]|ivec[234]|uvec[234]|bvec[234]|mat[234]) (\w+);$",lines[i])
    if m: decl[m.group(2)]=(i,m.group(1))
moved=0
for name,(di,ty) in decl.items():
    assigns=[i for i in range(start,len(lines)) if re.search(r"\b%s\s*=[^=]"%name,lines[i])]
    if len(assigns)!=1: continue
    ai=assigns[0]
    if not re.match(r"^  %s = "%name,lines[ai]): continue           # outermost level only
    if any(re.search(r"\b%s\b"%name,lines[i]) for i in range(di+1,ai)): continue   # used before its definition
    lines[ai]="  %s %s"%(ty,lines[ai][2:]); lines[di]="\x00"; moved+=1
d["glsl"]="\n".join(l for l in lines if l != "\x00")
plistlib.dump(d,open(dst,"wb"))
print(os.path.basename(src)[:12],"declarations",len(decl),"moved",moved)
