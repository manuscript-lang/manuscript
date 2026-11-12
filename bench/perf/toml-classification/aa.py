import sys,os,subprocess,json,statistics
from pathlib import Path
p=Path(sys.argv[1]).resolve()
os.sched_setaffinity(0,{min(os.sched_getaffinity(0))})
env=dict(os.environ,MS_CPU_LEVEL='baseline',LC_ALL='C')
rows=[]
for kind,n,count in [('ordinary',0,250000),('tables',20,3000),('array',0,500000),('array',20,60000)]:
 samples=[]
 for rep in range(28):
  pair=[]
  for unused in range(2):
   r=subprocess.run([str(p/'base'),kind,str(n),str(count)],capture_output=True,check=True,env=env)
   ns,checksum=map(int,r.stdout.split());assert checksum==len(r.stderr)*count
   pair.append(ns)
  samples.append(pair if rep%2==0 else pair[::-1])
 ratios=[b/a for a,b in samples[3:]]
 row=dict(kind=kind,size=n,count=count,samples=samples,ratio=statistics.median(ratios),range=[min(ratios),max(ratios)])
 rows.append(row);print(kind,n,row['ratio'],flush=True)
 (p/'aa.json').write_text(json.dumps(rows,indent=2))
