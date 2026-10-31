import hashlib
import json
import os
from pathlib import Path
import subprocess

out=Path(__file__).resolve().parent
digest=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
record={'complete':False,'commands':[],'inputs':{},'programs':{}}
for name in ['states.json','rss-builds.json','protocol.md','fallback-source-proof.json','replay.py',
             'runner/string-normalize-ascii/compare_matrix.py','runner/string-lines/compare.py']:
    p=out/name;record['inputs'][str(p)]=digest(p)
for suite in ['reverse','normalize','byte','lines','text']:
    for suffix in ['programs','identities']:
        p=out/(suite+'-'+suffix+'.json');record['inputs'][str(p)]=digest(p)
    programs=json.loads((out/(suite+'-programs.json')).read_text())
    for label,path in programs.items():record['programs'][suite+'-'+label]={'path':path,'sha256':digest(path)}
rss=json.loads((out/'rss-builds.json').read_text());assert rss['complete']
for label,entry in rss['programs'].items():record['programs']['rss-'+label]=entry
record['programs']['rss-launcher']={'path':str(out/'rss-launcher'),'sha256':digest(out/'rss-launcher')}
record['affinity']=[0];os.sched_setaffinity(0,{0})
def save():(out/'replay-record.json').write_text(json.dumps(record,indent=2)+'\n')
save()
for suite in ['reverse','normalize','byte','lines','text']:
    args=['python3',str(out/'runner/string-normalize-ascii/compare_matrix.py'),str(out/(suite+'-programs.json')),
          str(out/(suite+'-identities.json')),str(out/(suite+'-matrix')),'--cpu','0']
    print(suite+' starting',flush=True)
    with (out/(suite+'-matrix.log')).open('wb') as log:r=subprocess.run(args,cwd=out,stdout=log,stderr=subprocess.STDOUT)
    record['commands'].append({'argv':args,'exit':r.returncode,'log':suite+'-matrix.log'});save();r.check_returncode()
    print(suite+' complete',flush=True)
rss_out=out/'rss-results';rss_out.mkdir()
rss_record={'complete':False,'units':'KiB single-child whole-process maximum RSS','samples':[]}
(rss_out/'record.json').write_text(json.dumps(rss_record,indent=2)+'\n')
labels=['baseline','word','reverse','both','rust']
for repetition in range(5):
    order=labels[repetition:]+labels[:repetition]
    for mode,expected in [('ascii',b'4194304\n'),('mixed',b'5242880\n')]:
        for label in order:
            prefix=f'{mode}-{repetition}-{label}'
            metrics=rss_out/(prefix+'.json');program=rss['programs'][label+'-'+mode]['path']
            args=[str(out/'rss-launcher'),str(metrics),program]
            r=subprocess.run(args,capture_output=True)
            (rss_out/(prefix+'.stdout')).write_bytes(r.stdout);(rss_out/(prefix+'.stderr')).write_bytes(r.stderr)
            item={'repetition':repetition,'order':order,'mode':mode,'label':label,'argv':args,'exit':r.returncode,
                  'stdout_matches':r.stdout==expected,'stderr_empty':not r.stderr,'metrics':json.loads(metrics.read_text()) if metrics.exists() else None}
            rss_record['samples'].append(item);(rss_out/'record.json').write_text(json.dumps(rss_record,indent=2)+'\n')
            assert r.returncode==0 and r.stdout==expected and not r.stderr and item['metrics']['maxrss_kib']>0,item
rss_record['complete']=True;(rss_out/'record.json').write_text(json.dumps(rss_record,indent=2)+'\n')
record['integrity_after']={p:digest(p)==h for p,h in record['inputs'].items()}
record['programs_integrity_after']={k:digest(v['path'])==v['sha256'] for k,v in record['programs'].items()}
assert all(record['integrity_after'].values()) and all(record['programs_integrity_after'].values())
record['complete']=True;save()
print('all matrices and50RSS children complete',flush=True)
