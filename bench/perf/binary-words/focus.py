import json,subprocess,statistics,os,resource
from pathlib import Path
P=Path(__file__).parent;O=P/'candidate-results';O.mkdir(exist_ok=True);os.sched_setaffinity(0,{4});bins={'baseline':P/'baseline-probe','candidate':P/'probe','c':P/'c-control/probe'};cases=[]
def add(name,t,value,n=1,start=0,data=None,kind='OK',op='read'):
 w=8 if t.startswith('u64') else 4;e='big' if t.endswith('be') else 'little';raw=value.to_bytes(w,e)*n
 if data is None:data=b'P'*max(start,0)+raw
 want=str(value>>32)+':'+str(value&0xffffffff) if t.startswith('u64') else str(value)
 i=O/(name+'.in');o=O/(name+'.out');i.write_bytes(data);o.write_bytes(raw)
 cases.append(dict(name=name,type=t,op=op,input=str(i),expected=str(o),start=start,fields=n,want=want,kind=kind,unit=n if op=='read' else len(raw)+1))
for e in ['le','be']:
 for label,value in [('low',0x123456789abcdef),('high',0xf123456789abcdef)]:
  for n in [1,16,8192]:add(f'{e}-{label}-{n}','u64'+e,value,n,start=1)
 for label,start,data in [('negative',-1,b'\0'*8),('huge',2**63-1,b'\0'*8),('short',0,b'\0'*7)]:add(e+'-'+label,'u64'+e,0,start=start,data=data,kind='ERANGE')
add('unchanged-read-u32','u32le',0x12345678,n=16)
add('unchanged-pack-u32','u32le',0x12345678,n=16,op='pack')
def run(c,v,n):
 cmd=[str(bins[v]),c['op'],c['type'],c['input'],c['expected'],str(c['start']),str(c['fields']),str(n),c['want'],c['kind']]
 a=resource.getrusage(resource.RUSAGE_CHILDREN);r=subprocess.run(cmd,text=True,capture_output=True,check=True);b=resource.getrusage(resource.RUSAGE_CHILDREN);count,ns,ch,w=map(int,r.stdout.split(','));assert count==n and ch==c['unit']*n and w==c['unit']*max(1,n//10);return dict(ns=ns,count=n,checksum=ch,command=cmd,minor_faults=b.ru_minflt-a.ru_minflt,major_faults=b.ru_majflt-a.ru_majflt)
for c in cases:
 for v in bins:run(c,v,2)
 n=10
 while True:
  fast=min(run(c,v,n)['ns'] for v in ['baseline','candidate'])
  if fast>=100000000 or n>=10000000:break
  n=min(10000000,max(n+1,int(n*110000000/max(1,fast))))
 c['count']=n
r=[]
for pair in range(7):
 for c in cases:
  for v in (list(bins) if pair%2==0 else list(reversed(bins))):r.append(dict(case=c['name'],pair=pair,variant=v,**run(c,v,c['count'])))
 (O/'samples.json').write_text(json.dumps(r,indent=2));print('pair',pair,flush=True)
report=[]
for c in cases:
 d={v:[x['ns']/x['count'] for x in r if x['case']==c['name'] and x['variant']==v] for v in bins};rat=[a/b for a,b in zip(d['candidate'],d['baseline'])];item=dict(case=c['name'],medians={v:statistics.median(x) for v,x in d.items()},ratio=statistics.median(rat),range=[min(rat),max(rat)]);report.append(item);print(item,flush=True)
(O/'cases.json').write_text(json.dumps(cases,indent=2));(O/'report.json').write_text(json.dumps(report,indent=2))
aa=[]
for pair in range(7):
 for c in [x for x in cases if x['name'] in ['be-high-1','be-high-8192','be-negative','unchanged-read-u32','unchanged-pack-u32']]:
  for side in ['A','B']:aa.append(dict(case=c['name'],pair=pair,side=side,**run(c,'baseline',c['count'])))
(O/'aa.json').write_text(json.dumps(aa,indent=2));print('AA done',flush=True)
