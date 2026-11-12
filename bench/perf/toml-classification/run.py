import sys,os,subprocess,json,statistics,hashlib
from pathlib import Path
p=Path(sys.argv[1]).resolve()
os.sched_setaffinity(0,{min(os.sched_getaffinity(0))})
env=dict(os.environ,MS_CPU_LEVEL='baseline',LC_ALL='C')
rows=[]
for kind,n,count in [('ordinary',0,250000),('tables',1,60000),('tables',20,3000),('tables',1000,60),('mixed',1,100000),('mixed',20,6000),('mixed',1000,120),('array',0,500000),('array',20,60000),('array',1000,1500)]:
 samples=[]
 for rep in range(28):
  pair={}; output=[]
  for side in (['base','new'] if rep%2==0 else ['new','base']):
   r=subprocess.run([str(p/side),kind,str(n),str(count)],capture_output=True,check=True,env=env)
   ns,checksum=map(int,r.stdout.split()); assert checksum==len(r.stderr)*count
   pair[side]=ns;output.append(r.stderr)
  assert output[0]==output[1]
  samples.append(pair)
 ratios=[x['new']/x['base'] for x in samples[3:]]
 row=dict(kind=kind,size=n,count=count,samples=samples,baseline_ns=statistics.median(x['base'] for x in samples[3:])/count,candidate_ns=statistics.median(x['new'] for x in samples[3:])/count,ratio=statistics.median(ratios),range=[min(ratios),max(ratios)],output_sha256=hashlib.sha256(output[0]).hexdigest())
 rows.append(row);print(kind,n,round(row['baseline_ns']),round(row['candidate_ns']),round(row['ratio'],3),flush=True)
 (p/'samples.json').write_text(json.dumps(rows,indent=2))
