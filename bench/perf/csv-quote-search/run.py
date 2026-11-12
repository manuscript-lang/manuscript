import argparse,json,subprocess,os,statistics
from pathlib import Path
parser=argparse.ArgumentParser()
parser.add_argument('--baseline',type=Path,default=Path(__file__).parent/'baseline'/'probe')
parser.add_argument('--candidate',type=Path,default=Path(__file__).parent/'candidate'/'probe')
parser.add_argument('--out',type=Path,default=Path(__file__).parent)
parser.add_argument('--cpu',type=int,default=4)
args=parser.parse_args();P=args.out.resolve();P.mkdir(parents=True,exist_ok=True)
binaries={'baseline':args.baseline.resolve(),'candidate':args.candidate.resolve()}
os.sched_setaffinity(0,{args.cpu});cases=[]
ws='\t\n\v\f\r \x85\xa0\u1680\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200a\u2028\u2029\u202f\u205f\u3000'
def encode(s,d,e):
 q=bool(s) and (any(c in s for c in ['"','\r','\n',d]) or s[0] in ws or s=='\\.')
 if not q:return s
 s=s.replace('"','""')
 if e=='crlf':s=s.replace('\r\n','\n').replace('\n','\r\n')
 return '"'+s+'"'
def add(name,s,d=',',e='lf',limit=2**63-1,kind='OK',perf=False):
 i=P/(name+'.in');o=P/(name+'.out');i.write_bytes(s.encode());want=(encode(s,d,e)+d+encode('tail',d,e)+ ('\r\n' if e=='crlf' else '\n')).encode();o.write_bytes(want)
 c=dict(name=name,input=str(i),expected=str(o),delimiter=d,ending=e,kind=kind,limit=limit,unit=len(want)+1 if kind=='OK' else 1,perf=perf);cases.append(c)
for n,s in [('empty',''),('one','a'),('ordinary','hello world'),('comma','hello,world'),('quote','hello"world'),('newline','hello\r\nworld'),('space',' hello'),('unicode','é日😀'),('unicode-space','\u2003hello'),('dot','\\.')]:add(n,s,perf=True)
for size in [1024,65536]:
 for n,s in [('ascii','x'*size),('unicode','日'*size),('early-comma',','+'x'*size),('late-comma','x'*size+',')]:add(n+'-'+str(size),s,perf=True)
add('semicolon','hello;world',';',perf=True);add('crlf','hello\r\nworld',e='crlf',perf=True)
add('limit','abc',limit=1,kind='EOVERFLOW',perf=True);add('negative','abc',limit=-1,kind='EINVAL',perf=True);add('invalid-delimiter','abc',d='é',kind='EINVAL',perf=True)
perf=[c for c in cases if c['perf']]
for cp in list(range(128))+[133,160,0x1680,0x2003,0x2028,0x2029,0x202f,0x205f,0x3000,0xfeff,0x10ffff]:
 for s in [chr(cp)+'x','x'+chr(cp),'\\.'+chr(cp)]:add('oracle'+str(len(cases)),s)
for d in [';',':','\t','|','\\','.']:
 for s in ['\\.','é日',d+'x','x'+d,'', ' tail','a"b\nc']:
  for e in ['lf','crlf']:add('oracle'+str(len(cases)),s,d,e)
def run(c,v,n):
 cmd=[str(binaries[v]),c['input'],c['expected'],c['delimiter'],c['ending'],c['kind'],str(c['limit']),str(n)];r=subprocess.run(cmd,text=True,capture_output=True,check=True);count,ns,ch,w=map(int,r.stdout.split(','));assert count==n and ch==n*c['unit'] and w==max(1,n//10)*c['unit'];return dict(ns=ns,checksum=ch,count=n,command=cmd)
correct=[]
for c in cases:
 for v in ['baseline','candidate']:correct.append(dict(case=c['name'],variant=v,**run(c,v,3)))
(P/'correctness.json').write_text(json.dumps(correct,indent=2));print('correct',len(cases),flush=True)
for c in perf:
 n=100
 while True:
  fast=min(run(c,v,n)['ns'] for v in ['baseline','candidate'])
  if fast>=100_000_000 or n>=10000000:break
  n=min(10000000,max(n+1,int(n*110_000_000/max(fast,1))))
 c['count']=n
rows=[]
for pair in range(7):
 for c in perf:
  for v in (['baseline','candidate'] if pair%2==0 else ['candidate','baseline']):rows.append(dict(case=c['name'],variant=v,pair=pair,**run(c,v,c['count'])))
 (P/'samples.json').write_text(json.dumps(rows,indent=2));print('pair',pair,flush=True)
report=[]
for c in perf:
 b,a=[[r['ns']/r['count'] for r in rows if r['case']==c['name'] and r['variant']==v] for v in ['baseline','candidate']];ratios=[x/y for x,y in zip(a,b)];item=dict(case=c['name'],baseline=statistics.median(b),candidate=statistics.median(a),ratio=statistics.median(ratios),range=[min(ratios),max(ratios)]);report.append(item);print(item,flush=True)
(P/'report.json').write_text(json.dumps(report,indent=2));(P/'cases.json').write_text(json.dumps(perf,indent=2))
aa=[]
for pair in range(7):
 for c in [x for x in perf if x['name'] in ['empty','ordinary','comma','ascii-65536','negative']]:
  for side in ['A','B']:aa.append(dict(case=c['name'],pair=pair,side=side,**run(c,'baseline',c['count'])))
(P/'aa.json').write_text(json.dumps(aa,indent=2));print('AA done',flush=True)
