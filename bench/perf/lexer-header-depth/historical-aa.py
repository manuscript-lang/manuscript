import hashlib
import json
import os
from pathlib import Path
import random
import statistics
import subprocess

root = Path('/workspace/perf-parser-evidence')
out = root/'header-buildpath-aa'
out.mkdir(exist_ok=False)
inputs = root/'header-current-main/inputs'
cases = {name: [inputs/(name+'.ms')] for name in ['tiny','function-1-lf','declarations-256']}
cases['stdlib'] = sorted((root/'lexer-work/stdlib').glob('*.ms'))
bins = {'different_path': root/'header-current-base/bench', 'same_path': root/'header-samepath-base/bench'}
os.sched_setaffinity(0,{min(os.sched_getaffinity(0))})
record = {'purpose':'A/A: identical e01fb141e production source, different package build paths; compiler flags and benchmark source unchanged',
          'baseline_revision':'e01fb141e','binaries':{key:hashlib.sha256(path.read_bytes()).hexdigest() for key,path in bins.items()},
          'validation':{},'samples':[]}
for case,files in cases.items():
    output=[subprocess.check_output([str(path),'validate',*map(str,files)]) for path in bins.values()]
    assert output[0]==output[1]
    record['validation'][case]=hashlib.sha256(output[0]).hexdigest()
rng=random.Random(1729)
for trial in range(10):
    work=[(case,mode) for case in cases for mode in ['lex','parse']]
    rng.shuffle(work)
    order=list(bins) if trial%2==0 else list(reversed(bins))
    for case,mode in work:
        for which in order:
            row=json.loads(subprocess.check_output([str(bins[which]),mode,*map(str,cases[case])],text=True))
            assert row['checksum']==row['units']*row['passes']
            row.update(case=case,mode=mode,which=which,trial=trial)
            record['samples'].append(row)
            (out/'results.json').write_text(json.dumps(record,indent=2)+'\n')
for case in cases:
    for mode in ['lex','parse']:
        med={key:statistics.median(row['elapsed_ns']/row['passes']/1000 for row in record['samples']
                                  if row['case']==case and row['mode']==mode and row['which']==key) for key in bins}
        print(case,mode,med,flush=True)
