import sys,os,subprocess,statistics,json
from pathlib import Path
p=Path(sys.argv[1]).resolve();os.sched_setaffinity(0,{min(os.sched_getaffinity(0))});out={}
for name,sides in [('AB',['base','new']),('AA',['base','base'])]:
 rows=[]
 for rep in range(28):
  times={}
  for i in ([0,1] if rep%2==0 else [1,0]):
   r=subprocess.run([str(p/sides[i]),'1','100000'],capture_output=True,check=True,env=dict(os.environ,MS_CPU_LEVEL='baseline'));times[i]=int(r.stdout.split()[0])
  rows.append([times[0],times[1]])
 ratios=[b/a for a,b in rows[3:]];out[name]={'samples':rows,'ratio':statistics.median(ratios),'range':[min(ratios),max(ratios)]};print(name,out[name]['ratio'],flush=True)
(p/'small.json').write_text(json.dumps(out,indent=2))
