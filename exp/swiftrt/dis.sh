#!/bin/zsh
# dis.sh <symbol> [bytes]: disassembles an exported libswiftCore function with symbolized call targets.
cd ${0:a:h}
./fdump $1 ${2:-160} > f.addr & sleep 1; base=$(cat f.addr); pid=$(pgrep -n fdump)
python3 -c "b=open('f.bin','rb').read(); open('f.s','w').write('.text\n_f:\n'+''.join('.byte %d\n'%x for x in b))"
clang -c f.s -o f.o && xcrun llvm-objdump -d --no-show-raw-insn f.o | awk 'NR>7' > f.dis
python3 - $pid $base <<'PY'
import re,subprocess,sys
pid,base=sys.argv[1],int(sys.argv[2],16)
rows=[];tg=[]
for l in open('f.dis'):
    m=re.match(r'\s*([0-9a-f]+):\s*(.*)',l.rstrip())
    if not m: continue
    off=int(m.group(1),16); ins=m.group(2); t=re.search(r'(call|jmp)q?\s+0x([0-9a-f]+)',ins)
    a=base+int(t.group(2),16) if t else None
    if a: tg.append(hex(a))
    rows.append((off,ins,a))
names=subprocess.run(['atos','-p',pid]+tg,capture_output=True,text=True).stdout.split('\n') if tg else []
i=0
for off,ins,a in rows:
    s=''
    if a: s='  -> '+names[i]; i+=1
    print('+%-4d %s%s'%(off,ins.split('##')[0].strip(),s))
PY
kill $pid 2>/dev/null
