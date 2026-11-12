import os,subprocess,statistics,json,sys
from pathlib import Path
root=Path(sys.argv[1])
os.sched_setaffinity(0,{min(os.sched_getaffinity(0))})
rows=[]
for backend in ['llvm','clif']:
 for case,pattern in [('empty',''),('literal','hello'),('date','YYYY-MM-DD'),('usual','YYYY-MM-DD HH:mm:ss ZZ zone'),('unicode','日本語の日時 YYYY年MM月DD日 🗓'),('long','YYYY-MM-DD HH:mm:ss ZZ zone 日本語 🗓 '*128)]:
  for zone in ['UTC','America/New_York']:
   n=5000 if case=='long' else 300000
   ratios=[];samples={'base':[],'new':[]}
   for rep in range(29):
    pair={}; checks={}
    for mode in (['base','new'] if rep%2==0 else ['new','base']):
     out=subprocess.check_output([str(root/f'{mode}-{backend}'),pattern,zone,str(n)],text=True)
     ns,checksum=map(int,out.split())
     rows.append(dict(backend=backend,case=case,zone=zone,rep=rep,mode=mode,ns=ns,n=n,checksum=checksum))
     pair[mode]=ns/n
     checks[mode]=checksum
    assert checks["base"]==checks["new"]
    if rep>=4:
     ratios.append(pair['new']/pair['base'])
     for mode in pair:samples[mode].append(pair[mode])
   print(backend,case,zone,*[f'{k}:{statistics.median(v):.2f}' for k,v in samples.items()],f'ratio:{statistics.median(ratios):.4f}',f'slower:{sum(r>1 for r in ratios)}/{len(ratios)}',flush=True)
   (root/'samples.json').write_text(json.dumps(rows,indent=2))
