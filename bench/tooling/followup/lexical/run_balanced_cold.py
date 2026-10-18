#!/usr/bin/env python3
import hashlib,json,os,pathlib,subprocess
root=pathlib.Path(__file__).resolve().parent;out=root/'balanced-cold';out.mkdir(exist_ok=True)
env={**os.environ,'GOMAXPROCS':'4','GOGC':'100','GOMEMLIMIT':'off'}
records=[];binaries={side:root/(side+'-index-app')/'probe.test' for side in ['baseline','candidate']}
for n in [41,101]:
 order=['baseline','candidate','candidate','baseline']*5
 for sequence,side in enumerate(order):
  done=subprocess.run([str(binaries[side]),'-test.run=^TestLexical(ColdIndex|SerializerCoversInfo)$','-test.v'],env={**env,'LEXICAL_MODULES':str(n),'LEXICAL_LIBRARY':'0'},text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
  (out/f'app-{n}-{sequence:02d}-{side}.log').write_text(done.stdout)
  if done.returncode:raise SystemExit(done.stdout)
  row=[json.loads(line.split('lexical_cold=',1)[1]) for line in done.stdout.splitlines() if 'lexical_cold=' in line]
  assert len(row)==1
  records.append({'modules':n,'sequence':sequence,'side':side,**row[0]})
 print(f'passed balanced app-{n}: tenfreshprocesses per side',flush=True)
(out/'records.json').write_text(json.dumps({'order_per_size':['baseline','candidate','candidate','baseline']*5,'binary_sha256':{s:hashlib.sha256(p.read_bytes()).hexdigest() for s,p in binaries.items()},'records':records},indent=2)+'\n')
print(out/'records.json')
