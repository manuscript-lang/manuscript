"""Long TOML integration controls; reject confirmed common-path regressions."""
import argparse
import hashlib
import json
import pathlib
import statistics
import subprocess
import tomllib

p = argparse.ArgumentParser()
for name in ['before', 'after', 'summary', 'output']:
    p.add_argument('--' + name, type=pathlib.Path, required=True)
a = p.parse_args()
a.output.mkdir(parents=True, exist_ok=False)
versions = {'baseline-a': a.before.resolve(), 'baseline-b': a.before.resolve(), 'candidate': a.after.resolve()}
(a.output / 'binaries.json').write_text(json.dumps({k: {'path': str(v), 'sha256': hashlib.sha256(v.read_bytes()).hexdigest()} for k,v in versions.items()}, indent=2) + '\n')
source = json.loads(a.summary.read_text())
cases = {'common': 'configuration value with spaces, punctuation and 0123456789',
         'ascii-16k': 'abcdefgh01234567' * 1024,
         'sparse-escape': 'abcdefgh01234567' * 1024 + '\n',
         'dense-escape': '\"\\\n\r\t\b\f\x00\x1f\x7f' * 1024}
rows=[]
for case,text in cases.items():
    path=(a.output/(case+'.txt')).resolve();path.write_text(text)
    outputs={k:subprocess.check_output([v,path,'0']) for k,v in versions.items()}
    if len(set(outputs.values())) != 1 or tomllib.loads(outputs['baseline-a'].decode()) != {'value': text}:
        raise ValueError('full output mismatch')
    size=len(outputs['baseline-a']);original=next(r for r in source if r['case']==case)
    count=max(1,int(700_000_000/original['distributions']['before']['median_ns']))
    labels=list(versions)
    for trial in range(12):
        order=labels[trial%3:]+labels[:trial%3]
        if trial%2:order.reverse()
        for label in order:
            ns,checksum,unit=map(int,subprocess.check_output([versions[label],path,str(count)]).split())
            if ns<=0 or unit!=size or checksum!=count*size:raise ValueError('producer mismatch')
            row=dict(case=case,label=label,trial=trial,count=count,ns=ns/count,unit=unit)
            rows.append(row)
            with (a.output/'samples.jsonl').open('a') as out:out.write(json.dumps(row)+'\n')
summary=[]
for case in cases:
    d={}
    for label in versions:
        values=[r['ns'] for r in rows if r['case']==case and r['label']==label]
        if len(values)!=12:raise ValueError('missing samples')
        m=statistics.median(values);d[label]=dict(median_ns=m,mad_ns=statistics.median(abs(v-m) for v in values),min_ns=min(values),max_ns=max(values))
    summary.append(dict(case=case,distributions=d))
(a.output/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
for row in summary:print(row['case'],row['distributions'])
