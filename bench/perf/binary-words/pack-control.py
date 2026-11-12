from pathlib import Path
import json,subprocess,statistics,os
P=Path(__file__).parent;os.sched_setaffinity(0,{4});cases=json.loads((P/'candidate-results/cases.json').read_text());c=next(x for x in cases if x['name']=='unchanged-pack-u32');rows=[]
def run(v):
 n=1000000;exe=P/('baseline-probe' if v=='baseline' else 'probe');cmd=[str(exe),'pack','u32le',c['input'],c['expected'],'0','16',str(n),c['want'],'OK'];r=subprocess.run(cmd,text=True,capture_output=True,check=True);count,ns,ch,w=map(int,r.stdout.split(','));assert count==n and ch==65*n and w==65*(n//10);return dict(ns=ns,count=n,checksum=ch,command=cmd)
for pair in range(7):
 for mode in ['ABBA','AA']:
  for slot,v in enumerate(['baseline','candidate','candidate','baseline']):rows.append(dict(pair=pair,mode=mode,slot=slot,**run(v if mode=='ABBA' else 'baseline')))
report=[]
for mode in ['ABBA','AA']:
 ratios=[]
 for pair in range(7):
  x=[r['ns'] for r in rows if r['pair']==pair and r['mode']==mode];ratios.append((x[1]+x[2])/(x[0]+x[3]))
 report.append(dict(mode=mode,ratio=statistics.median(ratios),pairs=ratios))
(P/'candidate-results/pack-control-samples.json').write_text(json.dumps(rows,indent=2));(P/'candidate-results/pack-control-report.json').write_text(json.dumps(report,indent=2));print(json.dumps(report,indent=2))
