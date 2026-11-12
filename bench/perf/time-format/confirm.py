import os,subprocess,statistics,json,sys
from pathlib import Path
root=Path(sys.argv[1])
os.sched_setaffinity(0,{min(os.sched_getaffinity(0))})
rows=[]
for case,pattern,zone in [('empty-utc','','UTC'),('empty-ny','','America/New_York')]:
 for comparison in ['ab','aa']:
  ratio=[]
  for rep in range(29):
   pair={}
   for side in ([0,1] if rep%2==0 else [1,0]):
    variant='new' if side==1 and comparison=='ab' else 'base'
    ns,check=map(int,subprocess.check_output([str(root/f'{variant}-llvm'),pattern,zone,'2000000']).split())
    assert check==0
    rows.append(dict(case=case,comparison=comparison,rep=rep,side=side,variant=variant,ns=ns))
    pair[side]=ns
   if rep>=4:ratio.append(pair[1]/pair[0])
  print(case,comparison,statistics.median(ratio),sum(x>1 for x in ratio),len(ratio),flush=True)
(root/'confirm.json').write_text(json.dumps(rows,indent=2))
