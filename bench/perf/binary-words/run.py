import json,subprocess,statistics,os,struct,argparse,resource
from pathlib import Path
P=Path(__file__).parent;O=P/'results';O.mkdir(exist_ok=True);bins={'ms':P/'probe','c':P/'c-control/probe'}
parser=argparse.ArgumentParser();parser.add_argument('--correct-only',action='store_true');parser.add_argument('--ms');parser.add_argument('--out');args=parser.parse_args()
if args.ms:bins['ms']=Path(args.ms)
if args.out:O=Path(args.out);O.mkdir(parents=True,exist_ok=True)
types=['i8','u8']+[f'{s}{n}{e}' for n in [16,32,64] for s in ['i','u'] for e in ['le','be']]+[f'f{n}{e}' for n in [32,64] for e in ['le','be']];cases=[]
def info(t):
 n=int(t[1:-2]) if t.endswith(('le','be')) else 8
 return n//8,'big' if t.endswith('be') else 'little'
def text(t,v):
 return str(v>>32)+':'+str(v&0xffffffff) if t.startswith('u64') else str(v)
def packed(t,v):
 w,e=info(t)
 if t[0]=='f':return struct.pack(('>' if e=='big' else '<')+('f' if w==4 else 'd'),v)
 return int(v).to_bytes(w,e,signed=t[0]=='i')
def add(name,op,t,data,expected,start=0,fields=1,want='1',kind='OK',perf=False):
 i=O/(name+'.in');o=O/(name+'.out');i.write_bytes(data);o.write_bytes(expected)
 cases.append(dict(name=name,op=op,type=t,input=str(i),expected=str(o),start=start,fields=fields,want=want,kind=kind,unit=fields if op=='read' else len(expected)+1,perf=perf))
for t in types:
 w,e=info(t)
 vals=[0,1,-1,-(1<<(w*8-1)),(1<<(w*8-1))-1] if t[0]=='i' else [0,1,(1<<(w*8-1)),(1<<(w*8))-1]
 if t[0]=='f':vals=[0.0,-0.0,1.5,-2.25]
 for v in vals:
  raw=packed(t,v);want=text(t,v)
  for at in [0,1,3]:
   data=b'P'*at+raw*3+b'Q';add('read'+str(len(cases)),'read',t,data,raw*3,at,3,want)
   add('round'+str(len(cases)),'roundtrip',t,data,raw*3,at,3,want)
  add('pack'+str(len(cases)),'pack',t,b'',raw*3,0,3,want)
 for at,data in [(-1,b'\0'*w),(2**63-1,b'\0'*w),(0,b'\0'*(w-1)),(1,b'\0'*w)]:add('error'+str(len(cases)),'read',t,data,b'',at,1,'0:0' if t.startswith('u64') else '0',kind='ERANGE')
 if t[0]=='f':
  patterns=([0,0x80000000,0x00000001,0x007fffff,0x00800000,0x7f800000,0xff800000,0x7fc12345,0x7f812345,0xff812345] if w==4 else [0,0x8000000000000000,1,0x000fffffffffffff,0x0010000000000000,0x7ff0000000000000,0xfff0000000000000,0x7ff8000000001234,0x7ff0000000001234,0xfff0000000001234])
  for bits in patterns:
   out=bits
   if w==4 and bits&0x7f800000==0x7f800000 and bits&0x7fffff:out|=0x400000
   add('bits'+str(len(cases)),'roundtrip',t,b'X'+bits.to_bytes(w,e),out.to_bytes(w,e),1,1,'1.5')
for op,chosen in [('read',['u32le','u64be','f32le','f64be']),('pack',['u32le','i64be','f32le','f64be'])]:
 for t in chosen:
  v=1.5 if t[0]=='f' else (0xf123456789abcdef if t.startswith('u64') else -123456789 if t.startswith('i64') else 0x12345678)
  for n in [1,16,8192]:
   raw=packed(t,v)*n;add(f'{op}-{t}-{n}',op,t,raw,raw,0,n,text(t,v),perf=True)
def run(c,v,n):
 cmd=[str(bins[v]),c['op'],c['type'],c['input'],c['expected'],str(c['start']),str(c['fields']),str(n),c['want'],c['kind']]
 before=resource.getrusage(resource.RUSAGE_CHILDREN);r=subprocess.run(cmd,text=True,capture_output=True,check=True);after=resource.getrusage(resource.RUSAGE_CHILDREN);count,ns,ch,w=map(int,r.stdout.split(','));assert count==n and ch==c['unit']*n and w==c['unit']*max(1,n//10),(c,r.stdout);return dict(ns=ns,count=n,checksum=ch,command=cmd,minor_faults=after.ru_minflt-before.ru_minflt,major_faults=after.ru_majflt-before.ru_majflt)
(O/'cases.json').write_text(json.dumps(cases,indent=2));correct=[]
for c in cases:
 for v in bins:
  try:correct.append(dict(case=c['name'],variant=v,**run(c,v,2)))
  except Exception:
   print('FAILED',c,v,flush=True);raise
(O/'correctness.json').write_text(json.dumps(correct,indent=2));print('correct',len(cases),flush=True)
if args.correct_only:raise SystemExit
os.sched_setaffinity(0,{4});perf=[c for c in cases if c['perf']]
for c in perf:
 n=10
 while True:
  fast=min(run(c,v,n)['ns'] for v in bins)
  if fast>=30000000 or n>=10000000:break
  n=min(10000000,max(n+1,int(n*35000000/max(fast,1))))
 c['count']=n
samples=[]
for pair in range(7):
 for c in perf:
  for v in (['ms','c'] if pair%2==0 else ['c','ms']):samples.append(dict(case=c['name'],pair=pair,variant=v,**run(c,v,c['count'])))
 (O/'samples.json').write_text(json.dumps(samples,indent=2));print('pair',pair,flush=True)
report=[]
for c in perf:
 m,b=[[x['ns']/x['count'] for x in samples if x['case']==c['name'] and x['variant']==v] for v in bins];rat=[x/y for x,y in zip(m,b)];r=dict(case=c['name'],ms=statistics.median(m),c=statistics.median(b),ratio=statistics.median(rat),range=[min(rat),max(rat)]);report.append(r);print(r,flush=True)
(O/'report.json').write_text(json.dumps(report,indent=2))
aa=[]
for pair in range(7):
 for c in [x for x in perf if x['name'] in ['read-u64be-1','read-u64be-8192','pack-u32le-1','pack-u32le-8192']]:
  for side in ['A','B']:aa.append(dict(case=c['name'],pair=pair,side=side,**run(c,'ms',c['count'])))
(O/'aa.json').write_text(json.dumps(aa,indent=2));print('AA done',flush=True)
