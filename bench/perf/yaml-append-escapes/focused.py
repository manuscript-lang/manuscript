"""Long A/A controls for cached-file operations; all baseline labels share a binary."""
import argparse
import hashlib
import json
import pathlib
import statistics
import subprocess
import sys

p=argparse.ArgumentParser()
for name in ['environment','summary','inputs','output']:
    p.add_argument('--'+name,type=pathlib.Path,required=True)
p.add_argument('--operation',choices=['writer'],required=True)
p.add_argument('--cases',nargs='+',required=True)
a=p.parse_args()
a.output.mkdir(parents=True,exist_ok=False)
meta=json.loads(a.environment.read_text())
group='binaries'
original=meta[group]
versions={'baseline-a':pathlib.Path(original['before']['path']),'baseline-b':pathlib.Path(original['before']['path']),'candidate':pathlib.Path(original['after']['path'])}
digest=lambda path:hashlib.sha256(path.read_bytes()).hexdigest()
for label,path in versions.items():
    if digest(path)!=original['after' if label=='candidate' else 'before']['sha256']:
        raise ValueError('binary differs from full matrix')
(a.output/'provenance.json').write_text(json.dumps({'command':sys.argv,'driver_sha256':digest(pathlib.Path(__file__)),
    'environment_sha256':digest(a.environment),'summary_sha256':digest(a.summary),
    'binaries':{k:{'path':str(v),'sha256':digest(v)} for k,v in versions.items()}},indent=2)+'\n')
source=json.loads(a.summary.read_text());rows=[]
for case in a.cases:
    path=(a.inputs/f'{case}.input').resolve()
    outputs={k:subprocess.check_output([v,path,'0']) for k,v in versions.items()}
    if len(set(outputs.values()))!=1:
        raise ValueError('before/after output changed')
    unit=len(outputs['baseline-a'])
    base=next(r for r in source if r['case']==case)
    count=max(1,int(700_000_000/base['distributions']['before']['median_ns']))
    labels=list(versions)
    for trial in range(12):
        order=labels[trial%3:]+labels[:trial%3]
        if trial%2:order.reverse()
        for label in order:
            ns,checksum,size=map(int,subprocess.check_output([versions[label],path,str(count)]).split())
            if ns<=0 or size!=unit or checksum!=unit*count:raise ValueError('wrong producer result')
            row=dict(operation=a.operation,case=case,label=label,trial=trial,count=count,ns=ns/count,output_bytes=unit)
            rows.append(row)
            with (a.output/'samples.jsonl').open('a') as log:log.write(json.dumps(row)+'\n')
summary=[]
for case in a.cases:
    d={}
    for label in versions:
        values=[r['ns'] for r in rows if r['case']==case and r['label']==label]
        if len(values)!=12:raise ValueError('missing samples')
        m=statistics.median(values);d[label]=dict(median_ns=m,mad_ns=statistics.median(abs(x-m) for x in values),min_ns=min(values),max_ns=max(values))
    summary.append(dict(operation=a.operation,case=case,distributions=d))
(a.output/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
for r in summary:print(r['case'],r['distributions'])
