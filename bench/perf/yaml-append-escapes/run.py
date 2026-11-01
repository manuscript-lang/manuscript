"""Matched YAML writer programs; fresh-file primary and reused-value exploratory."""
import argparse,hashlib,json,pathlib,platform,statistics,subprocess,sys
p=argparse.ArgumentParser()
for n in ['before','after','rust','output']:p.add_argument('--'+n,type=pathlib.Path,required=True)
p.add_argument('--mode',choices=['file','guarded'],required=True);a=p.parse_args();a.output.mkdir(exist_ok=False)
r=pathlib.Path(__file__).resolve().parent;digest=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
versions={k:getattr(a,k).resolve() for k in ['before','after','rust']}
meta={'command':sys.argv,'base':'024af5e2e544f7c9d2ccccc1c333b92b70db0ef3','mode':a.mode,'platform':platform.platform(),'rust':subprocess.check_output(['rustc','-vV'],text=True),'binaries':{k:{'path':str(v),'sha256':digest(v)} for k,v in versions.items()},'before_yaml_sha256':digest(r/'baseline-yaml.ms'),'after_yaml_sha256':digest(pathlib.Path('stdlib/yaml.ms')),'driver_sha256':digest(pathlib.Path(__file__)),'harness_sha256':{str(p.relative_to(r)):digest(p) for p in (r/'harness').rglob('*') if p.is_file() and 'target' not in p.parts},'native_archive_sha256':digest(pathlib.Path('target/ms-native/libms_native.a')),'trials':12,'flags':'Rust1.99.1 LLVM23.1.1; MS Release; Rust opt-level3 panicabort; repository framepointers; no concurrent builds/benchmarks','note':'Primary file mode rereads UTF8 inside every iteration, creates the same dynamic single-string map and stringifies with full equality guard. Setup/printing excluded; I/O/map creation/serialization/destruction timed. Guarded mode reuses an invariant value and is exploratory whole-program evidence only, not source-proof of per-iteration serialization. Counts calibrated separately and retained.'}
(a.output/'environment.json').write_text(json.dumps(meta,indent=2)+'\n')
cases={'empty':'','tiny':'Ada','common':'configuration value with spaces, punctuation and 0123456789','ascii16k':'abcdefgh01234567'*1024,'unicode16k':'é🙂日本語'*1024,'sparse':'abcdefgh01234567'*1024+'\n','dense':'"\\\n\r\t\b\f\0\x1f\x7f\x80\x9f'*1024,'mixed':'é🙂\n日本語\\'*1024}
if a.mode=='file':cases.update({'ascii1m':'abcdefgh'*131072,'sparse1m':'abcdefgh'*131072+'\n','dense1m':'\0\x1f\x80\x9f'*131072})
rows=[]
for case,text in cases.items():
 path=(a.output/(case+'.input')).resolve();path.write_bytes(text.encode());outputs={k:subprocess.check_output([v,path,'0']) for k,v in versions.items()}
 if outputs['before']!=outputs['after']:raise ValueError('changed YAML bytes '+case)
 for k,out in outputs.items():
  outpath=(a.output/(case+'-'+k+'.out')).resolve();outpath.write_bytes(out);subprocess.run([versions['rust'],'--validate',path,outpath],check=True,stderr=subprocess.PIPE)
 def invoke(k,count):
  ns,checksum,size=map(int,subprocess.check_output([versions[k],path,str(count)]).split())
  if ns<=0 or size!=len(outputs[k]) or checksum!=size*count:raise ValueError('wrong producer count/checksum')
  return ns/count
 counts={}
 for k in versions:
  count=1
  while True:
   unit=invoke(k,count)
   if unit*count>=50_000_000 or count>=1_000_000:break
   count=min(max(count+1,int(60_000_000/unit)),count*10,1_000_000)
  counts[k]=count
 labels=list(versions)
 for trial in range(12):
  order=labels[trial%3:]+labels[:trial%3]
  if trial%2:order.reverse()
  for k in order:
   row={'case':case,'label':k,'trial':trial,'count':counts[k],'ns':invoke(k,counts[k]),'unit':len(outputs[k])};rows.append(row)
   with (a.output/'samples.jsonl').open('a') as f:f.write(json.dumps(row)+'\n')
summary=[]
for case in cases:
 d={}
 for k in versions:
  v=[x['ns'] for x in rows if x['case']==case and x['label']==k]
  if len(v)!=12:raise ValueError('missing observation')
  m=statistics.median(v);d[k]={'median_ns':m,'mad_ns':statistics.median(abs(x-m) for x in v),'min_ns':min(v),'max_ns':max(v)}
 summary.append({'case':case,'distributions':d,'before_over_after':d['before']['median_ns']/d['after']['median_ns'],'after_over_rust':d['after']['median_ns']/d['rust']['median_ns']})
(a.output/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
for row in summary:print(row['case'],row['before_over_after'],row['after_over_rust'])
