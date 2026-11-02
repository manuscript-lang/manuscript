"""Controlled producer failures must reject before any final summary is written."""
import argparse
import hashlib
import json
import pathlib
import subprocess
import sys
import tempfile

p=argparse.ArgumentParser()
p.add_argument('--environment',type=pathlib.Path,required=True)
p.add_argument('--output',type=pathlib.Path,required=True)
a=p.parse_args()
meta=json.loads(a.environment.read_text())
root=pathlib.Path(__file__).resolve().parents[3]
records=[]
with tempfile.TemporaryDirectory(prefix='toml-fail-',dir=a.output.parent) as temp:
    directory=pathlib.Path(temp).resolve()
    scripts={
        'failed-producer':'import sys\nsys.exit(23)\n',
        'changed-output':'print(\'other = "wrong"\')\n',
        'wrong-checksum':f'''import os,sys
real={meta['binaries']['after']['path']!r}
if sys.argv[2]=='0':os.execv(real,[real,*sys.argv[1:]])
print('1\\t0\\t999999')
''',
    }
    for name,source in scripts.items():
        producer=directory/name
        marker=directory/(name+'-invoked')
        producer.write_text('#!/usr/bin/env python3\nimport pathlib\npathlib.Path('+repr(str(marker))+').write_text(\"invoked\")\n'+source)
        producer.chmod(0o700)
        command=[sys.executable,*meta['command']]
        target='--before' if name=='failed-producer' else '--after'
        command[command.index(target)+1]=str(producer)
        output=directory/(name+'-output')
        command[command.index('--output')+1]=str(output)
        result=subprocess.run(command,cwd=root,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=30)
        expected={'failed-producer':'returned non-zero exit status 23','changed-output':'changed output: roundtrip/empty','wrong-checksum':'invalid producer count/checksum'}[name]
        if result.returncode==0 or (output/'summary.json').exists() or not marker.exists() or expected not in result.stderr.decode():
            raise ValueError(f'failed to reject {name}')
        records.append({'case':name,'exit':result.returncode,'summary_written':False,'producer_invoked':True,'expected_failure':expected,
                        'stderr':result.stderr.decode(),'producer_sha256':hashlib.sha256(producer.read_bytes()).hexdigest()})
a.output.write_text(json.dumps({'driver_sha256':hashlib.sha256(pathlib.Path(__file__).read_bytes()).hexdigest(),
    'environment_sha256':hashlib.sha256(a.environment.read_bytes()).hexdigest(),'records':records},indent=2)+'\n')
print('All three invalid producers rejected without a final summary')
