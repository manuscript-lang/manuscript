#!/usr/bin/env python3
"""Reports which bodiless stdlib functions derive their runtime signature from their declaration.

Read-only. For each top-level bodiless `fn` in stdlib/*.ms it finds the runtime symbol the lowering
would pick (msrt_/msstd_ x module x absorbed module), derives the C signature that
crates/ms-rt/ABI.md section 1 implies from the Manuscript types, and compares it with
crates/ms-rt/SYMBOLS.md. Classes: exact, mismatch (symbol found, signature differs),
irregular-type (types outside scalars/String/Bytes/Result of those), no-symbol (hand-lowered).
Methods of native types are not covered. Run from the repository root; `-v` lists every entry.
"""
import re,glob,os,collections
syms={}
for l in open('crates/ms-rt/SYMBOLS.md'):
    m=re.match(r'(ms(?:rt|std)_\w+)\((.*)\)(?: -> (.*))?$',l.strip())
    if m:
        ps=[p.split(':',1)[1].strip() for p in m.group(2).split(',') if ':' in p]
        syms[m.group(1)]=(ps,m.group(3) or '')
absorbed={"core":["errors","faults","cleanup","optional","result","equality"],"math":["numbers","bits","bigint"],"io":["terminal"],"fs":["path"],"process":["system"],"net":["tls","url","websocket"],"collections":["queues","list"],"string":["regex"],"bytes":["binary"],"archive":["compress"]}
def split_top(s):
    out=[];d=0;cur=''
    for c in s:
        if c in '[(':d+=1
        if c in '])':d-=1
        if c==',' and d==0: out.append(cur);cur=''
        else: cur+=c
    if cur.strip(): out.append(cur)
    return out
scal={'Int':['i64'],'Float':['f64'],'Bool':['u8']}
def param(t):
    t=t.strip()
    if t in scal: return scal[t]
    if t=='String': return ['*const StrVal']
    if t=='Bytes': return ['*const VecVal']
    return None
def derive(params,ret):
    ps=[]
    for p in params:
        t=p.split(':',1)[1].strip() if ':' in p else p
        d=param(t)
        if d is None: return None
        ps+=d
    r=ret.strip()
    if r in scal: return ps,scal[r][0]
    if r in ('','Unit'): return ps,''
    if r in('String','Bytes'): return ps+['*mut %s'%('StrVal' if r=='String' else 'VecVal')],''
    m=re.match(r'Result\[(.*),\s*\w+\]$',r)
    if m:
        ok=m.group(1)
        if ok=='Unit': return ps,'u8'
        d=scal.get(ok)
        if d: return ps+['*mut '+d[0]],'u8'
        if ok in('String','Bytes'): return ps+['*mut %s'%('StrVal' if ok=='String' else 'VecVal')],'u8'
    return None
stat=collections.Counter();det=collections.defaultdict(list)
for f in sorted(glob.glob('stdlib/*.ms')):
    mod=os.path.basename(f)[:-3]
    lines=open(f).read().split('\n')
    for i,l in enumerate(lines):
        m=re.match(r'(?:export )?fn (\w+)(?:\[.*?\])?\((.*)\)\s*(.*?):\s*$',l)
        if not m: continue
        j=i+1
        while j<len(lines) and (lines[j].startswith('#') or not lines[j].strip()): j+=1
        if j<len(lines) and lines[j].startswith((' ','\t')): continue
        name,params,ret=m.groups()
        cands=[f'{p}_{mm}_{name}' for mm in [mod]+absorbed.get(mod,[]) for p in('msrt','msstd')]
        sym=next((c for c in cands if c in syms),None)
        if not sym: stat['no-symbol']+=1;det['no-symbol'].append(f'{mod}.{name}');continue
        d=derive(split_top(params),ret)
        if d is None: stat['irregular-type']+=1;det['irregular-type'].append(f'{mod}.{name}');continue
        if (d[0],d[1])==tuple(syms[sym]): stat['exact']+=1
        else: stat['mismatch']+=1;det['mismatch'].append(f'{mod}.{name}: want {d} have {syms[sym]}')
print(sum(stat.values()),dict(stat))
import sys
for k in det:
    print('==',k,len(det[k]));print('\n'.join(det[k] if "-v" in sys.argv else det[k][:12]))
