import csv,json,statistics,hashlib
from pathlib import Path
base=Path('/workspace/perf-evidence')
results={}
for suite,expected in [('navigation',920),('semantic',1360),('outline',1020),('formatter',1180)]:
 rows=list(csv.DictReader((base/f'final-main-{suite}.csv').open()))
 assert len(rows)==expected,(suite,len(rows))
 groups={}
 for r in rows:
  key=tuple((k,r[k]) for k in ['mode','count','shape'] if k in r)
  groups.setdefault(key,[]).append(r)
 out=[]
 for key,rs in groups.items():
  a={name:[int(r['elapsed_ns'])/int(r['rounds']) for r in rs if r['binary']==name] for name in ['before','after']}
  assert all(len(v)==10 for v in a.values())
  assert {int(r['sample']) for r in rs}==set(range(10))
  identities={tuple((k,r[k]) for k in ['checksum_per_query','source_bytes','output_bytes'] if k in r) for r in rs}
  assert len(identities)==1,(suite,key,identities)
  for sample in range(10):
   order=[r['binary'] for r in rs if int(r['sample'])==sample]
   assert order==(['before','after'] if sample%2==0 else ['after','before'])
  m={k:statistics.median(v) for k,v in a.items()}
  out.append(dict(key=key,before_ns=m['before'],after_ns=m['after'],ratio=m['after']/m['before'],delta_ns=m['after']-m['before'],distributions={k:dict(min=min(v),max=max(v),median=statistics.median(v),q1=statistics.quantiles(v,n=4)[0],q3=statistics.quantiles(v,n=4)[2]) for k,v in a.items()}))
 results[suite]=out
 print(suite,len(rows),'samples',len(out),'cases')
 print('all slower median>3%:')
 for x in out:
  if x['ratio']>1.03: print(x['key'],round(x['before_ns'],2),round(x['after_ns'],2),round(x['ratio'],4),round(x['delta_ns'],2))
(base/'final-main-analysis.json').write_text(json.dumps(results,indent=2)+'\n')
