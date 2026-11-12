import json,os,subprocess,statistics
from pathlib import Path
P=Path(__file__).parent;os.sched_setaffinity(0,{4});cases=[x for x in json.loads((P/'runtime-results/cases.json').read_text()) if x['name'] in ['neighbor-u16le','unchanged-pack-u32']];bins={'baseline':P/'current-baseline-probe','candidate':P/'runtime-probe'};rows=[]
for pair in range(7):
 for c in cases:
  for mode in ['ABBA','AA']:
   for slot,v in enumerate(['baseline','candidate','candidate','baseline'] if mode=='ABBA' else ['baseline']*4):
    n=c['counts'][v];cmd=[str(bins[v]),c['op'],c['type'],c['input'],c['expected'],str(c['start']),str(c['fields']),str(n),c['want'],c['kind']];r=subprocess.run(cmd,check=True,text=True,capture_output=True);count,ns,check,warm=map(int,r.stdout.split(','));assert count==n and check==c['unit']*n and warm==c['unit']*max(1,n//10)
    rows.append(dict(case=c['name'],mode=mode,pair=pair,slot=slot,variant=v,count=n,ns=ns,checksum=check,command=cmd))
 (P/'control-samples.json').write_text(json.dumps(rows,indent=2));print(pair,flush=True)
report=[]
for c in cases:
 for mode in ['ABBA','AA']:
  ratios=[]
  for i in range(7):
   a=[r['ns']/r['count'] for r in rows if r['case']==c['name'] and r['mode']==mode and r['pair']==i];ratios.append((a[1]+a[2])/(a[0]+a[3]))
  report.append(dict(case=c['name'],mode=mode,ratio=statistics.median(ratios),pairs=ratios))
(P/'control-report.json').write_text(json.dumps(report,indent=2));print(report)
