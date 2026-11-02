import hashlib,json,os,random,statistics,subprocess
from pathlib import Path
root=Path('/workspace/perf-parser-evidence/fresh-pass-review')
os.sched_setaffinity(0,{min(os.sched_getaffinity(0))})
cases=[]
for n in [512,1024,2048,4096]:
 p=root/'inputs'/f'followup-flat-layout-{n}.src'
 p.write_text('fn f(flag: Bool) Int:\n'+''.join(f'    if flag:\n        let v{i} = 1\n' for i in range(n))+'    return 0\n')
 cases.append(dict(n=n,path=str(p),bytes=p.stat().st_size,sha256=hashlib.sha256(p.read_bytes()).hexdigest()))
r=dict(binary_sha256=hashlib.sha256((root/'probe').read_bytes()).hexdigest(),cases=cases,samples=[],seed=923)
work=[(case,mode) for case in cases for mode in ['lex','parse']]
rng=random.Random(923)
for trial in range(5):
 rng.shuffle(work)
 for case,mode in work:
  row=json.loads(subprocess.check_output([str(root/'probe'),mode,case['path']]))
  assert row['checksum']==(row['units']+row['diagnostics'])*row['passes']
  row.update(n=case['n'],mode=mode,trial=trial);r['samples'].append(row)
(root/'flat-layout-followup.json').write_text(json.dumps(r,indent=2)+'\n')
for mode in ['lex','parse']:
 med=[]
 for c in cases:
  values=[s['elapsed_ns']/s['passes']/1000 for s in r['samples'] if s['n']==c['n'] and s['mode']==mode]
  med.append(statistics.median(values));print(mode,c['n'],'median_us',round(med[-1],3),'range',round(min(values),3),round(max(values),3))
 print(mode,'doubling',[round(y/x,3) for x,y in zip(med,med[1:])])
