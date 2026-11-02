import argparse,hashlib,json,pathlib,statistics,subprocess,sys
p=argparse.ArgumentParser()
for n in ['environment','inputs','rss','output']:p.add_argument('--'+n,type=pathlib.Path,required=True)
a=p.parse_args();a.output.mkdir(exist_ok=False);meta=json.loads(a.environment.read_text());digest=lambda p:hashlib.sha256(p.read_bytes()).hexdigest();versions={k:pathlib.Path(v['path']) for k,v in meta['binaries'].items()}
for k,v in versions.items():
 if digest(v)!=meta['binaries'][k]['sha256']:raise ValueError('changed binary')
(a.output/'environment.json').write_text(json.dumps({'command':sys.argv,'driver_sha256':digest(pathlib.Path(__file__)),'timing_environment_sha256':digest(a.environment),'binaries':meta['binaries'],'rss_sha256':digest(a.rss),'note':'Fresh child whole-process RSS includes setup, semantic full-output guards, 3 cached-file reads/map-creation/stringify operations; not allocation counts.'},indent=2)+'\n')
rows=[];labels=list(versions)
for case in ['ascii1m','sparse1m','dense1m','unicode16k','dense']:
 path=(a.inputs/(case+'.input')).resolve();outputs={k:subprocess.check_output([v,path,'0']) for k,v in versions.items()}
 if outputs['before']!=outputs['after']:raise ValueError('changed bytes')
 for trial in range(6):
  order=labels[trial%3:]+labels[:trial%3]
  if trial%2:order.reverse()
  for k in order:
   metric=(a.output/f'{case}-{k}-{trial}.json').resolve();ns,checksum,size=map(int,subprocess.check_output([a.rss.resolve(),metric,versions[k],path,'3']).split())
   if ns<=0 or size!=len(outputs[k]) or checksum!=3*size:raise ValueError('wrong producer')
   rows.append({'case':case,'label':k,'trial':trial,**json.loads(metric.read_text())})
expected={(c,k,t) for c in ['ascii1m','sparse1m','dense1m','unicode16k','dense'] for k in labels for t in range(6)}
if len(rows)!=90 or {(r['case'],r['label'],r['trial']) for r in rows}!=expected:raise ValueError('missing observation')
(a.output/'samples.json').write_text(json.dumps(rows,indent=2)+'\n')
for case in dict.fromkeys(r['case'] for r in rows):print(case,{k:statistics.median(r['maxrss_kib'] for r in rows if r['case']==case and r['label']==k) for k in labels})
