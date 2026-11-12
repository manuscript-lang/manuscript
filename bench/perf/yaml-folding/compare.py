import sys,os,subprocess,statistics,json
from pathlib import Path
p=Path(sys.argv[1]).resolve();os.sched_setaffinity(0,{min(os.sched_getaffinity(0))});rows=[]
for n,count in [(1,20000),(10,5000),(100,1000),(1000,100),(4000,30),(8000,15)]:
 samples=[]
 for rep in range(18):
  pair={}
  for side in (['base','new'] if rep%2==0 else ['new','base']):
   r=subprocess.run([str(p/side),str(n),str(count)],check=True,capture_output=True,env=dict(os.environ,MS_CPU_LEVEL='baseline'))
   pair[side]=list(map(int,r.stdout.split()))
  assert pair['base'][1]==pair['new'][1]
  samples.append(pair)
 row={'lines':n,'count':count,'samples':samples,'base_ns':statistics.median(x['base'][0] for x in samples[3:])/count,'new_ns':statistics.median(x['new'][0] for x in samples[3:])/count,'ratio':statistics.median(x['new'][0]/x['base'][0] for x in samples[3:])};rows.append(row);print(n,row['base_ns'],row['new_ns'],row['ratio'],flush=True);(p/'samples.json').write_text(json.dumps(rows,indent=2))
