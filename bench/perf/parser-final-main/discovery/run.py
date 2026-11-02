import hashlib,json,os,platform,random,statistics,subprocess
from pathlib import Path
root=Path('/workspace/perf-parser-evidence/fresh-pass-review')
inputs=root/'inputs';inputs.mkdir(exist_ok=True)
repo=Path('/workspace/manuscript')
def sha(data):return hashlib.sha256(data).hexdigest()
def decls(n):return ''.join(f'fn f{i}(value: Int) Int:\n    return value + 1\n' for i in range(n))
def body(n):return 'fn f() Int:\n'+''.join(f'    let v{i} = {i}\n' for i in range(n))+'    return 0\n'
cases=[]
def add(family,n,text,modes):
 p=inputs/f'{family}-{n}.src';p.write_bytes(text.encode())
 cases.append(dict(family=family,n=n,path=str(p),bytes=p.stat().st_size,sha256=sha(p.read_bytes()),modes=modes))
for n in [256,512,1024]:
 add('declarations-lf',n,decls(n),['lex','parse'])
 add('declarations-crlf',n,decls(n).replace('\n','\r\n'),['lex','parse'])
 add('body',n,body(n),['lex','parse'])
 add('collection',n,'fn f() List[Int]:\n    return ['+','.join(['1']*n)+']\n',['lex','parse'])
 add('flat-layout',n,'fn f(flag: Bool) Int:\n'+''.join(f'    if flag:\n        let v{i} = 1\n' for i in range(n))+'    return 0\n',['lex','parse'])
 add('recovery-header',n,'fn broken(\n'+decls(n),['partial'])
 add('recovery-bad-declarations',n,''.join(f'fn broken{i}(:\n    return 0\n' for i in range(n)),['partial'])
 add('recovery-one-statement',n,body(n).replace('    return 0\n','    let bad =\n    return 0\n'),['partial'])
 add('recovery-many-statements',n,'fn f() Int:\n'+'    let bad =\n'*n+'    return 0\n',['partial'])
 params=''.join(f'v{i}: Int,\n' for i in range(n))
 add('recovery-multiline-params',n,'fn broken(\nfn f(\n'+params+') Int:\n    return 0\n',['partial'])
for n in [16384,32768,65536]:
 add('ascii-comment',n,'# '+'a'*n+'\n'+decls(1),['lex','parse'])
 add('unicode-comment',n,'# '+'é🦀'*n+'\n'+decls(1),['lex','parse'])
for n in [1024,2048,4096]:
 add('escaped-text',n,'let text = "'+r'\n\t\\\"\{\}\u{1F600}'*n+'"\n',['lex','parse'])
for n in [64,128,256]:
 add('flat-interpolation',n,'let text = "'+'{1}'*n+'"\n',['lex','parse'])
for n in [16,32,64]:
 add('nested-interpolation',n,'let text = '+'"{'*n+'1'+'}"'*n+'\n',['lex','parse'])
 add('nested-layout',n,'fn f(flag: Bool) Int:\n'+''.join('    '*(i+1)+'if flag:\n' for i in range(n))+'    '*(n+1)+'return 1\n    return 0\n',['lex','parse'])
affinity=sorted(os.sched_getaffinity(0));os.sched_setaffinity(0,{affinity[0]})
r=dict(revision=subprocess.check_output(['git','rev-parse','HEAD'],cwd=repo,text=True).strip(),platform=platform.platform(),cpu=affinity[0],seed=2741,rustc=subprocess.check_output(['/workspace/perf-parser-tools/cargo/bin/rustc','-vV'],text=True),sources={name:sha((repo/'crates/ms-syntax/src'/name).read_bytes()) for name in ['lexer.rs','parser.rs','partial.rs']},binary_sha256=sha((root/'probe').read_bytes()),rlib_sha256=sha((repo/'target/release/libms_syntax.rlib').read_bytes()),cases=cases,samples=[],failures=[])
work=[(c,mode) for c in cases for mode in c['modes']]
rng=random.Random(2741)
for trial in range(3):
 rng.shuffle(work)
 for c,mode in work:
  proc=subprocess.run([str(root/'probe'),mode,c['path']],capture_output=True,text=True)
  if proc.returncode:
   r['failures'].append(dict(family=c['family'],n=c['n'],mode=mode,trial=trial,stderr=proc.stderr,exit_code=proc.returncode))
   continue
  row=json.loads(proc.stdout);assert row['checksum']==(row['units']+row['diagnostics'])*row['passes']
  row.update(family=c['family'],n=c['n'],mode=mode,trial=trial)
  r['samples'].append(row)
  (root/'results.json').write_text(json.dumps(r,indent=2)+'\n')
(root/'results.json').write_text(json.dumps(r,indent=2)+'\n')
print('families',len({c['family'] for c in cases}),'cases',len(cases),'samples',len(r['samples']),'failures',len(r['failures']))
for family in dict.fromkeys(c['family'] for c in cases):
 for mode in dict.fromkeys(m for c in cases if c['family']==family for m in c['modes']):
  vals=[]
  for c in sorted([c for c in cases if c['family']==family],key=lambda c:c['n']):
   rows=[s for s in r['samples'] if s['family']==family and s['n']==c['n'] and s['mode']==mode]
   if len(rows)!=3:continue
   ns=statistics.median(s['elapsed_ns']/s['passes'] for s in rows);vals.append(ns)
   assert len({(s['units'],s['diagnostics']) for s in rows})==1
   print(family,mode,c['n'],'bytes',c['bytes'],'us',round(ns/1000,3),'units',rows[0]['units'],'issues',rows[0]['diagnostics'])
  if len(vals)==3:print('doubling ratios',family,mode,round(vals[1]/vals[0],3),round(vals[2]/vals[1],3))
if r['failures']:print('FAILURES',r['failures'])
