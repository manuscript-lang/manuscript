import json,subprocess,os,statistics,sys,argparse
from pathlib import Path
SOURCE=Path(__file__).resolve().parent
parser=argparse.ArgumentParser()
parser.add_argument('--baseline',type=Path,default=SOURCE.parent/'baseline'/'probe')
parser.add_argument('--candidate',type=Path,default=SOURCE.parent/'candidate'/'probe')
parser.add_argument('--c-binary',type=Path,default=SOURCE/'probe')
parser.add_argument('--out',type=Path,default=SOURCE)
parser.add_argument('--cpu',type=int,default=4)
parser.add_argument('--time',action='store_true')
args=parser.parse_args();P=args.out.resolve();P.mkdir(parents=True,exist_ok=True)
executables={v:str(p.resolve()) for v,p in [('baseline',args.baseline),('candidate',args.candidate),('c',args.c_binary)]}
ws='\t\n\v\f\r '
def enc(s,d,e):
 q=bool(s) and (any(c in s for c in ['"','\r','\n',d]) or s[0] in ws or s=='\\.')
 if not q:return s
 s=s.replace('"','""')
 if e=='crlf':s=s.replace('\r\n','\n').replace('\n','\r\n')
 return '"'+s+'"'
cases=[]
def add(name,s,d=',',e='lf',limit=2**63-1,kind='OK',perf=False):
 i=P/(name+'.in');o=P/(name+'.out');i.write_bytes(s.encode('ascii'));want=(enc(s,d,e)+d+enc('tail',d,e)+('\r\n' if e=='crlf' else '\n')).encode('ascii');o.write_bytes(want)
 cases.append(dict(name=name,input=str(i),expected=str(o),delimiter=d,ending=e,kind=kind,limit=limit,unit=len(want)+1 if kind=='OK' else 1,perf=perf))
for name,s in [('empty',''),('one','a'),('ordinary','hello world'),('comma','hello,world'),('quote','hello"world'),('crlf','hello\r\nworld')]:add(name,s,e='crlf' if name=='crlf' else 'lf',perf=True)
for size in [1024,65536]:
 for name,s in [('ascii','x'*size),('early-comma',','+'x'*size),('late-comma','x'*size+','),('quotes','"'*size)]:add(name+str(size),s,perf=True)
for cp in range(128):
 for s in [chr(cp)+'x','x'+chr(cp),'\\.'+chr(cp)]:add('oracle'+str(len(cases)),s)
for d in [',',';','\t','|','\\','.','t']:
 for s in ['','\\.','\\.x','x\\.','a\r\nb\rc\nd','\r\r\n','"',' tail']:
  for e in ['lf','crlf']:add('oracle'+str(len(cases)),s,d,e)
for d in ['', 'xx','"','\r','\n']:
 add('invalid'+str(len(cases)),'abc',d,kind='EINVAL')
add('negative','abc',limit=-1,kind='EINVAL');add('limit','abc',limit=1,kind='EOVERFLOW')
for lim in [8,9,10]:add('budget'+str(lim),'abc',limit=lim,kind='EOVERFLOW' if lim<9 else 'OK')
def run(c,v,n):
 exe=executables[v]
 cmd=[str(exe),c['input'],c['expected'],c['delimiter'],c['ending'],c['kind'],str(c['limit']),str(n)]
 r=subprocess.run(cmd,text=True,capture_output=True,check=True);count,ns,ch,w=map(int,r.stdout.split(','));assert count==n and ch==n*c['unit'] and w==max(1,n//10)*c['unit'],c
 return dict(ns=ns,count=n,checksum=ch,warm_checksum=w,command=cmd)
variants=['baseline','candidate','c']
if not args.time:
 rows=[]
 for c in cases:
  for v in variants:rows.append(dict(case=c['name'],variant=v,**run(c,v,1)))
 (P/'correctness.json').write_text(json.dumps(rows,indent=2));(P/'cases.json').write_text(json.dumps(cases,indent=2));print('validated',len(cases),'cases x',len(variants));sys.exit()
os.sched_setaffinity(0,{args.cpu});perf=[c for c in cases if c['name'] in ['empty','one','ordinary','comma','ascii1024','ascii65536']]
for c in perf:
 n=100
 while True:
  fast=min(run(c,v,n)['ns'] for v in variants)
  if fast>=100_000_000:break
  n=max(n+1,int(n*125_000_000/max(fast,1)))
 c['count']=n
rows=[]
for pair in range(7):
 for c in perf:
  for v in variants if pair%2==0 else variants[::-1]:rows.append(dict(case=c['name'],variant=v,pair=pair,**run(c,v,c['count'])))
 (P/'samples.json').write_text(json.dumps(rows,indent=2));print('pair',pair,flush=True)
report=[]
for c in perf:
 med={v:statistics.median(r['ns']/r['count'] for r in rows if r['case']==c['name'] and r['variant']==v) for v in variants}
 report.append(dict(case=c['name'],ns_per_call=med,baseline_over_c=med['baseline']/med['c'],candidate_over_c=med['candidate']/med['c']))
(P/'report.json').write_text(json.dumps(report,indent=2));print(json.dumps(report,indent=2))
