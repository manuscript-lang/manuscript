import hashlib,json,os,random,statistics,subprocess
from pathlib import Path
root=Path('/workspace/perf-parser-evidence/fresh-pass-review')
os.sched_setaffinity(0,{min(os.sched_getaffinity(0))})
cases=[]
for n in [64,128,256,512]:
 text='fn f(value:\n'+'    fn(\n'*n+'        Int\n'+'    ) Unit\n'*n+') Unit:\n    return unit\n'
 for ending in ['lf','crlf']:
  p=root/'inputs'/f'function-depth-{n}-{ending}.src';p.write_bytes((text if ending=='lf' else text.replace('\n','\r\n')).encode())
  cases.append(dict(n=n,ending=ending,path=str(p),bytes=p.stat().st_size,sha256=hashlib.sha256(p.read_bytes()).hexdigest()))
r=dict(binary_sha256=hashlib.sha256((root/'probe').read_bytes()).hexdigest(),cases=cases,samples=[],failures=[],seed=361)
work=[(case,mode) for case in cases for mode in ['lex','parse']]
rng=random.Random(361)
for trial in range(5):
 rng.shuffle(work)
 for case,mode in work:
  proc=subprocess.run([str(root/'probe'),mode,case['path']],text=True,capture_output=True)
  if proc.returncode:r['failures'].append(dict(n=case['n'],ending=case['ending'],mode=mode,trial=trial,stderr=proc.stderr,code=proc.returncode));continue
  row=json.loads(proc.stdout);assert row['checksum']==(row['units']+row['diagnostics'])*row['passes']
  row.update(n=case['n'],ending=case['ending'],mode=mode,trial=trial);r['samples'].append(row)
(root/'function-depth-baseline.json').write_text(json.dumps(r,indent=2)+'\n')
for ending in ['lf','crlf']:
 for mode in ['lex','parse']:
  med=[]
  for n in [64,128,256,512]:
   values=[s['elapsed_ns']/s['passes']/1000 for s in r['samples'] if s['n']==n and s['mode']==mode and s['ending']==ending]
   if not values:continue
   med.append(statistics.median(values));print(ending,mode,n,'median_us',round(med[-1],3),'range',round(min(values),3),round(max(values),3))
  print(ending,mode,'doubling',[round(y/x,3) for x,y in zip(med,med[1:])])
print('failures',r['failures'])
