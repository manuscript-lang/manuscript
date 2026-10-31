import json, subprocess, statistics, pathlib, hashlib, platform
root=pathlib.Path('/workspace/scratch/encoding-perf')
repo=pathlib.Path('/workspace/manuscript')
out=root/'optimized-rust'; out.mkdir(exist_ok=True)
files={'ascii':'encoding_ascii_bench.ms'}
raw={v:{} for v in ['before','after','rust']}
identities={}
for group,file in files.items():
 for i in range(5):
  versions=['before','after'] if i%2==0 else ['after','before']
  if group=='ascii':
   if i%2==0: versions+=['rust']
   else: versions=['rust']+versions
  for v in versions:
   cmd=[str(root/'rust')] if v=='rust' else [str(root/f'ms-{v}'),'bench',str(repo/'bench/perf/stdlib'/file),'--json','--samples','5' if group=='ascii' else '3','--time','100ms']
   r=subprocess.run(['taskset','-c','0',*cmd],capture_output=True,text=True,check=True)
   (out/f'{group}-{i}-{v}.json').write_text(r.stdout)
   (out/f'{group}-{i}-{v}.stderr').write_text(r.stderr)
   if v=='rust':
    parsed=[json.loads(line) for line in r.stdout.splitlines()]
    rows={x['name']:statistics.median(x['samples']) for x in parsed}
    identity={name:1 for name in rows}
   else:
    d=json.loads(r.stdout)
    assert d['completed'] and d['exit_code']==0,d
    parsed=d['benches']
    assert all(x['status']=='passed' and x['stats']['samples']==(5 if group=='ascii' else 3) for x in parsed),d
    rows={x['name'].split('::')[-1]:x['stats']['median_ns'] for x in parsed}
    identity={x['name'].split('::')[-1]:x['stats']['operations'] for x in parsed}
   assert len(parsed)==len(rows),'duplicate names'
   assert len(rows)==23,'ASCII coverage changed'
   if group not in identities: identities[group]=identity
   assert identity==identities[group],(v,group,identity,identities[group])
   for name,value in rows.items(): raw[v].setdefault(name,[]).append(value)
   print('completed',group,i,v,flush=True)
summary={}
for name in raw['before']:
 med={v:statistics.median(raw[v][name]) for v in raw if name in raw[v]}
 summary[name]={**med,'ratio':med['after']/med['before'],'distributions':{v:{'min':min(raw[v][name]),'max':max(raw[v][name]),'cv':statistics.pstdev(raw[v][name])/statistics.mean(raw[v][name])} for v in med}}
(out/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
(out/'process-medians.json').write_text(json.dumps(raw,indent=2)+'\n')
(out/'identities.json').write_text(json.dumps(identities,indent=2)+'\n')
paths=[root/'ms-before',root/'ms-after',root/'rust',root/'rust.rs',repo/'stdlib/encoding.ms',*[repo/'bench/perf/stdlib'/f for f in files.values()]]
metadata={'base_revision':subprocess.check_output(['git','rev-parse','HEAD'],cwd=repo,text=True).strip(),'platform':platform.platform(),'cpu':'AMD EPYC 9V45 96-Core Processor','cpu_affinity':'0','cpu_quota':'4 cores','rust':subprocess.check_output(['/workspace/.cargo/bin/rustc','--version'],text=True).strip(),'hashes':{str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}}
(out/'environment.json').write_text(json.dumps(metadata,indent=2)+'\n')
print(json.dumps(summary,indent=2))
